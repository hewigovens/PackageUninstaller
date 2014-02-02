//
//  PUDataSource.h
//  PackageUninstaller
//
//  Created by hewig on 2/2/14.
//  Copyright (c) 2014 hewig. All rights reserved.
//


@interface PUDataSource: NSObject

@property (nonatomic, strong, readonly) NSArray* packageList;
@property (nonatomic, strong, readonly) NSMutableDictionary* prefixMap;

-(void)load;

@end
