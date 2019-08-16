//
//  main.m
//  KFObjc4-test
//
//  Created by 冯哲 on 2019/7/30.
//

#import <Foundation/Foundation.h>
#import "Person.h"
#import "Person+Social.h"
#import <objc/message.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        Person *p1 = [[Person alloc] init];
        
        [p1 personName:@"123"];
//        [p1 personAddress:@"456"];
//        [p1 runTests];
        
        
        for (int i = 0; i < 10; i ++) {
            @autoreleasepool {
                NSString *str = [NSString stringWithFormat:@"%d",i];
                NSMutableArray *tempA = [NSMutableArray array];
                [tempA addObject:str];
                
                /*
                 * 为什么运行环境不要写NSLog，内部执行复杂、耗时。
                 * _NS_os_log_callback -> objc_autoreleasePoolPush 等等
                **/
//                NSLog(@" === %@",str);
            }
        }
        
//        id __weak p2 = p1;
//        for (int i = 0; i < 5; i ++) {
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                //Tagged Pointer
//                [p2 personName:[NSString stringWithFormat:@"12345678+%d",i]];
//            });
//        }
        
        
        
        
        BOOL res1 = [(id)[NSObject class] isKindOfClass:[NSObject class]];
        BOOL res2 = [(id)[NSObject class] isMemberOfClass:[NSObject class]];
        BOOL res3 = [(id)[Person class] isKindOfClass:[Person class]];
        BOOL res4 = [(id)[Person class] isMemberOfClass:[Person class]];
        BOOL res5 = [p1 isKindOfClass:[NSObject class]];
        BOOL res6 = [p1 isMemberOfClass:[Person class]];
        
        NSLog(@"res1==%d=res2=%d=res3=%d=res4=%d=res5=%d=res6=%d",res1,res2,res3,res4,res5,res6);
    }
    return 0;
}
