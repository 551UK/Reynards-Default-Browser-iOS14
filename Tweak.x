// Based on guacforlife/ReynardDefault (GPL-3.0).
// Rootful iOS 14 port: preserve complete URLs and handle either setter order.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "Common/Common.h"

@interface FBSystemServiceOpenApplicationRequest : NSObject
@property (nonatomic, copy) NSURL *URL;
@property (nonatomic, copy) NSString *bundleIdentifier;
@end

static NSString *const kReynardBundleID = @"com.minh-ton.Reynard";

static BOOL isBrowser(NSString *bundleID) {
    return [bundleID isEqualToString:@"com.apple.mobilesafari"] ||
           [bundleID isEqualToString:@"org.mozilla.ios.Firefox"] ||
           [bundleID isEqualToString:@"com.google.chrome.ios"] ||
           [bundleID isEqualToString:@"com.brave.ios.browser"];
}

static BOOL redirectEnabled(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    [prefs synchronize];
    return [prefs objectForKey:kEnabledKey] ? [prefs boolForKey:kEnabledKey] : YES;
}

static BOOL reynardInstalled(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL installedSelector = NSSelectorFromString(@"applicationIsInstalled:");
    if (![workspaceClass respondsToSelector:defaultSelector]) return NO;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSelector);
    if (![workspace respondsToSelector:installedSelector]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, installedSelector, kReynardBundleID);
}

static NSURL *wrappedURL(NSURL *original) {
    NSString *scheme = original.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;
    // Only unreserved characters may remain in this nested query value.
    // This protects &, +, #, %, = and an existing URL's percent escapes.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [original.absoluteString stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    if (!encoded.length) return nil;
    return [NSURL URLWithString:[@"reynard://open?url=" stringByAppendingString:encoded]];
}

%hook FBSystemServiceOpenApplicationRequest

- (void)setBundleIdentifier:(NSString *)bundleIdentifier {
    %orig;
    // Some iOS versions populate URL before bundleIdentifier, others after it.
    if (isBrowser(bundleIdentifier) &&
        [self respondsToSelector:@selector(URL)] &&
        [self respondsToSelector:@selector(setURL:)] && self.URL) {
        [self setURL:self.URL];
    }
}

- (void)setURL:(NSURL *)url {
    if ([self respondsToSelector:@selector(bundleIdentifier)] &&
        isBrowser(self.bundleIdentifier) && redirectEnabled()) {
        NSURL *wrapped = wrappedURL(url);
        if (wrapped && reynardInstalled()) {
            %orig(wrapped);
            [self setBundleIdentifier:kReynardBundleID];
            return;
        }
    }
    %orig;
}

%end
