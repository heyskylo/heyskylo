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

#ifndef PROC_SPAWN_H
#define PROC_SPAWN_H

#include <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/ProcEnvironment/Surface/trust/trust.h>

kern_return_t proc_spawn(ksurface_proc_t *parent, ksurface_proc_t **child, pid_t child_pid, int child_pidv, ksurface_trust_identity_t *identity);
kern_return_t proc_kill(ksurface_proc_t *child, int sig);

kern_return_t proc_reap(ksurface_proc_t *child);
kern_return_t proc_zombify(ksurface_proc_t *child);

kern_return_t proc_state_change(ksurface_proc_t *proc, int64_t status);

#endif /* PROC_SPAWN_H */
