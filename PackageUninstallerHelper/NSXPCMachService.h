//
//  PUXPCService.h
//  PackageUninstaller
//
//  Created by hewig on 12/27/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^XPCEventHandler)(xpc_object_t event);

@interface NSXPCMachService : NSObject

@property (nonatomic, copy) XPCEventHandler eventHandler;
@property (nonatomic, copy) XPCEventHandler errorHandler;

-(NSXPCMachService*)initWith:(NSString*)serviceName;

-(void)Run;
-(void)Stop;

@end
