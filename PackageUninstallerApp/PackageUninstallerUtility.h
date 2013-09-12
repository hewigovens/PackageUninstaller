//
//  PackageUninstallerUtility.h
//  PackageUninstaller
//
//  Created by hewig on 9/7/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SFAuthorization;
@interface PackageUninstallerUtility : NSObject

+(BOOL)blessHelperWithLabel:(NSString *)label
              authorization:(AuthorizationRef)authRef
                      error:(NSError **)error;

@end
