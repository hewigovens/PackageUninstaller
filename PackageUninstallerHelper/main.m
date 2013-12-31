//
//  main.m
//  PackageUninstallerHelper
//
//  Created by hewig on 8/30/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import "launchctl_lite.h"
#import "Constants.h"
#import "PUCmdDispatcher.h"
#import "NSXPCMachService.h"

int main(int argc, const char *argv[]) {
    
    @autoreleasepool {
        
        NSXPCMachService* service = [[NSXPCMachService alloc] initWith:@PACKAGE_UNINSTALLER_HELPER_LABEL];
        PUCmdDispatcher* dispatcher = [[PUCmdDispatcher alloc] init];
        
        service.eventHandler = ^(xpc_object_t event){
            [dispatcher handleCommands:&event];
        };
        
        [service Run];
        [service Stop];
        
        [service release];
        [dispatcher release];
        
        return EXIT_SUCCESS;
    }
}