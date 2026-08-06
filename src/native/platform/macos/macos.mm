#include "macos.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static NSWindow *window_from_view_ptr(void *view_ptr)
{
    if (!view_ptr)
    {
        NSLog(@"native view pointer is null");
        return nil;
    }

    NSView *nativeView = reinterpret_cast<NSView *>(view_ptr);
    if (!nativeView)
    {
        NSLog(@"native view is null");
        return nil;
    }

    NSWindow *window = [nativeView window];
    if (!window)
    {
        NSLog(@"native window is null");
        return nil;
    }

    return window;
}

static void set_traffic_light_inset(NSWindow *window, NSPoint position)
{
    if (!window)
        return;

    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    NSButton *miniaturizeButton =
        [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];

    if (!closeButton || !miniaturizeButton || !zoomButton)
        return;

    NSView *titleBarContainer = closeButton.superview.superview;
    if (!titleBarContainer)
        return;

    NSRect closeRect = closeButton.frame;
    CGFloat titleBarFrameHeight = closeRect.size.height + position.y;
    NSRect titleBarRect = titleBarContainer.frame;
    titleBarRect.size.height = titleBarFrameHeight;
    titleBarRect.origin.y = window.frame.size.height - titleBarFrameHeight;
    [titleBarContainer setFrame:titleBarRect];

    CGFloat spaceBetween = NSMinX(miniaturizeButton.frame) - NSMinX(closeRect);
    NSArray<NSButton *> *buttons =
        @[ closeButton, miniaturizeButton, zoomButton ];

    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *button = buttons[i];
        NSRect rect = button.frame;
        rect.origin.x = position.x + (i * spaceBetween);
        [button setFrameOrigin:rect.origin];
    }
}

// AppKit lays out the private titlebar view hierarchy again while resizing.
// Tao handles that by storing the inset in its view state and applying it from
// drawRect:. Qt owns the content view here, so observe the equivalent window
// lifecycle event and restore the inset after each AppKit resize layout.
@interface TrafficLightInsetObserver : NSObject
{
    NSWindow *_window;
    NSPoint _position;
}

- (instancetype)initWithWindow:(NSWindow *)window position:(NSPoint)position;
- (void)setPosition:(NSPoint)position;
- (void)windowDidResize:(NSNotification *)notification;

@end

@implementation TrafficLightInsetObserver

- (instancetype)initWithWindow:(NSWindow *)window position:(NSPoint)position
{
    self = [super init];
    if (self)
    {
        _window = window;
        _position = position;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(windowDidResize:)
                   name:NSWindowDidResizeNotification
                 object:window];
    }
    return self;
}

- (void)setPosition:(NSPoint)position
{
    _position = position;
    set_traffic_light_inset(_window, _position);
}

- (void)windowDidResize:(NSNotification *)notification
{
    set_traffic_light_inset(_window, _position);
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

@end

static void keep_traffic_light_inset(NSWindow *window, NSPoint position)
{
    static char observerAssociationKey;
    TrafficLightInsetObserver *observer = objc_getAssociatedObject(
        window, &observerAssociationKey);

    if (observer)
    {
        [observer setPosition:position];
        return;
    }

    observer = [[TrafficLightInsetObserver alloc]
        initWithWindow:window
              position:position];
    objc_setAssociatedObject(window, &observerAssociationKey, observer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [observer release];

    set_traffic_light_inset(window, position);
}

@interface SidebarVisualEffectView : NSVisualEffectView
@end

@implementation SidebarVisualEffectView

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

static void install_sidebar_material(NSWindow *window, NSView *nativeView)
{
    static char visualEffectAssociationKey;
    if (objc_getAssociatedObject(window, &visualEffectAssociationKey))
        return;

    NSView *containerView = [nativeView superview];
    if (!containerView)
    {
        NSLog(@"failed to install sidebar material: native view has no superview");
        return;
    }

    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];

    SidebarVisualEffectView *effectView =
        [[SidebarVisualEffectView alloc] initWithFrame:nativeView.frame];
    [effectView setMaterial:NSVisualEffectMaterialSidebar];
    [effectView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [effectView setState:NSVisualEffectStateFollowsWindowActiveState];
    [effectView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Keep Qt's native view exactly where Qt installed it. Reparenting this
    // view disrupts Qt's native responder and pointer-tracking setup.
    [containerView addSubview:effectView
                  positioned:NSWindowBelow
                  relativeTo:nativeView];

    objc_setAssociatedObject(window, &visualEffectAssociationKey, effectView,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [effectView release];
}

extern "C" void setup_tool_frame(void *view_ptr)
{
    NSWindow *window = window_from_view_ptr(view_ptr);
    if (!window) {
        NSLog(@"failed in setup_tool_frame");
        return;
    }

    // TODO: remove the fullscreen button. Changing the style mask here
    // currently breaks other window styling behavior.

    NSToolbar *toolbar =
        [[NSToolbar alloc] initWithIdentifier:@"HiddenInsetToolbar"];
    toolbar.showsBaselineSeparator = NO;
    [window setToolbar:toolbar];

    // TODO: theming
    NSColor *backgroundColor = [NSColor colorWithWhite:0.95 alpha:1.0];
    [window setBackgroundColor:backgroundColor];

    [toolbar release];
}

extern "C" void setup_macos_main_window(void *view_ptr)
{
    NSView *nativeView = reinterpret_cast<NSView *>(view_ptr);
    NSWindow *window = window_from_view_ptr(view_ptr);
    if (!window)
    {
        NSLog(@"failed in setup_macos_main_window");
        return;
    }

    [window setStyleMask:[window styleMask] |
                         NSWindowStyleMaskFullSizeContentView |
                         NSWindowTitleHidden];
    [window setTitleVisibility:NSWindowTitleHidden];
    [window setTitlebarAppearsTransparent:YES];
    [window setMovableByWindowBackground:NO];
    install_sidebar_material(window, nativeView);
    keep_traffic_light_inset(window, NSMakePoint(20.0, 20.0));
    [window center];
}
