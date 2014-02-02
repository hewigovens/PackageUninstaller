//
//  AppDelegate.m
//  PackageUninstallerApp
//
//  Created by hewig on 9/7/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import "AppDelegate.h"
#import <ServiceManagement/ServiceManagement.h>
#import <SecurityInterface/SFAuthorizationView.h>

#import <Crashlytics/Crashlytics.h>
#import <Sparkle/Sparkle.h>

@implementation AppDelegate

- (void)awakeFromNib
{
    packageListController = [[PackagesListViewController alloc] initWithNibName:@"PackagesListViewController" bundle:[NSBundle mainBundle]];
    self.window.contentView = [packageListController view];
    self.window.delegate = self;
    self.window.title = NSLocalizedStringFromTable(@"CFBundleName", @"InfoPlist", "General Package Uninstaller");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [Crashlytics startWithAPIKey:@"00294b074c27a6569db329a72df442fbff108a8c"];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    [self.window makeKeyAndOrderFront:self];
    return YES;
}

-(IBAction)checkUpdates:(id)sender
{
    [[SUUpdater sharedUpdater] checkForUpdates:sender];
}

@end