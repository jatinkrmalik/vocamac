// VocaObjCExceptionCatcher.m
// VocaMac

#import "VocaMacObjC.h"

@implementation VocaObjCExceptionCatcher

+ (NSError * _Nullable)catchException:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSString *name = exception.name ?: @"NSException";
        NSString *reason = exception.reason ?: @"Objective-C exception raised";

        return [NSError errorWithDomain:@"com.vocamac.objc-exception"
                                   code:1
                               userInfo:@{
                                   NSLocalizedDescriptionKey: reason,
                                   @"NSExceptionName": name
                               }];
    }
}

@end
