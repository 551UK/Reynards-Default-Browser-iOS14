#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *kHome = @"GeckoKiosk.homepage", *kStarted = @"GeckoKiosk.didBootstrap";
static NSURL *pendingURL;
static BOOL configured = NO, attached = NO, firstAppearance = NO;
static UIView *webContent = nil;
static UIView *chromeView = nil, *tabOverview = nil;
static IMP originalLoad = NULL, originalLayout = NULL, originalAppear = NULL, originalConnect = NULL, originalShortcut = NULL;
static NSString *defaultHomepage = @"https://google.com";

@interface GeckoURLContext : UIOpenURLContext @end
@implementation GeckoURLContext
- (NSURL *)URL { return pendingURL; }
@end

static NSString *homepage(void) { return [[NSUserDefaults standardUserDefaults] stringForKey:kHome] ?: defaultHomepage; }
static void alert(UIViewController *c, NSString *title, NSString *detail) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [c presentViewController:a animated:YES completion:nil];
}
static void navigate(UIViewController *c, NSString *string) {
    NSURL *url=[NSURL URLWithString:string];
    if (!url.host || !([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"])) {
        alert(c, @"Invalid URL", @"Enter a valid web address."); return;
    }
    UIWindowScene *scene=c.view.window.windowScene;
    id delegate=scene.delegate;
    if (!scene || ![delegate respondsToSelector:@selector(scene:openURLContexts:)]) {
        alert(c,@"Navigation unavailable",@"Please close and reopen this app.");return;
    }
    pendingURL=url;
    GeckoURLContext *ctx=[GeckoURLContext new];
    [delegate scene:scene openURLContexts:[NSSet setWithObject:ctx]];
}
static void promptURL(UIViewController *c) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Website URL" message:@"Change this Gecko app's homepage." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=homepage();f.keyboardType=UIKeyboardTypeURL;f.placeholder=@"https://example.com";}];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save & Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *url=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) url=[@"https://" stringByAppendingString:url];
        NSURL *parsed=[NSURL URLWithString:url];
        if (parsed.host.length==0) { alert(c,@"Invalid URL",@"Please enter a valid website address.");return; }
        [[NSUserDefaults standardUserDefaults] setObject:url forKey:kHome];
        navigate(c,url);
    }]];
    [c presentViewController:a animated:YES completion:nil];
}
// Exactly two Home Screen Quick Actions. Launching or resuming via a quick action is the
// ONLY path to the settings; there is no gesture or persistent UI in the app.
static void performShortcut(id sceneDelegate, UIApplicationShortcutItem *item) {
    if (!item) return;
    UIWindow *window = nil;
    if ([sceneDelegate respondsToSelector:@selector(window)])
        window = ((UIWindow *(*)(id,SEL))objc_msgSend)(sceneDelegate,@selector(window));
    UIViewController *controller = window.rootViewController;
    if (!controller) return;
    NSString *type = item.type;
    if ([type isEqualToString:@"com.551uk.gecko.website"]) {
        promptURL(controller);
    } else if ([type isEqualToString:@"com.551uk.gecko.fresh"]) {
        // A fresh start is immediate: navigate to the configured homepage.
        // Normal launches still use Reynard's saved last-tab state.
        // Cookies and logins remain intact.
        navigate(controller, homepage());
    }
}

