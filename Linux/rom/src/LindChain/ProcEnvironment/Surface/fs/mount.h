/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#ifndef FS_MOUNT_H
#define FS_MOUNT_H

#include <CoreFoundation/CoreFoundation.h>
#include <mach/kern_return.h>
#include <LindChain/ProcEnvironment/Surface/fs/preserver.h>
#include <LindChain/ProcEnvironment/Surface/fs/sandbox.h>

typedef CF_OPTIONS(UInt64, FSMountAttr) {
    kFSMountAttrNone                    = 0,
    kFSMountAttrRead                    = 1ull << 0,    /* grants read access in file system sandbox */
    kFSMountAttrWrite                   = 1ull << 1,    /* grants write access in file system sandbox MARK: kFSMountAttrRead is required for this, otherwise will error with KERN_INVALID_ARGUMENT */
    kFSMountAttrClear                   = 1ull << 2,    /* clears the mount_dir or bind_dir if passed */
    kFSMountAttrReadPlatform            = 1ull << 3,    /* grants read access in file system sandbox if it is a platform process        TODO: not supported yet */
    kFSMountAttrWritePlatform           = 1ull << 4,    /* grants write access in file system sandbox if it is a platform process       TODO: not supported yet */
    kFSMountAttrReadEntitlement         = 1ull << 5,    /* grants read access in file system sandbox if a specific entitlement is met   TODO: not supported yet */
    kFSMountAttrWriteEntitlement        = 1ull << 6,    /* grants write access in file system sandbox if a specific entitlement is met  TODO: not supported yet */
};

/* TODO: not supported yet */
typedef struct {
    CFStringRef readEntitlement;
    CFStringRef writeEntitlement;
} kFSMountAttrEntitlementDefinition;

kern_return_t ksurface_fs_mount(FSMountAttr attributes, const char *mount_dir, const char *bind_dir, ...) __attribute__((deprecated("Use ksurface_fs_mount2(3) instead")));
kern_return_t ksurface_fs_mount2(FSMountAttr attributes, const char *device_dir, const char *mount_dir, ...);

kern_return_t ksurface_fs_umount(const char *mount_dir);

#endif /* FS_MOUNT_H */
