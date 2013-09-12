//
//  Constants.h
//  Package Uninstaller
//
//  Created by hewig on 9/7/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#ifndef Package_Uninstaller_Constants_h
#define Package_Uninstaller_Constants_h

#define PACKAGE_UNINSTALLER_APP_LABEL       "im.kernelpanic.PackageUninstallerApp"
#define PACKAGE_UNINSTALLER_HELPER_LABEL    "im.kernelpanic.PackageUninstallerHelper"
#define PACKAGE_UNINSTALLER_AUTH            "im.kernelpanic.PackageUninstaller.auth"

#define PU_COMMAND_VERSION 1
#define PU_VERSION_KEY          "version"
#define PU_COMMAND_KEY          "cmd"
#define PU_DATA_KEY             "data"
#define PU_RET_KEY              "ret"
#define PU_WHITE_LIST_KEY       "white_list_path"
#define PU_PACKAGE_ID_KEY       "package_id"
#define PU_INSTALL_PREFIX_KEY   "install_prefix"

typedef enum{
    PU_CMD_SYN = 0,
    PU_CMD_ACK,
    PU_CMD_REMOVE_BOM
}PUCommand;

#endif