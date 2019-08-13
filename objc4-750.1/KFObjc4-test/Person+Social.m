//
//  Person+Social.m
//  KFObjc4-test
//
//  Created by youma001 on 2019/8/12.
//

#import "Person+Social.h"

@implementation Person (Social)

+ (void)load {
    NSLog(@"current Social load!!!");
}

// category的方法被放到了新方法列表的前面，而原来类的方法被放到了新方法列表的后面，这也就是我们平常所说的category的方法会“覆盖”掉原来类的同名方法，这是因为运行时在查找方法的时候是顺着方法列表的顺序查找的，它只要一找到对应名字的方法，就会罢休^_^，殊不知后面可能还有一样名字的方法。
//- (void)personName:(NSString *)arg1 {
//    NSLog(@"123456");
//}

@end
