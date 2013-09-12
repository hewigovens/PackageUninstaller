//
//  main.c
//  launchctl_lite_test
//
//  Created by hewig on 9/6/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#include <stdio.h>
#include "launchctl_lite.h"

void test_list_cmd()
{
    char* label2 = "im.kernelpanic.PackageUninstallerHelper";
    launchctl_list_cmd(label2);
    if (launchctl_is_job_alive(label2)) {
        printf("%s is alive\n", label2);
    } else{
        printf("%s is dead\n", label2);
    }

}

void test_submit_cmd()
{
    launchctl_submit_cmd("im.kernelpanic.PackageUninstallerHelper",
               "/Users/hewig/Desktop/quick_n_dirty/Package Uninstaller/build/Debug/im.kernelpanic.PackageUninstallerHelper",
               "/tmp/im.kernelpanic.log",
               "/tmp/im.kernelpanic.log",
               NULL);
}

void test_remove_cmd()
{
    launchctl_remove_cmd("im.kernelpanic.PackageUninstallerHelper");
}

int main(int argc, const char * argv[])
{
    if (getuid() == 0) {
        launchctl_setup_system_context();
    }
    test_list_cmd();
    return 0;
}

