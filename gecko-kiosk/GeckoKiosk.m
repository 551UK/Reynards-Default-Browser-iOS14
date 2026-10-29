#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *kHome = @"GeckoKiosk.homepage", *kReset = @"GeckoKiosk.resetNextLaunch", *kStarted = @"GeckoKiosk.didBootstrap";
static NSURL *pendingURL;
static BOOL configured = NO, attached = NO, firstAppearance = NO;
static UIView *webContent = nil;
static UIView *chromeView = nil, *tabOverview = nil;
static IMP originalLoad = NULL, originalLayout = NULL, originalAppear = NULL;
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
static void chooseIcon(UIViewController *c) {
    UIApplication *app=UIApplication.sharedApplication;
    if (!app.supportsAlternateIcons) {alert(c,@"Icons unavailable",@"This installation does not support alternate icons.");return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Home Screen Icon" message:@"Choose a bundled icon. For your own image, replace the icon files when cloning this IPA." preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary<NSString *, NSString *> *icons=@{@"Ocean (Blue)":@"GeckoOcean",@"Forest (Green)":@"GeckoForest",@"Sunset (Orange)":@"GeckoSunset",@"Midnight (Dark)":@"GeckoMidnight"};
    for (NSString *label in @[@"Ocean (Blue)",@"Forest (Green)",@"Sunset (Orange)",@"Midnight (Dark)"]) {
        NSString *name=icons[label];
        [a addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[app setAlternateIconName:name completionHandler:nil];}]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Original" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[app setAlternateIconName:nil completionHandler:nil];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=c.view;
    [c presentViewController:a animated:YES completion:nil];
}
static void showMenu(UIViewController *c) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Gecko App" message:@"Hidden settings · three-finger press and hold" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Change Website URL" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){promptURL(c);}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Open Homepage" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){navigate(c,homepage());}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Start New Session" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Start New Session?" message:@"This will clear saved tabs on next launch, but keep website cookies. Force-close the app from the switcher and reopen it." preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Start Fresh Next Launch" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *y){
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReset];
            alert(c,@"New Session Set",@"Force-close the app and reopen it to start fresh.");
        }]];
        [c presentViewController:confirm animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restore Last Session" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
        [d setBool:NO forKey:kReset];[d setObject:@"lastTab" forKey:@"default.HomepageSettings.openingScreen"];
        alert(c,@"Session Restore Enabled",@"Saved tabs will be restored when you reopen the app.");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Change App Icon" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){chooseIcon(c);}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=c.view;
    [c presentViewController:a animated:YES completion:nil];
}
static void gesture(id self,SEL sel,UILongPressGestureRecognizer *g) {
    if (g.state==UIGestureRecognizerStateBegan && ![(UIViewController *)self presentedViewController]) showMenu((UIViewController *)self);
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
    UILongPressGestureRecognizer *g=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(geckoKioskGesture:)];
    g.numberOfTouchesRequired=3;g.minimumPressDuration=0.7;g.cancelsTouchesInView=NO;
    [[self view] addGestureRecognizer:g];
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
        if ([d boolForKey:kReset]) {
            [d setBool:NO forKey:kReset];[d setBool:NO forKey:kStarted];
            NSURL *support=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
            NSURL *tabs=[[support URLByAppendingPathComponent:@"AppData"] URLByAppendingPathComponent:@"TabManagement"];
            [NSFileManager.defaultManager removeItemAtURL:tabs error:nil];
        }
        [d setObject:@"lastTab" forKey:@"default.HomepageSettings.openingScreen"];
        Class cls=NSClassFromString(@"Reynard.BrowserViewController");
        if (!cls) {
            unsigned int count=0;Class *classes=objc_copyClassList(&count);
            for (unsigned int i=0;i<count;i++) if ([NSStringFromClass(classes[i]) containsString:@"Reynard.BrowserViewController"]) {cls=classes[i];break;}
            free(classes);
        }
        if (!cls)return;
        class_addMethod(cls,@selector(geckoKioskGesture:),(IMP)gesture,"v@:@");
        replace(cls,@selector(viewDidLoad),(IMP)didLoad,&originalLoad);
        replace(cls,@selector(viewDidLayoutSubviews),(IMP)didLayout,&originalLayout);
        replace(cls,@selector(viewDidAppear:),(IMP)didAppear,&originalAppear);
        class_replaceMethod(cls,@selector(prefersStatusBarHidden),(IMP)statusHidden,"c@:");
        class_replaceMethod(cls,@selector(childForStatusBarHidden),(IMP)noChild,"@@:");
    }
}
