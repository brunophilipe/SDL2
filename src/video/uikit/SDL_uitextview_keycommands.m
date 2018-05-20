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
#include "keyinfotable.h"

#import "SDL_uitextview_keycommands.h"

NSString * const UIKeyInputBackspace = @"\x08";
NSString * const UIKeyInputReturn = @"\x0D";
NSString * const UIKeyInputTab = @"\x09";
NSString * const UIKeyInputDelete = @"\x7F";

@implementation SDL_uitextview_keycommands
{
    NSArray<UIKeyCommand *> *_allKeyCommands;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        /* set UITextInputTrait properties, mostly to defaults */
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.enablesReturnKeyAutomatically = NO;
        self.keyboardAppearance = UIKeyboardAppearanceDefault;
        self.keyboardType = UIKeyboardTypeDefault;
        self.returnKeyType = UIReturnKeyDefault;
        self.secureTextEntry = NO;

        UIBarButtonItem *escapeButton = [[UIBarButtonItem alloc] initWithTitle:@"esc"
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(sendFakeEscapeKey)];

        UIBarButtonItemGroup *escapeGroup = [[UIBarButtonItemGroup alloc] initWithBarButtonItems:@[escapeButton]
                                                                              representativeItem:nil];

        NSMutableArray *items = [self.inputAssistantItem.leadingBarButtonGroups mutableCopy];
        [items insertObject:escapeGroup atIndex:0];

        self.inputAssistantItem.leadingBarButtonGroups = items;

        [self generateModifierKeyCommands];
    }
    return self;
}

- (void)generateModifierKeyCommands
{
    NSMutableArray<UIKeyCommand *> *keyCommands = [[NSMutableArray alloc] initWithCapacity:2 * 26];

    [keyCommands addObjectsFromArray:@[
        [UIKeyCommand keyCommandWithInput:@"`" modifierFlags:UIKeyModifierControl action:@selector(sendFakeEscapeKey)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputReturn modifierFlags:0 action:@selector(sendFakeReturnKey)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow modifierFlags:0 action:@selector(sendFakeUpArrowKey)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow modifierFlags:0 action:@selector(sendFakeDownArrowKey)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:0 action:@selector(sendFakeLeftArrowKey)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:0 action:@selector(sendFakeRightArrowKey)]
    ]];

    for (char i=0; i<('z' - 'a'); i++)
    {
        [keyCommands addObject:[UIKeyCommand keyCommandWithInput:[NSString stringWithFormat:@"%c", 'a' + i]
                                                   modifierFlags:UIKeyModifierControl
                                                          action:@selector(sendFakeKeyWithControlModifier:)]];
        [keyCommands addObject:[UIKeyCommand keyCommandWithInput:[NSString stringWithFormat:@"%c", 'a' + i]
                                                   modifierFlags:UIKeyModifierAlternate
                                                          action:@selector(sendFakeKeyWithAltModifier:)]];
    }

    _allKeyCommands = keyCommands;
}

- (void)deleteBackward
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_BACKSPACE);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_BACKSPACE);
}

- (void)insertText:(NSString *)text
{
    NSUInteger len = text.length;

    /* go through all the characters in the string we've been sent and
     * convert them to key presses */
    int i;
    for (i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        Uint16 mod = 0;
        SDL_Scancode code;

        if (c < 127) {
            /* figure out the SDL_Scancode and SDL_keymod for this unichar */
            code = unicharToUIKeyInfoTable[c].code;
            mod  = unicharToUIKeyInfoTable[c].mod;
        } else {
            /* we only deal with ASCII right now */
            code = SDL_SCANCODE_UNKNOWN;
            mod = 0;
        }

        if (mod & KMOD_SHIFT) {
            /* If character uses shift, press shift down */
            SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LSHIFT);
        }

        /* send a keydown and keyup even for the character */
        SDL_SendKeyboardKey(SDL_PRESSED, code);
        SDL_SendKeyboardKey(SDL_RELEASED, code);

        if (mod & KMOD_SHIFT) {
            /* If character uses shift, press shift back up */
            SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LSHIFT);
        }
    }

    SDL_SendKeyboardText([text UTF8String]);
}

- (void)sendFakeKeyWithControlModifier:(UIKeyCommand *)keyCommand
{
    unichar c = [keyCommand.input characterAtIndex:0];
    SDL_Scancode code = unicharToUIKeyInfoTable[c].code;

    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LCTRL);
    SDL_SendKeyboardKey(SDL_PRESSED, code);
    SDL_SendKeyboardKey(SDL_RELEASED, code);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LCTRL);
}

- (void)sendFakeKeyWithAltModifier:(UIKeyCommand *)keyCommand
{
    unichar c = [keyCommand.input characterAtIndex:0];
    SDL_Scancode code = unicharToUIKeyInfoTable[c].code;

    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LALT);
    SDL_SendKeyboardKey(SDL_PRESSED, code);
    SDL_SendKeyboardKey(SDL_RELEASED, code);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LALT);
}

/* Key commands provide support for some control keys */
- (NSArray<UIKeyCommand *> *)keyCommands
{
    return _allKeyCommands;
}

- (void)sendFakeEscapeKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_ESCAPE);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_ESCAPE);
}

- (void)sendFakeReturnKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RETURN);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RETURN);
}

- (void)sendFakeUpArrowKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_UP);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_UP);
}

- (void)sendFakeDownArrowKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_DOWN);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_DOWN);
}

- (void)sendFakeLeftArrowKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LEFT);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LEFT);
}

- (void)sendFakeRightArrowKey
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RIGHT);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RIGHT);
}

@end

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
