/*
 * Copyright (c) 2004-2006 Apple Inc.  All Rights Reserved.
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

/***********************************************************************
* objc-loadmethod.m
* Support for +load methods.
**********************************************************************/

#include "objc-loadmethod.h"
#include "objc-private.h"

typedef void(*load_method_t)(id, SEL);

struct loadable_class {
    Class cls;  // may be nil
    IMP method;
};

struct loadable_category {
    Category cat;  // may be nil
    IMP method;
};


// List of classes that need +load called (pending superclass +load)
// This list always has superclasses first because of the way it is constructed
// 需要+load的类的列表（等待超类+load）
// 这个列表总是先有超类，因为它的构造方式
static struct loadable_class *loadable_classes = nil;
static int loadable_classes_used = 0;
static int loadable_classes_allocated = 0;

// List of categories that need +load called (pending parent class +load)
static struct loadable_category *loadable_categories = nil;
static int loadable_categories_used = 0;
static int loadable_categories_allocated = 0;


/***********************************************************************
* add_class_to_loadable_list
* Class cls has just become connected. Schedule it for +load if
* it implements a +load method.
 * Class cls刚刚连接起来。如果它实现了+Load方法，则为+Load调度它。
 * 该方法会不断的被调用，每次调用 loadable_classes_used = 0
**********************************************************************/
void add_class_to_loadable_list(Class cls)
{
    IMP method;

    loadMethodLock.assertLocked();

    method = cls->getLoadMethod();
    if (!method) return;  // Don't bother if cls has no +load method
    
    if (PrintLoading) {
        _objc_inform("LOAD: class '%s' scheduled for +load", 
                     cls->nameForLogging());
    }
    
    if (loadable_classes_used == loadable_classes_allocated) {
        loadable_classes_allocated = loadable_classes_allocated*2 + 16;
        loadable_classes = (struct loadable_class *)
            realloc(loadable_classes,
                              loadable_classes_allocated *
                              sizeof(struct loadable_class));
    }
    
    loadable_classes[loadable_classes_used].cls = cls;
    loadable_classes[loadable_classes_used].method = method;
    loadable_classes_used++;
    _objc_inform("add_class_to_loadable_list = %s===%d\n",object_getClassName(cls),loadable_classes_used);
}


/***********************************************************************
* add_category_to_loadable_list
* Category cat's parent class exists and the category has been attached
* to its class. Schedule this category for +load after its parent class
* becomes connected and has its own +load method called.
 * Category 父类存在以及category已经附加到他的类。
 * 在他的父类已连接并且父类的+load方法被调用之后再来调度category的+load。
 * 该方法会不断的被调用，每次调用 loadable_categories_used = 0
**********************************************************************/
void add_category_to_loadable_list(Category cat)
{
    IMP method;

    loadMethodLock.assertLocked();

    method = _category_getLoadMethod(cat);

    // Don't bother if cat has no +load method
    if (!method) return;

    if (PrintLoading) {
        _objc_inform("LOAD: category '%s(%s)' scheduled for +load", 
                     _category_getClassName(cat), _category_getName(cat));
    }
    
    if (loadable_categories_used == loadable_categories_allocated) {
        loadable_categories_allocated = loadable_categories_allocated*2 + 16;
        loadable_categories = (struct loadable_category *)
            realloc(loadable_categories,
                              loadable_categories_allocated *
                              sizeof(struct loadable_category));
    }

    loadable_categories[loadable_categories_used].cat = cat;
    loadable_categories[loadable_categories_used].method = method;
    loadable_categories_used++;
    _objc_inform("add_category_to_loadable_list = %s===%d\n",cat->name,loadable_categories_used);
}


/***********************************************************************
* remove_class_from_loadable_list
* Class cls may have been loadable before, but it is now no longer 
* loadable (because its image is being unmapped).
* 镜像未映射
**********************************************************************/
void remove_class_from_loadable_list(Class cls)
{
    loadMethodLock.assertLocked();

    if (loadable_classes) {
        int i;
        for (i = 0; i < loadable_classes_used; i++) {
            if (loadable_classes[i].cls == cls) {
                loadable_classes[i].cls = nil;
                if (PrintLoading) {
                    _objc_inform("LOAD: class '%s' unscheduled for +load", 
                                 cls->nameForLogging());
                }
                return;
            }
        }
    }
}