// When launched from the Home Screen quick-action menu while terminated,
// iOS supplies the item inside UIScene.ConnectionOptions rather than invoking
// performActionForShortcutItem on an already-running scene.
static void sceneConnect(id self, SEL cmd, UIScene *scene,
                         UISceneSession *session, UISceneConnectionOptions *options) {
    ((void (*)(id,SEL,UIScene *,UISceneSession *,UISceneConnectionOptions *))originalConnect)
        (self,cmd,scene,session,options);
    UIApplicationShortcutItem *item = options.shortcutItem;
    if (item) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.65*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ performShortcut(self,item); });
    }
}
static void sceneShortcut(id self, SEL cmd, UIWindowScene *scene,
                          UIApplicationShortcutItem *item,
                          void (^completionHandler)(BOOL)) {
    performShortcut(self,item);
    if (originalShortcut) {
        ((void (*)(id,SEL,UIWindowScene *,UIApplicationShortcutItem *,void (^)(BOOL)))originalShortcut)
            (self,cmd,scene,item,completionHandler);
    } else if (completionHandler) {
        completionHandler(YES);
    }
}
static void fill(UIViewController *c) {
    if (!configured) return;
    UIView *root=c.view;
    for (UIView *v in root.subviews) {
        NSString *name=NSStringFromClass(v.class);
        if ([name containsString:@"BrowserChrome"]) chromeView=v;
        else if ([name containsString:@"TabOverview"]) tabOverview=v;
        else if ([name hasSuffix:@"ContentView"]]) webContent=v;
    }
    chromeView.hidden=YES; tabOverview.hidden=YES;
    if (!webContent) return;
    // Drop the two original constraints reserving room for the address bar
    // and bottom toolbar; keep horizontal constraints.
    for (NSLayoutConstraint *cons in root.constraints) {
        if (!cons.isActive) continue;
        if (cons.firstItem!=webContent && cons.secondItem!=webContent) continue;
        BOOL vertical=cons.firstAttribute==NSLayoutAttributeTop || cons.firstAttribute==NSLayoutAttributeBottom ||
                      cons.secondAttribute==NSLayoutAttributeTop || cons.secondAttribute==NSLayoutAttributeBottom;
        if (!vertical) continue;
        BOOL rootPair=(cons.firstItem==root && cons.secondItem==webContent) || (cons.firstItem==webContent && cons.secondItem==root);
        if (!rootPair) cons.active=NO;
    }
    if (!attached) {
        [NSLayoutConstraint activateConstraints:@[
           [webContent.topAnchor constraintEqualToAnchor:root.topAnchor],
           [webContent.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
        ]];
        attached=YES;
    }
}
static void didLoad(id self,SEL _cmd) {
    ((void(*)(id,SEL))originalLoad)(self,_cmd);
    fill(self);
    [self setNeedsStatusBarAppearanceUpdate];
}
static void didLayout(id self,SEL _cmd){((void(*)(id,SEL))originalLayout)(self,_cmd);fill(self);}
static void didAppear(id self,SEL _cmd,BOOL anim) {
    ((void(*)(id,SEL,BOOL))originalAppear)(self,_cmd,anim);fill(self);[self setNeedsStatusBarAppearanceUpdate];
    if (!firstAppearance) {
        firstAppearance=YES;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kStarted]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kStarted];
            navigate(self,homepage());
        }
    }
}
static BOOL statusHidden(id self,SEL s){return YES;}
static id noChild(id self,SEL s){return nil;}
static void replace(Class klass,SEL sel,IMP newer,IMP *saved) {
    Method m=class_getInstanceMethod(klass,sel);if (!m)return;
    if (saved)*saved=method_getImplementation(m);
    class_replaceMethod(klass,sel,newer,method_getTypeEncoding(m));
}
__attribute__((constructor)) static void startKiosk(void){
    @autoreleasepool {
        NSString *config=[NSBundle.mainBundle pathForResource:@"GeckoSite" ofType:@"json"];
        if (!config) return;
        NSData *data=[NSData dataWithContentsOfFile:config];if(!data)return;
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSDictionary.class] || ![json[@"websiteApp"] boolValue]) return;
        defaultHomepage=json[@"homepage"] ?: defaultHomepage;configured=YES;
        NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
        [d setObject:@"lastTab" forKey:@"default.HomepageSettings.openingScreen"];
        Class cls=NSClassFromString(@"Reynard.BrowserViewController");
        if (!cls) {
            unsigned int count=0;Class *classes=objc_copyClassList(&count);
            for (unsigned int i=0;i<count;i++) if ([NSStringFromClass(classes[i]) containsString:@"Reynard.BrowserViewController"]) {cls=classes[i];break;}
            free(classes);
        }
        if (!cls)return;

        replace(cls,@selector(viewDidLoad),(IMP)didLoad,&originalLoad);
        replace(cls,@selector(viewDidLayoutSubviews),(IMP)didLayout,&originalLayout);
        replace(cls,@selector(viewDidAppear:),(IMP)didAppear,&originalAppear);
        class_replaceMethod(cls,@selector(prefersStatusBarHidden),(IMP)statusHidden,"c@:");
        class_replaceMethod(cls,@selector(childForStatusBarHidden),(IMP)noChild,"@@:");
        Class sceneClass = NSClassFromString(@"Reynard.SceneDelegate");
        if (sceneClass) {
            replace(sceneClass,@selector(scene:willConnectToSession:options:),(IMP)sceneConnect,&originalConnect);
            SEL shortcutSelector = @selector(windowScene:performActionForShortcutItem:completionHandler:);
            Method shortcutMethod = class_getInstanceMethod(sceneClass, shortcutSelector);
            if (shortcutMethod) {
                originalShortcut = method_getImplementation(shortcutMethod);
                class_replaceMethod(sceneClass, shortcutSelector, (IMP)sceneShortcut, method_getTypeEncoding(shortcutMethod));
            } else {
                class_addMethod(sceneClass, shortcutSelector, (IMP)sceneShortcut, "v@:@@@?");
            }
        }

    }
}
