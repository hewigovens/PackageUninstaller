//
//  main.m
//  PackageUninstallerHelper
//
//  Created by hewig on 8/30/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <syslog.h>
#import <sys/stat.h>
#import <pwd.h>
#import <xpc/xpc.h>

#import "launchctl_lite.h"
#import "Constants.h"

static void pu_xpc_dispatch_event(xpc_connection_t *connection, xpc_object_t *event);
int pu_handle_remove_cmd(const char*, const char*);
static NSSet* folder_white_list;

static void pu_xpc_peer_event_handler(xpc_connection_t connection, xpc_object_t event) {
    syslog(LOG_NOTICE,"Received event in helper.");
    
	xpc_type_t type = xpc_get_type(event);
    
	if (type == XPC_TYPE_ERROR) {
		if (event == XPC_ERROR_CONNECTION_INVALID) {
			// The client process on the other end of the connection has either
			// crashed or cancelled the connection. After receiving this error,
			// the connection is in an invalid state, and you do not need to
			// call xpc_connection_cancel(). Just tear down any associated state
			// here.
            
		} else if (event == XPC_ERROR_TERMINATION_IMMINENT) {
			// Handle per-connection termination cleanup.
		}
        
	} else {
        pu_xpc_dispatch_event(&connection, &event);
	}
}

static void pu_xpc_connection_handler(xpc_connection_t connection)  {
    syslog(LOG_NOTICE, "Configuring message event handler for helper.");
    
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		pu_xpc_peer_event_handler(connection, event);
	});
	
	xpc_connection_resume(connection);
}

static void pu_xpc_dispatch_event(xpc_connection_t* connection, xpc_object_t* event){

    xpc_connection_t remote = xpc_dictionary_get_remote_connection(*event);
    xpc_object_t reply = xpc_dictionary_create_reply(*event);
    xpc_dictionary_set_int64(reply, PU_VERSION_KEY, PU_COMMAND_VERSION);
    PUCommand cmd = (PUCommand)xpc_dictionary_get_int64(*event, PU_COMMAND_KEY);
    
    switch (cmd) {
        case PU_CMD_SYN:{
            xpc_dictionary_set_int64(reply, PU_COMMAND_KEY, PU_CMD_ACK);
            xpc_dictionary_set_int64(reply, PU_RET_KEY, 0);
        
            const char* white_list_path = xpc_dictionary_get_string(*event, PU_WHITE_LIST_KEY);
            if (white_list_path) {
                if (folder_white_list) {
                    [folder_white_list release];
                }
                syslog(LOG_NOTICE, "get file path:%s", white_list_path);
                NSArray* array = [[NSArray alloc] initWithContentsOfFile:@(white_list_path)];
                syslog(LOG_NOTICE, "white list count:%lu", (unsigned long)[array count]);
                folder_white_list = [[NSSet alloc] initWithArray:array];
                [array release];
            }
        }
            break;
        case PU_CMD_REMOVE_BOM:{
            syslog(LOG_NOTICE, "get package_id %s install prefix is %s",
                   xpc_dictionary_get_string(*event, PU_PACKAGE_ID_KEY),
                   xpc_dictionary_get_string(*event, PU_INSTALL_PREFIX_KEY));
            int ret = pu_handle_remove_cmd(xpc_dictionary_get_string(*event, "package_id"), xpc_dictionary_get_string(*event, "install_prefix"));
            xpc_dictionary_set_int64(reply, PU_RET_KEY, ret);
        }
            break;
        default:
            xpc_dictionary_set_int64(reply, PU_RET_KEY, -1);
            break;
    }
    
    xpc_connection_send_message(remote, reply);
    xpc_release(reply);
    
}

