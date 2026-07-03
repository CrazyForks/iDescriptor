#include "macos.h"
#import <AppKit/AppKit.h>

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
    [window setMovableByWindowBackground:YES];
    set_traffic_light_inset(window, NSMakePoint(20.0, 20.0));
    [window center];
}
