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

#include <LindChain/ProcEnvironment/Surface/sys/cred/getsid.h>
#include <LindChain/ProcEnvironment/Surface/proc/lookup.h>
#include <LindChain/ProcEnvironment/Surface/proc/list.h>
#include <LindChain/ProcEnvironment/Surface/proc/permit.h>
#include <errno.h>

static kern_return_t proc_visible_target_for_pid(ksurface_proc_snapshot_t *caller,
                                                 pid_t pid,
                                                 ksurface_proc_t **target)
{
    kern_return_t kr = proc_for_pid(pid, target);
    if(kr != KERN_SUCCESS || *target == NULL)
    {
        return KERN_NOT_FOUND;
    }
    
    proc_visibility_t vis = proc_get_proc_visibility(caller);
    if(!proc_can_see_proc(caller, *target, vis))
    {
        kvo_release(*target);
        *target = NULL;
        return KERN_NOT_FOUND;
    }
    
    return KERN_SUCCESS;
}

DEFINE_SYSCALL_HANDLER(getsid)
{
    pid_t u_pid = (pid_t)args[0];
    if(u_pid == 0)
    {
        return proc_getsid(sys_proc_snapshot_);
    }
    
    ksurface_proc_t *target = NULL;
    kern_return_t kr = proc_visible_target_for_pid(sys_proc_snapshot_, u_pid, &target);
    if(kr != KERN_SUCCESS)
    {
        sys_return_failure_with_errno(ESRCH);
    }
    
    kvo_rdlock(target);
    pid_t sid = proc_getsid(target);
    kvo_unlock(target);
    kvo_release(target);
    
    return sid;
}

DEFINE_SYSCALL_HANDLER(getpgrp)
{
    return proc_getpgid(sys_proc_snapshot_);
}

DEFINE_SYSCALL_HANDLER(getpgid)
{
    pid_t u_pid = (pid_t)args[0];
    if(u_pid == 0)
    {
        return proc_getpgid(sys_proc_snapshot_);
    }
    
    ksurface_proc_t *target = NULL;
    kern_return_t kr = proc_visible_target_for_pid(sys_proc_snapshot_, u_pid, &target);
    if(kr != KERN_SUCCESS)
    {
        sys_return_failure_with_errno(ESRCH);
    }
    
    kvo_rdlock(target);
    pid_t pgid = proc_getpgid(target);
    kvo_unlock(target);
    kvo_release(target);
    
    return pgid;
}