int pu_handle_remove_cmd(const char* package_id, const char* install_prefix){
    
    @autoreleasepool {
        
        int ret = 0;
        
        if (package_id == NULL || install_prefix == NULL) {
            return -1;
        }
        
        //check if system folder list is normal
        if ([folder_white_list count]<=50) {
            syslog(LOG_ERR,"system folder list is far way samll, refuse to remove.");
            return -2;
        }
        
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
        
        if (fp){
            
            NSMutableString* files = [NSMutableString new];
            NSString* prefix = [NSString stringWithUTF8String:install_prefix];
            NSFileManager* fileMgr = [NSFileManager defaultManager];
            
            //read output from pipe
            while ((read_count = fread(buf, 1, sizeof(buf), fp))) {
                NSString* str = [[NSString alloc] initWithBytes:buf length:read_count encoding:NSUTF8StringEncoding];
                [files appendString:str];
                [str release];
            }
            
            //construct and remove files
            NSMutableArray* filesList = [[files componentsSeparatedByString:@"\n"] mutableCopy];
            
            struct stat stat_buf;
            struct passwd* pwd;
            stat("/dev/console", &stat_buf);
            pwd = getpwuid(stat_buf.st_uid);
            
            if (pwd->pw_dir) {
                //maybe some leftovers
                [filesList addObject:[NSString stringWithFormat:@"%s/Library/Caches/%s", pwd->pw_dir, package_id]];
                [filesList addObject:[NSString stringWithFormat:@"%s/Library/Containers/%s", pwd->pw_dir, package_id]];
                [filesList addObject:[NSString stringWithFormat:@"%s/Library/Preferences/%s.plist", pwd->pw_dir, package_id]];
            }
            
            for (NSString* file in filesList) {
                if ([file isEqualToString:@""]) {
                    continue;
                }
                NSString* final_path;
                if ([file hasPrefix:@"/"]) {
                    final_path = file;
                } else{
                    if (![prefix isEqualToString:@"/"]){
                        final_path = [NSString stringWithFormat:@"%@/%@", prefix, file];
                    } else{
                        final_path = [NSString stringWithFormat:@"%@%@", prefix, file];
                    }
                }
                
                if ([folder_white_list containsObject:final_path]) {
                    syslog(LOG_NOTICE,"skip path:%s", [final_path UTF8String]);
                } else{
                    if([fileMgr fileExistsAtPath:final_path]){
                        NSError* error;
                        if(![fileMgr removeItemAtPath:final_path error:&error]){
                            syslog(LOG_ERR, "remove path:%s failed", [final_path UTF8String]);
                        } else{
                            syslog(LOG_NOTICE, "remove path:%s", [final_path UTF8String]);
                        }
                    }
                }
            }
            [filesList release];
            pclose(fp);
            
            //remove from receipts db
            snprintf(cmd, length+1, "/usr/sbin/pkgutil --forget %s", package_id);
            syslog(LOG_NOTICE, "cmd is %s", cmd);
            int r = system(cmd);
            if(r == 0){
                syslog(LOG_NOTICE, "remove %s from receipts db", package_id);
            } else{
                syslog(LOG_ERR, "remove %s from receipts db failed:%d", package_id,r);
            }
            
            //try remove launchd jobs
            if (launchctl_is_job_alive(package_id)) {
                launchctl_remove_cmd(package_id);
            }
            [files release];
        }
        free(cmd);
        return ret;
    }
}

int main(int argc, const char *argv[]) {
    
    launchctl_setup_system_context();
    
    xpc_connection_t service = xpc_connection_create_mach_service(PACKAGE_UNINSTALLER_HELPER_LABEL,
                                                                  dispatch_get_main_queue(),
                                                                  XPC_CONNECTION_MACH_SERVICE_LISTENER);
    
    if (!service) {
        syslog(LOG_NOTICE, "Failed to create service.");
        exit(EXIT_FAILURE);
    }
    
    syslog(LOG_NOTICE, "Configuring connection event handler for helper");
    xpc_connection_set_event_handler(service, ^(xpc_object_t connection) {
        pu_xpc_connection_handler(connection);
    });
    
    xpc_connection_resume(service);
    dispatch_main();
    
    xpc_release(service);
    if (folder_white_list) {
        [folder_white_list release];
    }
    return EXIT_SUCCESS;
}