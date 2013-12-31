//
//  PUXPCService.m
//  PackageUninstaller
//
//  Created by hewig on 12/27/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <syslog.h>
#import "NSXPCMachService.h"
#import "Constants.h"

@interface NSXPCMachService()
{
    xpc_connection_t _service;
}

@end

@implementation NSXPCMachService

-(NSXPCMachService*)initWith:(NSString*)serviceName
{
    self = [super init];
    if (self) {
        _service = xpc_connection_create_mach_service([serviceName UTF8String], dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    }
    return self;
}

-(void)Run
{
    if (_service) {
        [self setupHandler];
        xpc_connection_resume(_service);
        dispatch_main();
    } else{
        NSLog(@"Failed to start service.");
    }
    
}

-(void)dealloc
{
    if (_service) {
        xpc_release(_service);
    }
    [_eventHandler release];
    [_errorHandler release];
    [super dealloc];
}

-(void)Stop
{
    //
}

-(void)setupHandler
{
    xpc_connection_set_event_handler(_service, ^(xpc_object_t connection) {
        
        if (!_eventHandler) {
            _eventHandler = ^(xpc_object_t event){
                NSLog(@"event handled by default handler, do nothing");
            };
        }
        
        if (!_errorHandler) {
            _errorHandler = ^(xpc_object_t event){
                NSLog(@"event handled by default handler, do nothing");
            };
        }
        
        xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
            xpc_type_t type = xpc_get_type(event);
            
            if (type == XPC_TYPE_ERROR) {
                _errorHandler(event);
            } else {
                _eventHandler(event);
            }
        });
        
        xpc_connection_resume(connection);
    });
}

@end