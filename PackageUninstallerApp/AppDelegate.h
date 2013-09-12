//
//  AppDelegate.h
//  PackageUninstallerApp
//
//  Created by hewig on 9/7/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PackagesListViewController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>{
    PackagesListViewController* packageListController;
}

@property (assign) IBOutlet NSWindow *window;

@end
