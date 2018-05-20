/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2017 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "../../SDL_internal.h"

#if SDL_VIDEO_DRIVER_UIKIT

#include "SDL_video.h"
#include "SDL_assert.h"
#include "SDL_hints.h"
#include "../SDL_sysvideo.h"
#include "../../events/SDL_events_c.h"

#import "SDL_uikitviewcontroller.h"
#import "SDL_uikitmessagebox.h"
#include "SDL_uikitvideo.h"
#include "SDL_uikitmodes.h"
#include "SDL_uikitwindow.h"
#include "SDL_uikitopengles.h"

#if SDL_IPHONE_KEYBOARD
#import "SDL_uitextview_keycommands.h"
#endif

#if TARGET_OS_TV
static void SDLCALL
SDL_AppleTVControllerUIHintChanged(void *userdata, const char *name, const char *oldValue, const char *hint)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *viewcontroller = (__bridge SDL_uikitviewcontroller *) userdata;
        viewcontroller.controllerUserInteractionEnabled = hint && (*hint != '0');
    }
}
#endif

@implementation SDL_uikitviewcontroller {
    CADisplayLink *displayLink;
    int animationInterval;
    void (*animationCallback)(void*);
    void *animationCallbackParam;

#if SDL_IPHONE_KEYBOARD
    UITextView *textView;
    BOOL rotatingOrientation;
#endif
}

@synthesize window;

- (instancetype)initWithSDLWindow:(SDL_Window *)_window
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.window = _window;

#if SDL_IPHONE_KEYBOARD
        [self initKeyboard];
        rotatingOrientation = FALSE;
#endif

#if TARGET_OS_TV
        SDL_AddHintCallback(SDL_HINT_APPLE_TV_CONTROLLER_UI_EVENTS,
                            SDL_AppleTVControllerUIHintChanged,
                            (__bridge void *) self);
#endif
    }
    return self;
}

- (void)dealloc
{
#if SDL_IPHONE_KEYBOARD
    [self deinitKeyboard];
#endif

#if TARGET_OS_TV
    SDL_DelHintCallback(SDL_HINT_APPLE_TV_CONTROLLER_UI_EVENTS,
                        SDL_AppleTVControllerUIHintChanged,
                        (__bridge void *) self);
#endif
}

- (void)setAnimationCallback:(int)interval
                    callback:(void (*)(void*))callback
               callbackParam:(void*)callbackParam
{
    [self stopAnimation];

    animationInterval = interval;
    animationCallback = callback;
    animationCallbackParam = callbackParam;

    if (animationCallback) {
        [self startAnimation];
    }
}

- (void)startAnimation
{
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(doLoop:)];

#ifdef __IPHONE_10_3
    SDL_WindowData *data = (__bridge SDL_WindowData *) window->driverdata;

    if ([displayLink respondsToSelector:@selector(preferredFramesPerSecond)]
        && data != nil && data.uiwindow != nil
        && [data.uiwindow.screen respondsToSelector:@selector(maximumFramesPerSecond)]) {
        displayLink.preferredFramesPerSecond = data.uiwindow.screen.maximumFramesPerSecond / animationInterval;
    } else
#endif
    {
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 100300
        [displayLink setFrameInterval:animationInterval];
#endif
    }

    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopAnimation
{
    [displayLink invalidate];
    displayLink = nil;
}

- (void)doLoop:(CADisplayLink*)sender
{
    /* Don't run the game loop while a messagebox is up */
    if (!UIKit_ShowingMessageBox()) {
        /* See the comment in the function definition. */
        UIKit_GL_RestoreCurrentContext();

        animationCallback(animationCallbackParam);
    }
}

- (void)loadView
{
    /* Do nothing. */
}

- (void)viewDidLayoutSubviews
{
    const CGSize size = self.view.bounds.size;
    int w = (int) size.width;
    int h = (int) size.height;

    SDL_SendWindowEvent(window, SDL_WINDOWEVENT_RESIZED, w, h);
}