/***********************************************************************
* remove_category_from_loadable_list
* Category cat may have been loadable before, but it is now no longer 
* loadable (because its image is being unmapped). 
**********************************************************************/
void remove_category_from_loadable_list(Category cat)
{
    loadMethodLock.assertLocked();

    if (loadable_categories) {
        int i;
        for (i = 0; i < loadable_categories_used; i++) {
            if (loadable_categories[i].cat == cat) {
                loadable_categories[i].cat = nil;
                if (PrintLoading) {
                    _objc_inform("LOAD: category '%s(%s)' unscheduled for +load",
                                 _category_getClassName(cat), 
                                 _category_getName(cat));
                }
                return;
            }
        }
    }
}


/***********************************************************************
* call_class_loads
* Call all pending class +load methods.
* If new classes become loadable, +load is NOT called for them.
*
* 调用所有挂起的类+load方法。
* Called only by call_load_methods().
**********************************************************************/
static void call_class_loads(void)
{
    int i;
    
    // Detach current loadable list.
    struct loadable_class *classes = loadable_classes;
    int used = loadable_classes_used;
    
    //还原初始设置
    loadable_classes = nil;
    loadable_classes_allocated = 0;
    loadable_classes_used = 0;
    
    // Call all +loads for the detached list.
    for (i = 0; i < used; i++) {
        Class cls = classes[i].cls;
        load_method_t load_method = (load_method_t)classes[i].method;
        if (!cls) continue; 

        if (PrintLoading) {
            _objc_inform("LOAD: +[%s load]\n", cls->nameForLogging());
        }
        //调用class load方法
        (*load_method)(cls, SEL_load);
    }
    
    // Destroy the detached list.
    if (classes) free(classes);
}


/***********************************************************************
* call_category_loads
* Call some pending category +load methods.
* The parent class of the +load-implementing categories has all of 
*   its categories attached, in case some are lazily waiting for +initalize.
* Don't call +load unless the parent class is connected.
* If new categories become loadable, +load is NOT called, and they 
*   are added to the end of the loadable list, and we return TRUE.
* Return FALSE if no new categories became loadable.
*
* Called only by call_load_methods().
*
* 调用一些pending（未决的）category +load方法。
* 父类的+load-implementing categories有其所有类别的附加，以防有一些懒惰的等待+initalize。
* 除非父类被连接，否则不要调用+load。
* 如果新的类别成为可加载的，+load不被调用，并且它们被添加到可加载列表的末尾，并且我们返回true。
* 如果没有新的类别载入，返回错误。
* 只被 call_load_methods()调用。
**********************************************************************/
static bool call_category_loads(void)
{
    int i, shift;
    bool new_categories_added = NO;
    
    // Detach(分离/分派) current loadable list.
    struct loadable_category *cats = loadable_categories;
    int used = loadable_categories_used;
    int allocated = loadable_categories_allocated;
    
    //还原初始设置
    loadable_categories = nil;
    loadable_categories_allocated = 0;
    loadable_categories_used = 0;

    // Call all +loads for the detached list.
    for (i = 0; i < used; i++) {
        Category cat = cats[i].cat;
        load_method_t load_method = (load_method_t)cats[i].method;
        Class cls;
        if (!cat) continue;

        // 父类
        cls = _category_getClass(cat);
        // 满足这个条件（类存在并且类的load已经调用）！！！才调用category的load，否则不管
        if (cls  &&  cls->isLoadable()) {
            if (PrintLoading) {
                _objc_inform("LOAD: +[%s(%s) load]\n", 
                             cls->nameForLogging(), 
                             _category_getName(cat));
            }
            // 调用 category的load
            (*load_method)(cls, SEL_load);
            cats[i].cat = nil;
        }
    }

    // Compact detached list (order-preserving)
    // 紧凑的分离列表（保序）  将已经load的category移除，并筛选出未加载load的category。
    shift = 0;
    for (i = 0; i < used; i++) {
        if (cats[i].cat) {
            cats[i-shift] = cats[i];
        } else {
            shift++;
        }
    }
    used -= shift;

    // Copy any new +load candidates from the new list to the detached list.
    // 另存储未加载 load方法的category
    new_categories_added = (loadable_categories_used > 0);
    for (i = 0; i < loadable_categories_used; i++) {
        if (used == allocated) {
            allocated = allocated*2 + 16;
            cats = (struct loadable_category *)
                realloc(cats, allocated *
                                  sizeof(struct loadable_category));
        }
        cats[used++] = loadable_categories[i];
    }

    // Destroy the new list.
    if (loadable_categories) free(loadable_categories);

    // Reattach the (now augmented) detached list. 
    // But if there's nothing left to load, destroy the list.
    if (used) {
        loadable_categories = cats;
        loadable_categories_used = used;
        loadable_categories_allocated = allocated;
    } else {
        if (cats) free(cats);
        loadable_categories = nil;
        loadable_categories_used = 0;
        loadable_categories_allocated = 0;
    }

    if (PrintLoading) {
        if (loadable_categories_used != 0) {
            _objc_inform("LOAD: %d categories still waiting for +load\n",
                         loadable_categories_used);
        }
    }

    return new_categories_added;
}


