//
//  PUCmdDispatcher.m
//  PackageUninstaller
//
//  Created by hewig on 12/31/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <xpc/xpc.h>
#import <pwd.h>
#import <sys/stat.h>

#import "PUCmdDispatcher.h"
#import "Constants.h"
#import "launchctl_lite.h"

@interface PUCmdDispatcher()

@end;

@implementation PUCmdDispatcher

-(PUCmdDispatcher*)init
{
    self = [super init];
    if (self) {
        launchctl_setup_system_context();
    }
    return self;
}

-(void)handleCommands:(xpc_object_t*)event
{
    xpc_connection_t remote = xpc_dictionary_get_remote_connection(*event);
    xpc_object_t reply = xpc_dictionary_create_reply(*event);
    PUCommand cmd = (PUCommand)xpc_dictionary_get_int64(*event, PU_COMMAND_KEY);
    
    switch (cmd) {
        case PU_CMD_ACK:
        case PU_CMD_SYN:
        {
            [self handleCommandSYN:event withReply:&reply];
            break;
        }
        case PU_CMD_REMOVE_BOM:
        {
            [self handleCommandRemove:event withReply:&reply];
            break;
        }
        case PU_CMD_EXIT:
        {
            [self handleCommandExit:event withReply:&reply];
            break;
        }
        default:
            break;
    }
    xpc_dictionary_set_int64(reply, PU_VERSION_KEY, PU_COMMAND_VERSION);
    xpc_connection_send_message(remote, reply);
    [reply release];
}

-(void)handleCommandSYN:(xpc_object_t*)event withReply:(xpc_object_t*)reply
{
    xpc_dictionary_set_int64(*reply, PU_COMMAND_KEY, PU_CMD_ACK);
    xpc_dictionary_set_int64(*reply, PU_RET_KEY, 0);
    
    const char* white_list_path = xpc_dictionary_get_string(*event, PU_WHITE_LIST_KEY);
    if (white_list_path) {
        if (_whiteList) {
            [_whiteList release];
        }
        NSLog(@"get file path:%s", white_list_path);
        NSArray* array = [[NSArray alloc] initWithContentsOfFile:@(white_list_path)];
        
        NSLog(@"white list count:%lu", (unsigned long)[array count]);
        _whiteList = [[NSSet alloc] initWithArray:array];
        [array release];
    }
}

-(void)handleCommandRemove:(xpc_object_t*)event withReply:(xpc_object_t*)reply
{
    NSLog(@"get package_id %s install prefix is %s",
           xpc_dictionary_get_string(*event, PU_PACKAGE_ID_KEY),
           xpc_dictionary_get_string(*event, PU_INSTALL_PREFIX_KEY));
    int ret = [self removePackageID:xpc_dictionary_get_string(*event, "package_id")
                         WithPrefix:xpc_dictionary_get_string(*event, "install_prefix")];
    
    xpc_dictionary_set_int64(*reply, PU_RET_KEY, ret);
    xpc_dictionary_set_int64(*reply, PU_VERSION_KEY, PU_COMMAND_VERSION);
}

-(void)handleCommandExit:(xpc_object_t*)event withReply:(xpc_object_t*)reply
{
    xpc_dictionary_set_int64(*reply, PU_RET_KEY, 0);
    xpc_dictionary_set_int64(*reply, PU_VERSION_KEY, PU_COMMAND_VERSION);

    double delayInSeconds = 4.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        exit(EXIT_SUCCESS);
    });
}

-(NSString*)currentUserHome
{
    NSString* home = nil;
    struct stat stat_buf;
    struct passwd* pwd;
    stat("/dev/console", &stat_buf);
    pwd = getpwuid(stat_buf.st_uid);
    
    if (pwd->pw_dir) {
        home = [[[NSString alloc] initWithCString:pwd->pw_dir encoding:NSUTF8StringEncoding] autorelease];
    }
    return home;
}

