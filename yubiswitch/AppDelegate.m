//  AppDelegate.m
//  yubiswitch

/*
 yubiswitch - enable/disable yubikey
 Copyright (C) 2013-2015  Angelo "pallotron" Failla <pallotron@freaknet.org>

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "AppDelegate.h"
#import "AboutWindowController.h"
#import <ShortcutRecorder/ShortcutRecorder.h>

// This is the main class, responsible for the status bar icon and general
// application behavior

@implementation AppDelegate
@synthesize window;
@synthesize controller;

- (id)init {
    self = [super init];
    if (self) {
        // Set default values for preferences, load it from
        // DefaultPreferences.plist file
        NSString *defaultPrefsFile =
        [[NSBundle mainBundle] pathForResource:@"DefaultPreferences"
                                        ofType:@"plist"];
        NSDictionary *defaultPrefs =
        [NSDictionary dictionaryWithContentsOfFile:defaultPrefsFile];

        [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];

        dispatch_async(dispatch_get_main_queue(), ^{
            m_timer =
            [NSTimer scheduledTimerWithTimeInterval:1
                                             target:self
                                           selector:@selector(updateMenuState:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
    return self;
}

- (void)updateMenuState:(NSTimer *)foo {
    if (yk != NULL) {
        if (isEnabled && [yk state]) { // inverted this means change
            NSLog(@"noticed change...");
            [statusItem setToolTip:(@"YubiKey disabled")];
            [statusItem setImage:[NSImage imageNamed:@"YubikeyDisabled"]];
            isEnabled = false;
            [[statusMenu itemAtIndex:0] setState:0];
            [self notify:@"YubiKey disabled"];
        }
    }
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    yk = [[YubiKey alloc] init];
    [yk disable];
    state_monitor = [[ComputerStateMonitor alloc] initWithYubiKey:yk];
    usernotification = [[NSUserNotification alloc] init];
    [self notify:@"YubiKey disabled"];
    aboutwc = [[AboutWindowController alloc]
               initWithWindowNibName:@"AboutWindowController"];
    prefwc = [[PreferencesController alloc]
              initWithWindowNibName:@"PreferencesController"];
}

- (void)awakeFromNib {

    statusItem = [[NSStatusBar systemStatusBar]
                  statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:YES];
    [statusItem.button setImage:[NSImage imageNamed:@"YubikeyDisabled"]];
    [statusItem.button setToolTip:@"YubiKey disabled"];

    isEnabled = false;

    // setup observer method, when the global hotkey is changed in the
    // preference controller this method gets notified.
    NSUserDefaultsController *defaults =
    [NSUserDefaultsController sharedUserDefaultsController];
    NSString *keyPath = @"values.hotkey";
    [defaults addObserver:self
               forKeyPath:keyPath
                  options:NSKeyValueObservingOptionInitial
                  context:NULL];

    SRShortcutAction *hotkeyAction =
    [SRShortcutAction shortcutActionWithKeyPath:keyPath
                                       ofObject:defaults
                                  actionHandler:^BOOL(SRShortcutAction *anAction) {
        [self toggle:nil];
        return YES;
    }];
    [[SRGlobalShortcutMonitor sharedMonitor] addAction:hotkeyAction forKeyEvent:SRKeyEventTypeDown];

    controller = [NSUserDefaultsController sharedUserDefaultsController];
    NSString *defaultPrefsFile =
    [[NSBundle mainBundle] pathForResource:@"DefaultPreferences"
                                    ofType:@"plist"];
    NSDictionary *defaultPrefs =
    [NSDictionary dictionaryWithContentsOfFile:defaultPrefsFile];
    [controller setInitialValues:defaultPrefs];
    [controller setAppliesImmediately:NO];
}

- (void)observeValueForKeyPath:(NSString *)aKeyPath
                      ofObject:(id)anObject
                        change:(NSDictionary *)aChange
                       context:(void *)aContext {
    if ([aKeyPath isEqualToString:@"values.hotkey"]) {
        NSDictionary *hotkey =
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"hotkey"];
        [[statusMenu itemAtIndex:0]
         setKeyEquivalent:[hotkey valueForKey:@"charactersIgnoringModifiers"]];
        [[statusMenu itemAtIndex:0]
         setKeyEquivalentModifierMask:
         [[hotkey valueForKey:@"modifierFlags"] unsignedIntValue]];
    } else
        [super observeValueForKeyPath:aKeyPath
                             ofObject:anObject
                               change:aChange
                              context:aContext];
}

- (void)notify:(NSString *)msg {
    BOOL displayNotifications = [[NSUserDefaults standardUserDefaults]
                                 boolForKey:@"displayNotifications"];
    if (!displayNotifications)
        return;
    usernotification.title = msg;
    [[NSUserNotificationCenter defaultUserNotificationCenter]
     deliverNotification:usernotification];
}

// TODO: create enable/disable methods and use them in toggle: and createTimer:
- (NSTimer *)createTimer:(NSInteger)interval {
    return [NSTimer scheduledTimerWithTimeInterval:interval
                                            target:self
                                          selector:@selector(reDisableYK)
                                          userInfo:nil
                                           repeats:NO];
}

- (void)reDisableYK {
    BOOL res;
    res = [yk disable];
    if (res == TRUE) {
        [statusItem setToolTip:(@"YubiKey disabled")];
        [statusItem setImage:[NSImage imageNamed:@"YubikeyDisabled"]];
        isEnabled = false;
        [[statusMenu itemAtIndex:0] setState:0];
        [self notify:@"YubiKey disabled"];
    }
}

- (void)enableYubiKey:(BOOL)enable {
    BOOL res;
    if (enable == TRUE) {
        res = [yk enable];
    } else {
        res = [yk disable];
    }
    if (res == TRUE) {
        [reDisableTimer invalidate];
        reDisableTimer = nil;
        if (enable == TRUE) {
            [statusItem setToolTip:(@"YubiKey enabled")];
            [statusItem setImage:[NSImage imageNamed:@"YubikeyEnabled"]];
            isEnabled = true;
            [[statusMenu itemAtIndex:0] setState:1];
            [self notify:@"YubiKey enabled"];
            NSDictionary *switchOffDelayPrefs = [[NSUserDefaults standardUserDefaults]
                                                 dictionaryForKey:@"switchOffDelay"];
            bool enabled = [[switchOffDelayPrefs valueForKey:@"enabled"] boolValue];
            if (enabled == TRUE) {
                NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
                [f setNumberStyle:NSNumberFormatterDecimalStyle];
                NSNumber *interval =
                [f numberFromString:[switchOffDelayPrefs valueForKey:@"interval"]];
                reDisableTimer = [self createTimer:(long)[interval integerValue]];
            }
        } else {
            [statusItem setToolTip:(@"YubiKey disabled")];
            [statusItem setImage:[NSImage imageNamed:@"YubikeyDisabled"]];
            isEnabled = false;
            [[statusMenu itemAtIndex:0] setState:0];
            [self notify:@"YubiKey disabled"];
        }
    }
}

-(bool)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key {
    return [key isEqualToString:@"status"]; 
}

- (bool)status {
    return isEnabled;
}

- (IBAction)toggle:(id)sender {
    if (isEnabled == TRUE) {
        [self enableYubiKey:FALSE];
    } else {
        [self enableYubiKey:TRUE];
    }
}

- (IBAction)toggleSwitchOffDelay:(id)sender {
    [controller save:self];
}

- (IBAction)toggleLockWhenUnplugged:(id)sender {
    [controller save:self];
}

- (IBAction)toggleDisplayNotications:(id)sender {
    [controller save:self];
}

- (IBAction)toggleDisableSleepLock:(id)sender {
    [controller save:self];
}

- (IBAction)about:(id)sender {
    [[aboutwc window] makeKeyAndOrderFront:self];
    [[aboutwc window] setOrderedIndex:0];
    [NSApp activateIgnoringOtherApps:YES];
    [aboutwc showWindow:self];
}

- (IBAction)pref:(id)sender {
    [[prefwc window] makeKeyAndOrderFront:self];
    [[prefwc window] setOrderedIndex:0];
    [NSApp activateIgnoringOtherApps:YES];
    [prefwc showWindow:self];
}

- (IBAction)quit:(id)sender {
    [yk enable];
    [self notify:@"YubiKey enabled"];
    [reDisableTimer invalidate];
    reDisableTimer = nil;
    [[NSApplication sharedApplication] terminate:self];
}

- (void)lockComputer {
    NSAppleScript *lockScript = [[NSAppleScript alloc] initWithSource:@"activate application \"ScreenSaverEngine\""];
    [lockScript executeAndReturnError:nil];
}

@end
