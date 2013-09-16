#!/bin/sh
sudo launchctl remove im.kernelpanic.PackageUninstallerHelper
sudo rm -rf /Library/LaunchDaemons/im.kernelpanic.PackageUninstallerHelper.plist
sudo rm -rf /Library/PrivilegedHelperTools/im.kernelpanic.PackageUninstallerHelper