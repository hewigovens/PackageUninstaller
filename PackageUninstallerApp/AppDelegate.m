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

@implementation AppDelegate

- (void)awakeFromNib{
    packageListController = [[PackagesListViewController alloc] initWithNibName:@"PackagesListViewController" bundle:[NSBundle mainBundle]];
    self.window.contentView = [packageListController view];
    self.window.delegate = self;
    self.window.title = NSLocalizedStringFromTable(@"CFBundleName", @"InfoPlist", "General Package Uninstaller");
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag{
    [self.window makeKeyAndOrderFront:self];
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification{

}



@end