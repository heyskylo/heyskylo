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

#ifndef KSURFACE_FS_SANDBOX_H
#define KSURFACE_FS_SANDBOX_H

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <limits.h>
#include <stdbool.h>
#include <LindChain/ProcEnvironment/Surface/fs/preserver.h>

typedef enum: UInt8 {
    kFSMountPermissionNone      = 0,
    kFSMountPermissionRead      = 1,
    kFSMountPermissionReadWrite = 2,
} FSMountPermissionFlags;

kern_return_t ksurface_fs_sandbox_init(void);
kern_return_t ksurface_fs_sandbox_registry_add(FSMountPermissionFlags permission, FSNodeType type, const char *mount_dir, const char *bind_dir);
kern_return_t ksurface_fs_sandbox_registry_remove(const char *path);
CFArrayRef ksurface_fs_sandbox_copy_sandbox_extensions(const char *guest_path, FSMountPermissionFlags wanted);
CFDataRef ksurface_fs_sandbox_copy_sandbox_extension_for_arbitary_path(const char *guest_path, FSMountPermissionFlags wanted);

#endif /* KSURFACE_FS_SANDBOX_H */
