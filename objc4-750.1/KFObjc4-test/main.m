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
        
        [p1 personName:@"123"];
        [p1 personAddress:@"456"];
        [p1 runTests];
        
    }
    return 0;
}
