//
//  PUDataSource.m
//  PackageUninstaller
//
//  Created by hewig on 2/2/14.
//  Copyright (c) 2014 hewig. All rights reserved.
//

#import "PUDataSource.h"

@interface PUDataSource() <NSOutlineViewDelegate, NSOutlineViewDataSource>

@property (nonatomic, strong, readwrite) NSMutableArray* packageList;
@property (nonatomic, strong, readwrite) NSMutableDictionary* prefixMap;
@property (nonatomic, strong) NSDateFormatter* dateFormatter;

@end

@implementation PUDataSource

-(instancetype)init
{
    self = [super init];
    if (self) {
        _packageList = [NSMutableArray new];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale currentLocale];
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
        [self load];
    }
    return self;
}

-(void)remove:(id)obj
{
    [self.packageList removeObject:obj];
}

-(void)load
{
    NSFileManager* fileMgr = [NSFileManager defaultManager];
    
    [self.packageList removeAllObjects];
    NSArray* histories = [NSArray arrayWithContentsOfFile:@"/Library/Receipts/InstallHistory.plist"];
    
    for (NSDictionary* dict in histories){
        NSUInteger existedCount = [dict[@"packageIdentifiers"] count];
        for (NSString* packageId in dict[@"packageIdentifiers"]){
            NSString* path = [NSString stringWithFormat:@"/var/db/receipts/%@.plist", packageId];
            if (![fileMgr fileExistsAtPath:path]) {
                existedCount = existedCount - 1;
            }
        }
        if (existedCount > 0) {
            [self.packageList addObject:dict];
        }
    }
    
    if (self.prefixMap) {
        self.prefixMap = nil;
    }
    self.prefixMap = [NSMutableDictionary new];
    
    NSDirectoryEnumerator* fileEnumerator = [fileMgr enumeratorAtPath:@"/var/db/receipts"];
    
    NSString* file;
    while (file = [fileEnumerator nextObject]) {
        NSString* bundleId = [file stringByDeletingPathExtension];
        NSString* fileExt = [file pathExtension];
        if ([fileExt isEqualToString:@"bom"]) {
            continue;
        }
        if ([bundleId hasPrefix:@"com.apple"] || [bundleId hasPrefix:@"com.microsoft"]) {
            //continue;
        }
        
        NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile:
                                   [NSString stringWithFormat:@"/var/db/receipts/%@", file]];
        
        NSString* install_prefix;
        NSString* temp_prefix = infoPlist[@"InstallPrefixPath"];
        if ([temp_prefix isEqualToString:@""] || [temp_prefix isEqualToString:@"/"]){
            install_prefix = @"/";
        } else{
            install_prefix = [NSString stringWithFormat:@"/%@", temp_prefix];
        }
        self.prefixMap[bundleId] = install_prefix;
    }
}

#pragma mark NSOutlineViewDelegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (item == nil) {
        return [self.packageList count];
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        return [item[@"packageIdentifiers"] count];
    }
    return 0;
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (item == nil) {
        return [self.packageList objectAtIndex:index];
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        return [item[@"packageIdentifiers"] objectAtIndex:index];
    }
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if (item == nil) {
        return  nil;
    }
    
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            return item[@"displayName"];
        }
        if ([item isKindOfClass:[NSString class]]) {
            return item;
        }
        return @"↑";
    }
    
    if ([tableColumn.identifier isEqualToString:@"version"]) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            return item[@"displayVersion"];
        }
        return @"↑";
    }
    
    if ([tableColumn.identifier isEqualToString:@"installed_by"]) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            return item[@"processName"];
        }
        return @"↑";
    }
    
    if ([tableColumn.identifier isEqualToString:@"install_prefix"]) {
        if ([item isKindOfClass:[NSString class]]) {
            return self.prefixMap[item];
        }
        return @"";
    }
    
    if ([tableColumn.identifier isEqualToString:@"date"]) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            return [self.dateFormatter stringFromDate:item[@"date"]];
        }
        return @"↑";
    }
    
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if ([item isKindOfClass:[NSDictionary class]]) {
        return YES;
    } else{
        return NO;
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
    return YES;
}

@end
