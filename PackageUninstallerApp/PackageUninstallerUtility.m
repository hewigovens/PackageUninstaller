//
//  PackageUninstallerUtility.m
//  PackageUninstaller
//
//  Created by hewig on 9/7/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import "PackageUninstallerUtility.h"
#import <ServiceManagement/ServiceManagement.h>
#import <Security/Security.h>

@implementation PackageUninstallerUtility

+(BOOL)blessHelperWithLabel:(NSString *)label
              authorization:(AuthorizationRef)authorizationRef
                      error:(NSError **)error{
    
	BOOL result = NO;
    OSStatus status = 0;
    AuthorizationRef authRef = NULL;
    
    if (authorizationRef!= NULL) {
        authRef = authorizationRef;
    } else {
        
        AuthorizationItem authItem		= { kSMRightBlessPrivilegedHelper, 0, NULL, 0 };
        AuthorizationRights authRights	= { 1, &authItem };
        AuthorizationFlags flags		=	kAuthorizationFlagDefaults	|
        kAuthorizationFlagInteractionAllowed|
        kAuthorizationFlagPreAuthorize|
        kAuthorizationFlagExtendRights;
        
        status = AuthorizationCreate(&authRights, kAuthorizationEmptyEnvironment, flags, &authRef);
        
        if (status != errAuthorizationSuccess) {
            NSLog(@"%@",[NSString stringWithFormat:@"Failed to create AuthorizationRef. Error code: %d", (int)status]);
        }
        return result;
    }
    
    CFErrorRef cfError;
    result = SMJobBless(kSMDomainSystemLaunchd, (__bridge CFStringRef)label, authRef,&cfError);
    if (error) {
        *error = CFBridgingRelease(cfError);
    }
    
    return result;
}

@end
