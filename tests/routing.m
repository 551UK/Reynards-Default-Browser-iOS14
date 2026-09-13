// Exercises the actual routing helpers extracted from Tweak.x, with an
// options object matching the published iOS 14 interface. No phone simulation.
#import "TweakRouting.inc"

@implementation FBSOpenApplicationOptions
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary {
    FBSOpenApplicationOptions *options = [self new];
    options.dictionary = dictionary;
    return options;
}
- (NSURL *)url { return self.dictionary[@"__PayloadURL"]; }
- (id)copyWithZone:(NSZone *)zone {
    return [[self class] optionsWithDictionary:self.dictionary];
}
@end

int main(void) {
    @autoreleasepool {
        NSArray *links = @[
            @"https://example.com/",
            @"https://example.com/?a=1&b=two#section",
            @"https://example.com/?q=a+b&next=https%3A%2F%2Fexample.org%2Fa%3Fx%3D1",
            @"http://example.com/path%20with%20spaces?q=%26%23%25%2B"
        ];
        for (NSString *link in links) {
            NSURL *url = [NSURL URLWithString:link];
            NSDictionary *payload = @{@"__PayloadURL":url, @"PreserveThis":@42};
            FBSOpenApplicationOptions *original = [FBSOpenApplicationOptions optionsWithDictionary:payload];
            FBSOpenApplicationOptions *replacement = redirectedOptions(original);
            NSCAssert(replacement != nil, @"Missing replacement");
            NSURLComponents *parts = [NSURLComponents componentsWithURL:replacement.url resolvingAgainstBaseURL:NO];
            NSCAssert([parts.scheme isEqual:@"reynard"] && [parts.host isEqual:@"open"], @"Wrong destination");
            NSCAssert(parts.queryItems.count == 1, @"Query got split");
            NSCAssert([parts.queryItems.firstObject.value isEqual:link], @"URL changed during round trip");
            NSCAssert([replacement.dictionary[@"PreserveThis"] isEqual:@42], @"Options lost");
            NSCAssert([original.url isEqual:url], @"Original request mutated");
        }
        for (NSString *link in @[@"mailto:test@example.com", @"tel:123", @"reynard://open?url=x"]) {
            FBSOpenApplicationOptions *options = [FBSOpenApplicationOptions optionsWithDictionary:@{@"__PayloadURL":[NSURL URLWithString:link]}];
            NSCAssert(redirectedOptions(options) == nil, @"Non-web URL redirected");
        }
        NSCAssert(redirectedOptions(nil) == nil, @"Empty options redirected");
        NSCAssert(redirectedOptions([FBSOpenApplicationOptions optionsWithDictionary:@{}]) == nil, @"Icon launch redirected");
        NSLog(@"Routing checks passed: complete URLs, unchanged original/options, non-web and empty requests.");
    }
    return 0;
}
