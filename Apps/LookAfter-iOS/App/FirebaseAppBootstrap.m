#import <Foundation/Foundation.h>
@import FirebaseCore;

/// Runs in +load — immediately after Firebase dylibs load, before Swift @main.
@interface LookAfterFirebaseAppBootstrap : NSObject
@end

@implementation LookAfterFirebaseAppBootstrap

+ (void)load {
    if ([FIRApp defaultApp] != nil) {
        return;
    }

    FIROptions *options = nil;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
    if (plistPath.length > 0) {
        options = [[FIROptions alloc] initWithContentsOfFile:plistPath];
    }

    if (options == nil) {
        options = [[FIROptions alloc] initWithGoogleAppID:@"1:1234567890:ios:1234567890abcdef"
                                              GCMSenderID:@"1234567890"];
        options.APIKey = @"AIzaSy000000000000000000000000000000000";
        options.projectID = @"lifeos-dummy";
        options.storageBucket = @"lifeos-dummy.appspot.com";
    }

    [FIRApp configureWithOptions:options];
}

@end
