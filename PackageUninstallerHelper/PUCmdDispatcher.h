//
//  PUCmdDispatcher.h
//  PackageUninstaller
//
//  Created by hewig on 12/31/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PUCmdDispatcher : NSObject

@property (nonatomic,retain) NSSet* whiteList;

-(void)handleCommands:(xpc_object_t*)event;

@end
