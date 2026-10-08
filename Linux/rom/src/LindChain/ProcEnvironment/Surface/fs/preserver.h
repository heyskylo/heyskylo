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

#ifndef KSURFACE_FS_PRESERVER_H
#define KSURFACE_FS_PRESERVER_H

#include <mach/kern_return.h>
#include <stdint.h>
#include <limits.h>
#include <stddef.h>

typedef enum: uint8_t {
    kFSNodeTypeSymbolicLink,
    kFSNodeTypeDirectory,
} FSNodeType;

typedef struct {
    FSNodeType type;
    char name[PATH_MAX];
    char target[PATH_MAX];
} FSPreserverNode;

typedef struct {
    FSNodeType type;
    const char *name;
    const char *target;
} FSPreserverDesc;

kern_return_t ksurface_fs_preserver_add_node(FSPreserverNode node);
kern_return_t ksurface_fs_preserver_remove_node(const char *path);

kern_return_t ksurface_fs_preserver_kickstart(void);

#endif /* KSURFACE_FS_PRESERVER_H */
