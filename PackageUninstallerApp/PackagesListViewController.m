//
//  PackagesListViewController.m
//  PackageUninstaller
//
//  Created by hewig on 8/30/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import "PackagesListViewController.h"
#import "AuthStatus.h"
#import "Constants.h"
#import "PackageUninstallerUtility.h"
#import <Security/Security.h>
#import <SecurityInterface/SFAuthorizationView.h>


@interface PackagesListViewController ()
{
    xpc_connection_t connection_;
}
@property (strong, retain) NSMutableArray* packagesList;
@property (nonatomic, weak) IBOutlet NSArrayController* packagesListArrayController;
@property (nonatomic, weak) IBOutlet NSTableView* packagesListView;
@property (nonatomic, weak) IBOutlet NSButton* uninstallButton;
@property (nonatomic, weak) IBOutlet NSButton* refreshButton;
@property (nonatomic, weak) IBOutlet SFAuthorizationView* authorizationView;
@property (strong, readonly) IBOutlet AuthStatus* authStatus;
@property (strong, retain) SFAuthorization* authorization;
@property (nonatomic, assign) BOOL helperAvailable;

@end

@implementation PackagesListViewController

@synthesize authStatus;
@synthesize packagesList;
@synthesize packagesListArrayController;
@synthesize packagesListView;
@synthesize uninstallButton;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.packagesList = [[NSMutableArray alloc] init];
        self.helperAvailable = NO;
    }
    return self;
}

- (void)awakeFromNib{
    [self initXPConnection];
    [self listAllPackages];
    [self.authorizationView setString:PACKAGE_UNINSTALLER_AUTH];
    [self.authorizationView setDelegate:self];
    [self.authorizationView setAutoupdate:YES];
}

#pragma mark IBActions

- (IBAction)uninstallClicked:(id)sender{
    
    if(-1 == [self.packagesListView selectedRow]){
        NSLog(@"no row selected");
        return;
    }
    NSDictionary* dict = self.packagesList[[self.packagesListView selectedRow]];
    NSDictionary* data = @{
                            @PU_PACKAGE_ID_KEY: dict[@"package_id"],
                            @PU_INSTALL_PREFIX_KEY:dict[@"install_prefix"]};
    
    [self sendXPCCommandAsync:PU_CMD_REMOVE_BOM withData:data Handler:^(xpc_object_t event){
    
        int ret = (int)xpc_dictionary_get_int64(event,PU_RET_KEY);
        NSLog(@"command PU_CMD_REMOVE_BOM returns:%d", ret);
        [self performSelectorOnMainThread:@selector(refreshClicked:) withObject:nil waitUntilDone:NO];
    }];
}

-(IBAction)refreshClicked:(id)sender{
    NSRange range = NSMakeRange(0, [[self.packagesListArrayController arrangedObjects] count]);
    
    [self.packagesListArrayController removeObjectsAtArrangedObjectIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
    [self listAllPackages];
}

- (void)sendXPCCommandAsync:(PUCommand)command withData:(NSDictionary*)data Handler:(xpc_handler_t) handler{
    xpc_object_t message =xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(message, PU_VERSION_KEY, PU_COMMAND_VERSION);
    xpc_dictionary_set_int64(message, PU_COMMAND_KEY, command);
    if (data) {
        for (NSString *key in data) {
            //TODO implement xpc_dictionary <=> NSDictionary
            xpc_dictionary_set_string(message, [key UTF8String], [data[key] UTF8String]);
        }
    }
    xpc_connection_send_message_with_reply(connection_, message, dispatch_get_main_queue(), handler);
    xpc_release(message);
}

- (void)listAllPackages{
    NSFileManager* fileMgr = [NSFileManager defaultManager];
    NSDirectoryEnumerator* fileEnumerator = [fileMgr enumeratorAtPath:@"/var/db/receipts"];

    NSString* file;
    while (file = [fileEnumerator nextObject]) {
        NSString* bundleId = [file stringByDeletingPathExtension];
        NSString* fileExt = [file pathExtension];
        if ([fileExt isEqualToString:@"bom"]) {
            continue;
        }
        if ([bundleId hasPrefix:@"com.apple"] || [bundleId hasPrefix:@"com.microsoft"]) {
            continue;
        }
        
        NSDictionary* infoPlist = [[NSDictionary alloc]initWithContentsOfFile:[NSString stringWithFormat:@"/var/db/receipts/%@", file]];
        
        NSString* install_prefix;
        NSString* temp_prefix = infoPlist[@"InstallPrefixPath"];
        if ([temp_prefix isEqualToString:@""] || [temp_prefix isEqualToString:@"/"]){
            install_prefix = @"/";
        } else{
            install_prefix = [NSString stringWithFormat:@"/%@", temp_prefix];
        }
    
        [self.packagesListArrayController addObject:@{
                                                      @"name": [infoPlist[@"PackageFileName"] stringByDeletingPathExtension],
                                                      @"package_id":bundleId,
                                                      @"install_prefix":install_prefix}];
    }
}

-(void)initXPConnection{
    xpc_connection_t connection = xpc_connection_create_mach_service(PACKAGE_UNINSTALLER_HELPER_LABEL, NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR) {
            
            if (event == XPC_ERROR_CONNECTION_INTERRUPTED) {
                NSLog(@"XPC connection interupted.");
                
            } else if (event == XPC_ERROR_CONNECTION_INVALID) {
                 NSLog(@"XPC connection invalid, releasing.");
                
            } else {
                 NSLog(@"Unexpected XPC connection error.");
            }
            
            self.helperAvailable = NO;
            [self.uninstallButton setEnabled:NO];
            
        } else {
            NSLog(@"Unexpected XPC event");
        }
    });
    
    xpc_connection_resume(connection);
    
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(message, PU_VERSION_KEY, PU_COMMAND_VERSION);
    xpc_dictionary_set_int64(message, PU_COMMAND_KEY, PU_CMD_SYN);
    xpc_dictionary_set_string(message, PU_WHITE_LIST_KEY, [[[NSBundle mainBundle] pathForResource:@"SystemFolders" ofType:@"plist"] UTF8String]);
    NSLog(@"send syn command");
    
    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, message);
    PUCommand cmd = (PUCommand)xpc_dictionary_get_int64(reply, PU_COMMAND_KEY);
    long long ret = xpc_dictionary_get_int64(reply, PU_RET_KEY);
    if (cmd == PU_CMD_ACK && ret == 0) {
        connection_ = connection;
        NSLog(@"connection established");
        self.helperAvailable = YES;
        [self.uninstallButton setEnabled:YES];
    }
    xpc_release(message);
}

#pragma mark SFAuthorizationViewDelegate

- (void)authorizationViewDidAuthorize:(SFAuthorizationView *)view{
    if (view != self.authorizationView) {
        return;
    }
    self.authorization = [view authorization];
    self.authStatus.isAuthorized = YES;
    if (!self.helperAvailable) {
        NSError *error;
        if([PackageUninstallerUtility blessHelperWithLabel:@PACKAGE_UNINSTALLER_HELPER_LABEL
                                             authorization:[self.authorization authorizationRef]
                                                     error:&error]){
            NSLog(@"bless helper successfully");
            [self initXPConnection];
        } else{
            NSLog(@"bless helper failed:%@",error);
        }
    }
}

- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view{
    if (view != self.authorizationView) {
        return;
    }
    self.authorization = nil;
    self.authStatus.isAuthorized = NO;
}

@end
