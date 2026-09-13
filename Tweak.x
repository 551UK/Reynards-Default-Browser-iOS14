// Based on guacforlife/ReynardDefault (GPL-3.0).
// Independent iOS 14 routing through FBSOpenApplicationOptions.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Common/Common.h"

@interface FBSOpenApplicationOptions : NSObject <NSCopying>
@property (nonatomic, copy) NSDictionary *dictionary;
@property (nonatomic, readonly) NSURL *url;
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSystemServiceOpenApplicationRequest : NSObject
@property (nonatomic, copy) FBSOpenApplicationOptions *options;
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

// iOS 14 stores the URL in options, not on the request itself.
static FBSOpenApplicationOptions *redirectedOptions(FBSOpenApplicationOptions *options) {
    if (![options respondsToSelector:@selector(url)] ||
        ![options respondsToSelector:@selector(dictionary)]) return nil;
    NSURL *wrapped = wrappedURL(options.url);
    if (!wrapped) return nil;
    NSDictionary *original = options.dictionary;
    if (![original isKindOfClass:[NSDictionary class]]) return nil;
    NSString * __unsafe_unretained *symbol = (NSString * __unsafe_unretained *)dlsym(
        RTLD_DEFAULT, "FBSOpenApplicationOptionKeyPayloadURL");
    NSString *key = symbol ? *symbol : @"__PayloadURL";
    if (!key || !original[key]) return nil;
    NSMutableDictionary *payload = [original mutableCopy];
    payload[key] = wrapped;
    Class optionsClass = [options class];
    if (![optionsClass respondsToSelector:@selector(optionsWithDictionary:)]) return nil;
    FBSOpenApplicationOptions *replacement = [optionsClass optionsWithDictionary:payload];
    // Do not change the destination unless the replacement actually retained the URL.
    return [replacement.url isEqual:wrapped] ? replacement : nil;
}

%hook FBSystemServiceOpenApplicationRequest

- (void)setBundleIdentifier:(NSString *)bundleIdentifier {
    %orig;
    if (isBrowser(bundleIdentifier) &&
        [self respondsToSelector:@selector(options)] &&
        [self respondsToSelector:@selector(setOptions:)] && self.options) {
        [self setOptions:self.options];
    }
}

- (void)setOptions:(FBSOpenApplicationOptions *)options {
    if ([self respondsToSelector:@selector(bundleIdentifier)] &&
        isBrowser(self.bundleIdentifier) && redirectEnabled()) {
        FBSOpenApplicationOptions *replacement = redirectedOptions(options);
        if (replacement && reynardInstalled()) {
            %orig(replacement);
            [self setBundleIdentifier:kReynardBundleID];
            return;
        }
    }
    %orig;
}

%end