#if !TARGET_OS_TV
- (NSUInteger)supportedInterfaceOrientations
{
    return UIKit_GetSupportedOrientations(window);
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orient
{
    return ([self supportedInterfaceOrientations] & (1 << orient)) != 0;
}
#endif

- (BOOL)prefersStatusBarHidden
{
    return (window->flags & (SDL_WINDOW_FULLSCREEN|SDL_WINDOW_BORDERLESS)) != 0;
}
#endif

/*
 ---- Keyboard related functionality below this line ----
 */
#if SDL_IPHONE_KEYBOARD

@synthesize textInputRect;
@synthesize keyboardHeight;
@synthesize keyboardVisible;

/* Set ourselves up as a UITextFieldDelegate */
- (void)initKeyboard
{
    textView = [[SDL_uitextview_keycommands alloc] initWithFrame:CGRectZero];

    textView.hidden = YES;
    keyboardVisible = NO;

#if !TARGET_OS_TV
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
#endif
}

- (void)setView:(UIView *)view
{
    [super setView:view];

    [view addSubview:textView];

    if (keyboardVisible) {
        [self showKeyboard];
    }
}

/* willRotateToInterfaceOrientation and didRotateFromInterfaceOrientation are deprecated in iOS 8+ in favor of viewWillTransitionToSize */
#if TARGET_OS_TV || __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    rotatingOrientation = TRUE;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {}
                                 completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                                     rotatingOrientation = FALSE;
                                 }];
}
#else
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    rotatingOrientation = TRUE;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    rotatingOrientation = FALSE;
}
#endif /* TARGET_OS_TV || __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000 */

- (void)deinitKeyboard
{
#if !TARGET_OS_TV
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [center removeObserver:self name:UIKeyboardWillHideNotification object:nil];
#endif
}

/* reveal onscreen virtual keyboard */
- (void)showKeyboard
{
    keyboardVisible = YES;
    if (textView.window) {
        [textView becomeFirstResponder];
    }
}

/* hide onscreen virtual keyboard */
- (void)hideKeyboard
{
    keyboardVisible = NO;
    [textView resignFirstResponder];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
#if !TARGET_OS_TV
    CGRect kbrect = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue];

    /* The keyboard rect is in the coordinate space of the screen/window, but we
     * want its height in the coordinate space of the view. */
    kbrect = [self.view convertRect:kbrect fromView:nil];

    [self setKeyboardHeight:(int)kbrect.size.height];
#endif
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    if (!rotatingOrientation) {
        SDL_StopTextInput();
    }
    [self setKeyboardHeight:0];
}

- (void)updateKeyboard
{
    CGAffineTransform t = self.view.transform;
    CGPoint offset = CGPointMake(0.0, 0.0);
    CGRect frame = UIKit_ComputeViewFrame(window, self.view.window.screen);

    if (self.keyboardHeight) {
        int rectbottom = self.textInputRect.y + self.textInputRect.h;
        int keybottom = self.view.bounds.size.height - self.keyboardHeight;
        if (keybottom < rectbottom) {
            offset.y = keybottom - rectbottom;
        }
    }

    /* Apply this view's transform (except any translation) to the offset, in
     * order to orient it correctly relative to the frame's coordinate space. */
    t.tx = 0.0;
    t.ty = 0.0;
    offset = CGPointApplyAffineTransform(offset, t);

    /* Apply the updated offset to the view's frame. */
    frame.origin.x += offset.x;
    frame.origin.y += offset.y;

    self.view.frame = frame;
}

- (void)setKeyboardHeight:(int)height
{
    keyboardVisible = height > 0;
    keyboardHeight = height;
    [self updateKeyboard];
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    return @[[UIKeyCommand keyCommandWithInput:@"`" modifierFlags:UIKeyModifierControl action:@selector(sendFakeEscapeKey)]];
}

- (void)sendFakeEscapeKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_ESCAPE);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_ESCAPE);
}

#endif

@end

/* iPhone keyboard addition functions */
#if SDL_IPHONE_KEYBOARD

static SDL_uikitviewcontroller *
GetWindowViewController(SDL_Window * window)
{
    if (!window || !window->driverdata) {
        SDL_SetError("Invalid window");
        return nil;
    }

    SDL_WindowData *data = (__bridge SDL_WindowData *)window->driverdata;

    return data.viewcontroller;
}

SDL_bool
UIKit_HasScreenKeyboardSupport(_THIS)
{
    return SDL_TRUE;
}

void
UIKit_ShowScreenKeyboard(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        [vc showKeyboard];
    }
}

void
UIKit_HideScreenKeyboard(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        [vc hideKeyboard];
    }
}

SDL_bool
UIKit_IsScreenKeyboardShown(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        if (vc != nil) {
            return vc.isKeyboardVisible;
        }
        return SDL_FALSE;
    }
}

void
UIKit_SetTextInputRect(_THIS, SDL_Rect *rect)
{
    if (!rect) {
        SDL_InvalidParamError("rect");
        return;
    }

    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(SDL_GetFocusWindow());
        if (vc != nil) {
            vc.textInputRect = *rect;

            if (vc.keyboardVisible) {
                [vc updateKeyboard];
            }
        }
    }
}


#endif /* SDL_IPHONE_KEYBOARD */

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
