/*
 * Copyright (c) 2010-2011 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#ifndef _OBJC_WEAK_H_
#define _OBJC_WEAK_H_

#include <objc/objc.h>
#include "objc-config.h"

__BEGIN_DECLS

/*
The weak table is a hash table governed by a single spin lock.
An allocated blob of memory, most often an object, but under GC any such 
allocation, may have its address stored in a __weak marked storage location 
through use of compiler generated write-barriers or hand coded uses of the 
register weak primitive. Associated with the registration can be a callback 
block for the case when one of the allocated chunks of memory is reclaimed. 
The table is hashed on the address of the allocated memory.  When __weak 
marked memory changes its reference, we count on the fact that we can still 
see its previous reference.

So, in the hash table, indexed by the weakly referenced item, is a list of 
all locations where this address is currently being stored.
 
For ARC, we also keep track of whether an arbitrary object is being 
deallocated by briefly placing it in the table just prior to invoking 
dealloc, and removing it via objc_clear_deallocating just prior to memory 
reclamation.
 
 弱表是由单个自旋锁控制的  “哈希表”。一个已分配的内存块，通常是一个对象，但在GC下是这样的分配，
 可以将其地址存储在__weak标记的存储位置通过使用编译器生成的写屏障或手动编码使用的注册弱原语。
 与注册相关联可以是回调阻止其中一个分配的内存块被回收的情况。该表在已分配内存的地址上进行哈希处理。
 当__weak标记记忆改变了它的reference（参考），我们指望我们仍然可以看它以前的reference（参考）。
 
 因此，在哈希表中，由弱引用项索引，是一个列表 当前存储此地址的所有位置。
  
 对于ARC，我们还会跟踪是否正在释放任意对象，方法是在调用dealloc之前将其短暂放置在表中，
 并在内存回收之前通过objc_clear_delocating将其删除。

*/

// The address of a __weak variable.
// These pointers are stored disguised(伪装) so memory analysis tools
// don't see lots of interior pointers from the weak table into objects.
// 这些指针被隐藏起来，所以内存分析工具没有看到从弱表到对象的许多内部指针。
typedef DisguisedPtr<objc_object *> weak_referrer_t;

#if __LP64__
#define PTR_MINUS_2 62
#else
#define PTR_MINUS_2 30
#endif

/**
 * The internal structure stored in the weak references table. 
 * It maintains and stores
 * a hash set of weak references pointing to an object.
 * If out_of_line_ness != REFERRERS_OUT_OF_LINE then the set
 * is instead a small inline array.
 *
 * 内部结构存储在弱引用表中。
 * 它维护并存储指向对象的弱引用的散列集。
 * 如果 out_of_line_ness != REFERRERS_OUT_OF_LINE 然后设置为一个小的内联数组。  为什么这么做呢？
 */
#define WEAK_INLINE_COUNT 4

// out_of_line_ness field overlaps with the low two bits of inline_referrers[1].
// inline_referrers[1] is a DisguisedPtr of a pointer-aligned address.
// The low two bits of a pointer-aligned DisguisedPtr will always be 0b00
// (disguised nil or 0x80..00) or 0b11 (any other address).
// Therefore out_of_line_ness == 0b10 is used to mark the out-of-line state.
/*
 * 不是很理解 哈哈哈
 * out_of_line_ness字段与inline_referrers[1]低两位重叠。
 * inlineReferrers[1]是指针对齐地址的DisguisedPtr。
 * 指针对齐的DisguisedPtr的低两位将始终为0b00(伪装为零或0x80..00)或0b11(任何其他地址)。
 * 因此，out-oftlineClineNess == 0B10用于标记out-of-line状态。
 *
 */
#define REFERRERS_OUT_OF_LINE 2

struct weak_entry_t {
    /*
     * 模版类指针 待研究！！！(伪装指针，不知道干嘛用的)
     */
    DisguisedPtr<objc_object> referent;
    
    /*
     * union 多成员共享同一且相同大小的内存空间
     */
    union {
        struct {
            weak_referrer_t *referrers;
            uintptr_t        out_of_line_ness : 2;
            uintptr_t        num_refs : PTR_MINUS_2;
            uintptr_t        mask;
            uintptr_t        max_hash_displacement;
        };
        struct {
            // out_of_line_ness field is low bits of inline_referrers[1]
            /*
             * 如果某一对象对应的弱引用 <= WEAK_INLINE_COUNT(4)时,那么弱引用将保存在inline数组中;
             * 如果对应的弱引用数量 > WEAK_INLINE_COUNT(4)时,那么弱引用将保存在outline数组中;
             * 实现逻辑见 objc-weak::append_referrer
             */
            weak_referrer_t  inline_referrers[WEAK_INLINE_COUNT];
        };
    };

    bool out_of_line() {
        return (out_of_line_ness == REFERRERS_OUT_OF_LINE);
    }

    weak_entry_t& operator=(const weak_entry_t& other) {
        memcpy(this, &other, sizeof(other));
        return *this;
    }

    weak_entry_t(objc_object *newReferent, objc_object **newReferrer)
        : referent(newReferent)
    {
        inline_referrers[0] = newReferrer;
        for (int i = 1; i < WEAK_INLINE_COUNT; i++) {
            inline_referrers[i] = nil;
        }
    }
};

/**
 * The global weak references table. Stores object ids as keys,
 * and weak_entry_t structs as their values.
 * 全局弱引用表。将对象ID存储为键，将weak_entry_t结构存储为它们的值。
 */
struct weak_table_t {
    weak_entry_t *weak_entries;          // weak_table_t中具体存储的值的类型，负责记录一个对象和其弱引用的对应关系
    size_t    num_entries;               // 当前保存的entry的数目
    uintptr_t mask;                      // 记录weak_table_t的总容量
    uintptr_t max_hash_displacement;     // 记录weak_table_t所有项的最大偏移量 因为会有hash碰撞的情况，而weak_table_t采用了  开放寻址       来解决，所以某个entry实际存储的位置并不一定是hash函数计算出来的位置。
};

//以下对外开放接口 均线程不安全
/// Adds an (object, weak pointer) pair to the weak table.
/// 向弱表中添加（对象，弱指针）对。
id weak_register_no_lock(weak_table_t *weak_table, id referent, 
                         id *referrer, bool crashIfDeallocating);

/// Removes an (object, weak pointer) pair from the weak table.
/// 从弱表中移除（对象，弱指针）对。
void weak_unregister_no_lock(weak_table_t *weak_table, id referent, id *referrer);

#if DEBUG
/// Returns true if an object is weakly referenced somewhere.
/// 如果某个对象在某处被弱引用，则返回true。
bool weak_is_registered_no_lock(weak_table_t *weak_table, id referent);
#endif

/// Called on object destruction. Sets all remaining weak pointers to nil.
/// 对象析构时调用。设置所有剩余的弱指针为零。
void weak_clear_no_lock(weak_table_t *weak_table, id referent);

__END_DECLS

#endif /* _OBJC_WEAK_H_ */