-(void)removeReceipt:(const char*)package_id
{
    char* cmd_temp = "/usr/sbin/pkgutil --files ";
    unsigned long length = strlen(cmd_temp) + strlen(package_id) + 1;
    char* cmd = malloc(length*sizeof(char));

    snprintf(cmd, length+1, "/usr/sbin/pkgutil --forget %s", package_id);
    NSLog(@"cmd is %s", cmd);
    int ret = system(cmd);
    if(ret == 0){
        NSLog(@"remove %s from receipts db", package_id);
    } else{
        NSLog(@"remove %s from receipts db failed:%d", package_id,ret);
    }
    free(cmd);
}

-(NSArray*)filesAssociateWith:(const char*)package_id
{
    char* cmd_temp = "/usr/sbin/pkgutil --files ";
    unsigned long length = strlen(cmd_temp) + strlen(package_id) + 1;
    char* cmd = malloc(length*sizeof(char));
    
    FILE* fp = NULL;
    char* buf[512];
    size_t read_count;
    
    memset(cmd, '\0', length);
    memset(buf, '\0', sizeof(buf));
    
    snprintf(cmd, length, "%s%s", cmd_temp, package_id);
    
    fp = popen(cmd, "r");
    free(cmd);
    if (fp){
        
        NSMutableString* files = [NSMutableString new];
        //read output from pipe
        while ((read_count = fread(buf, 1, sizeof(buf), fp))) {
            NSString* str = [[NSString alloc] initWithBytes:buf length:read_count encoding:NSUTF8StringEncoding];
            [files appendString:str];
            [str release];
        }
        
        //construct and remove files
        NSMutableArray* filesList = [[files componentsSeparatedByString:@"\n"] mutableCopy];
    
        NSString* userHome = [self currentUserHome];
        if (userHome) {
            //maybe some leftovers
            [filesList addObject:[NSString stringWithFormat:@"%@/Library/Caches/%s", userHome, package_id]];
            [filesList addObject:[NSString stringWithFormat:@"%@/Library/Containers/%s", userHome, package_id]];
            [filesList addObject:[NSString stringWithFormat:@"%@/Library/Preferences/%s.plist", userHome, package_id]];
        }
        pclose(fp);
        NSArray* array = [NSArray arrayWithArray:filesList];
        [filesList release];
        [files release];
        return array;
    } else{
        return nil;
    }
}

-(int)removePackageID:(const char*)package_id WithPrefix:(const char*)path_prefix
{
    int ret = 0;
    
    if (package_id == NULL || path_prefix == NULL) {
        return -1;
    }
    
    //check if system folder list is normal
    if ([_whiteList count]<=50) {
        NSLog(@"system folder list is far way samll, refuse to remove.");
        return -2;
    }
    
    //remove files
    NSArray* filesList = [self filesAssociateWith:package_id];
    NSString* prefix = [NSString stringWithUTF8String:path_prefix];
    NSFileManager* fileMgr = [NSFileManager defaultManager];
    for (NSString* file in filesList)
    {
        if ([file isEqualToString:@""])
        {
            continue;
        }
        
        NSString* final_path;
        if ([file hasPrefix:@"/"])
        {
            final_path = file;
        }
        else
        {
            if (![prefix isEqualToString:@"/"])
            {
                final_path = [NSString stringWithFormat:@"%@/%@", prefix, file];
            } else
            {
                final_path = [NSString stringWithFormat:@"%@%@", prefix, file];
            }
        }
        
        if ([_whiteList containsObject:final_path])
        {
            NSLog(@"skip path:%s", [final_path UTF8String]);
        }
        else
        {
            if([fileMgr fileExistsAtPath:final_path])
            {
                NSError* error;
                if(![fileMgr removeItemAtPath:final_path error:&error])
                {
                    NSLog(@"remove path:%s failed", [final_path UTF8String]);
                } else{
                    NSLog(@"remove path:%s", [final_path UTF8String]);
                }
            }
        }
    }
    
    //remove receipt
    [self removeReceipt:package_id];
    
    //try remove launchd jobs
    if (launchctl_is_job_alive(package_id)) {
        launchctl_remove_cmd(package_id);
    }
    return ret;
}

@end
