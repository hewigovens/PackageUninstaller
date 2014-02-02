//
//  launchctl_lite.h
//  Package Uninstaller
//
//  Created by hewig on 9/6/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#ifndef Package_Uninstaller_launchctl_lite_h
#define Package_Uninstaller_launchctl_lite_h

#include "launch.h"
#include "launch_priv.h"
#include "vproc_priv.h"
#include "launch_internal.h"

#include <CoreFoundation/CoreFoundation.h>

int launchctl_submit_cmd(const char* label, const char* executable, const char* stdout_path, const char* stderr_path, const char* argv[]);
int launchctl_list_cmd(const char* label);
int launchctl_remove_cmd(const char* label);

bool launchctl_is_job_alive(const char* label);
void launchctl_setup_system_context(void);

int launchctl_submit_job(const char* label);
#endif