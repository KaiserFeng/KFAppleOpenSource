//
//  Person.m
//  KFObjc4-test
//
//  Created by kaiser on 2019/8/6.
//

#import "Person.h"
//#import <objc/runtime.h>

@interface Person ()

@property (nonatomic, copy) NSString *name;   //!< 姓名
@property (nonatomic, strong) NSString *address;  //!<地址
@property (nonatomic, copy) NSString *titleName;   //!< 标题

@end

@implementation Person

- (void)dealloc
{
    NSLog(@"%s",__FUNCTION__);
}

+ (void)load {
    NSLog(@"current load!!!");
}


- (void)personName:(NSString *)arg1 {
    NSLog(@"====%@",arg1);
    self.name = arg1;       // msg_send(self,"setName") -> objc_storeWeak(arg1, address)
//    self.name = arg1;
//    self.titleName = arg1;  // msg_send(self,"setTitleName") -> objc_setProperty_nonatomic_copy -> copyWithZone
}

- (void)personAddress:(NSString *)arg1 {
    self.address = arg1;
    self.address = arg1;
}


//- (void)runTests
//{
//    unsigned int count;
//    Method *methods = class_copyMethodList([self class], &count);
//    for (int i = 0; i < count; i++)
//    {
//        Method method = methods[i];
//        SEL selector = method_getName(method);
//        NSString *name = NSStringFromSelector(selector);
//        NSLog(@"Person '%@' completed successfuly", name);
//    }
//}

@end