/***********************************************************************
* call_load_methods
* Call all pending class and category +load methods.
* Class +load methods are called superclass-first. 
* Category +load methods are not called until after the parent class's +load.
* 
* This method must be RE-ENTRANT, because a +load could trigger 
* more image mapping. In addition, the superclass-first ordering 
* must be preserved in the face of re-entrant calls. Therefore, 
* only the OUTERMOST call of this function will do anything, and 
* that call will handle all loadable classes, even those generated 
* while it was running.
*
* The sequence below preserves +load ordering in the face of 
* image loading during a +load, and make sure that no 
* +load method is forgotten because it was added during 
* a +load call.
* Sequence:
* 1. Repeatedly call class +loads until there aren't any more
* 2. Call category +loads ONCE.
* 3. Run more +loads if:
*    (a) there are more classes to load, OR
*    (b) there are some potential category +loads that have 
*        still never been attempted.
* Category +loads are only run once to ensure "parent class first" 
* ordering, even if a category +load triggers a new loadable class 
* and a new loadable category attached to that class. 
*
* Locking: loadMethodLock must be held by the caller 
*   All other locks must not be held.
 
 * 调用所有挂起的类和类别的+Load方法。
 * class +load方法称为superclass-first。
 * Category +Load方法直到父类的 +Load之后才被调用。
 *
 * 此方法必须是可重新进入的，因为+Load可能会触发更多的图像映射。
 * 此外，在面对可重入调用时，必须保留超类优先排序。
 * 因此，只有这个函数的最外面的调用才能做任何事情，并且那个调用将处理所有可加载的类，甚至那些在运行时生成的类。
 *
 * 下面的序列保留了+Load在+Load期间面对图像加载时的+Load排序，并确保没有忘记+Load方法，因为它是在+Load调用期间添加的。
 * 顺序:
 * 1.反复调用class +loads，直到不再有
 * 2.调用category +loads一次。
 * 3.运行更多的+loads，如果:
 *   （a）有更多的类加载，或
 *    (b) 仍有一些潜在的category +loads从未尝试过。
 * Category +loads只运行一次以确保“父类优先”排序，即使Category +loads触发了新的可加载类和附加到该类的新可加载Category。
 *
 * 总结一句话：父类优先，category只加载一次！
**********************************************************************/
void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;

    loadMethodLock.assertLocked();

    // Re-entrant calls do nothing; the outermost call will finish the job.
    // 重入调用不做任何事情；最外面的调用将完成工作。 （最外面的完成什么工作？）
    // 加了锁 还加了一个静态变量来控制。双重保障？（商榷）
    if (loading) return;
    loading = YES;

    // 使用了autoReleasePool
    void *pool = objc_autoreleasePoolPush();

    do {
        // 1. Repeatedly call class +loads until there aren't any more
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        // 2. Call category +loads ONCE
        more_categories = call_category_loads();

        // 3. Run more +loads if there are classes OR more untried categories
    } while (loadable_classes_used > 0  ||  more_categories);

    objc_autoreleasePoolPop(pool);

    loading = NO;
}


