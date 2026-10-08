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

#ifndef SURFACE_SYS_SETUID_H
#define SURFACE_SYS_SETUID_H

#include <LindChain/ProcEnvironment/Surface/surface.h>

typedef struct {
    uid_t ruid;
    uid_t euid;
    uid_t svuid;
    gid_t rgid;
    gid_t egid;
    gid_t svgid;
} ksurface_proc_ucred_backup_t;

ksurface_proc_ucred_backup_t proc_make_ucred_backup(ksurface_proc_t *proc);
void proc_set_sugid_if_applicable(ksurface_proc_t *proc, ksurface_proc_ucred_backup_t backup);

bool proc_is_privileged(ksurface_proc_t *proc);

DEFINE_SYSCALL_HANDLER(setuid);
DEFINE_SYSCALL_HANDLER(seteuid);
DEFINE_SYSCALL_HANDLER(setreuid);

#endif /* SURFACE_SYS_SETUID_H */
