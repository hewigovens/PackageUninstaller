//
//  PackagesListViewController.m
//  PackageUninstaller
//
//  Created by hewig on 8/30/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#import <Security/Security.h>
#import <SecurityInterface/SFAuthorizationView.h>

#import "PackagesListViewController.h"
#import "AuthStatus.h"
#import "Constants.h"
#import "PUDataSource.h"

#import "PackageUninstallerUtility.h"


@interface PackagesListViewController ()
{
    xpc_connection_t connection_;
}

@property (nonatomic, weak) IBOutlet NSOutlineView* packagesListView;
@property (nonatomic, weak) IBOutlet NSButton* uninstallButton;
@property (nonatomic, weak) IBOutlet NSButton* refreshButton;
@property (nonatomic, weak) IBOutlet SFAuthorizationView* authorizationView;
@property (nonatomic, weak) IBOutlet AuthStatus* authStatus;
@property (nonatomic, strong) SFAuthorization* authorization;
@property (nonatomic, strong) PUDataSource* datasource;
@property (nonatomic, assign) BOOL helperAvailable;

@end

@implementation PackagesListViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _datasource = [[PUDataSource alloc] init];
        _helperAvailable = NO;
    }
    return self;
}

-(void)dealloc
{
    if (connection_) {
        xpc_release(connection_);
    }
}

- (void)awakeFromNib{
    [self configDatasource];
    [self.authorizationView setString:PACKAGE_UNINSTALLER_AUTH];
    [self.authorizationView setDelegate:self];
    [self.authorizationView setAutoupdate:YES];
}

#pragma mark IBActions

- (IBAction)uninstallClicked:(id)sender{
    
    NSUInteger selectedRow = [self.packagesListView selectedRow];
    if(selectedRow == -1){
        NSLog(@"no row selected");
        return;
    }

    id selectedItem = [self.packagesListView itemAtRow:selectedRow];
    
    NSMutableArray* cmds = [NSMutableArray new];
    
    if ([selectedItem isKindOfClass:[NSString class]]) {
        NSDictionary* data = @{@PU_PACKAGE_ID_KEY: selectedItem,
                               @PU_INSTALL_PREFIX_KEY:self.datasource.prefixMap[selectedItem]
                              };
        [cmds addObject:data];
    } else if ([selectedItem isKindOfClass:[NSDictionary class]]){
        NSArray* packageIds = [selectedItem valueForKey:@"packageIdentifiers"];
        for (NSString* packageId in packageIds){
            NSDictionary* data = @{
                                    @PU_PACKAGE_ID_KEY: packageId,
                                    @PU_INSTALL_PREFIX_KEY:self.datasource.prefixMap[packageId]
                                 };
            [cmds addObject:data];
        }
    }
    
    for (NSDictionary* data in cmds){
        [self sendXPCCommandAsync:PU_CMD_REMOVE_BOM withData:data Handler:^(xpc_object_t event){
            
            int ret = (int)xpc_dictionary_get_int64(event,PU_RET_KEY);
            NSLog(@"command PU_CMD_REMOVE_BOM returns:%d", ret);
            [self.datasource remove:selectedItem];
            [self performSelectorOnMainThread:@selector(refreshClicked:) withObject:nil waitUntilDone:NO];
        }];
    }
}

-(IBAction)refreshClicked:(id)sender{
    [self.packagesListView reloadData];
}

-(void)configDatasource
{
    [self.packagesListView setDataSource:(id<NSOutlineViewDataSource>)self.datasource];
    [self.packagesListView setDelegate:(id<NSOutlineViewDelegate>)self.datasource];
}

#pragma mark XPC

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
