//
//  main.m
//  KFObjc4-test
//
//  Created by 冯哲 on 2019/7/30.
//

#import <Foundation/Foundation.h>
#import "Person.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        Person *p1 = [[Person alloc] init];
        
//        [p1 personName:@"123"];
        [p1 personAddress:@"456"];
//        [p1 runTests];
        
        id __weak p2 = p1;
        for (int i = 0; i < 5; i ++) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //Tagged Pointer
                [p2 personName:[NSString stringWithFormat:@"12345678+%d",i]];
            });
        }
    }
    return 0;
}
