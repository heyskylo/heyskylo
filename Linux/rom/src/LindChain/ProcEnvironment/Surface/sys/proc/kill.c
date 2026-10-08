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

#include <LindChain/ProcEnvironment/Surface/sys/proc/kill.h>
#include <LindChain/ProcEnvironment/Surface/proc/proc.h>
#include <LindChain/ProcEnvironment/Surface/proc/permit.h>
#include <LindChain/ProcEnvironment/Surface/proc/list.h>
#include <errno.h>

static bool kill_one_target(ksurface_proc_snapshot_t *caller_snapshot,
                            ksurface_proc_t *target,
                            int sig)
{
    if(!proc_snapshot_primitive_over_proc_allowed(caller_snapshot, target, kPEEntitlementFlagProcessKill, kPEEntitlementFlagNone))
    {
        return false;
    }
    
    kvo_rdlock(target);
    bool system_process = (target->bsd.kp_proc.p_flag & P_SYSTEM) != 0;
    kvo_unlock(target);
    
    if(system_process)
    {
        return false;
    }
    
    if(sig == 0)
    {
        return true;
    }
    
    return proc_kill(target, sig) == KERN_SUCCESS;
}

DEFINE_SYSCALL_HANDLER(kill)
{
    pid_t u_pid = (pid_t)args[0];
    int u_signal = (int)args[1];
    
    if(u_signal < 0 || u_signal >= NSIG)
    {
        sys_return_failure_with_errno(EINVAL);
    }
    
    if(u_pid > 0)
    {
        ksurface_proc_t *target = NULL;
        kern_return_t kr = proc_for_pid(u_pid, &target);
        if(kr != KERN_SUCCESS || target == NULL)
        {
            sys_return_failure_with_errno(ESRCH);
        }
        
        bool ok = kill_one_target(sys_proc_snapshot_, target, u_signal);
        kvo_release(target);
        if(!ok)
        {
            sys_return_failure_with_errno(errno ? errno : EPERM);
        }
        
        sys_return;
    }
    
    proc_flavour_t flavour;
    pid_t selector = 0;
    
    if(u_pid == 0)
    {
        flavour = PROC_FLV_PGID;
        selector = proc_getpgid(sys_proc_snapshot_);
    }
    else if(u_pid < -1)
    {
        flavour = PROC_FLV_PGID;
        selector = (pid_t)(-(int64_t)u_pid);
    }
    else
    {
        flavour = PROC_FLV_ALL;
    }
    
    kinfo_proc_t *kp = NULL;
    size_t len = 0;
    kern_return_t kr = proc_list(sys_proc_snapshot_, &kp, &len, flavour, selector);
    if(kr != KERN_SUCCESS)
    {
        sys_return_failure_with_errno(ENOMEM);
    }
    
    bool any = false;
    size_t count = len / sizeof(kinfo_proc_t);
    
    for(size_t i = 0; i < count; i++)
    {
        ksurface_proc_t *target = NULL;
        if(proc_for_pid(kp[i].kp_proc.p_pid, &target) != KERN_SUCCESS)
        {
            continue;
        }
        
        if(kill_one_target(sys_proc_snapshot_, target, u_signal))
        {
            any = true;
        }
        
        kvo_release(target);
    }
    
    free(kp);
    if(!any)
    {
        sys_return_failure_with_errno(ESRCH);
    }
    
    sys_return;
}
