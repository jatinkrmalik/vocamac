// VocaMacObjC.h
// VocaMac
//
// Objective-C helpers used by the Swift app.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VocaObjCExceptionCatcher : NSObject

/// Executes a block and converts any Objective-C NSException into an NSError.
///
/// Some AVFoundation APIs, including AVAudioNode tap installation, report
/// programmer/precondition failures by raising NSException instead of throwing
/// Swift/Objective-C NSError values. Swift cannot catch NSException directly,
/// so this helper prevents those framework exceptions from aborting the app.
+ (NSError * _Nullable)catchException:(NS_NOESCAPE void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
