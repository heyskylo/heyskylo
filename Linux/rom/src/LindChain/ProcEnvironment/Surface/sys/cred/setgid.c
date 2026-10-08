/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab
 Copyright (C) 2026 semvis123

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

#include <LindChain/ProcEnvironment/Surface/sys/cred/setgid.h>
#include <LindChain/ProcEnvironment/Surface/sys/cred/setuid.h>
#include <LindChain/ProcEnvironment/Surface/trust/entitlement.h>
#include <LindChain/ProcEnvironment/Surface/proc/proc.h>

DEFINE_SYSCALL_HANDLER(setgid)
{
    /* getting arguments */
    gid_t u_gid = (gid_t)args[0];
    
    kvo_wrlock(sys_proc_);
    ksurface_proc_ucred_backup_t ucred_backup = proc_make_ucred_backup(sys_proc_);
    
    /* checking privelege */
    if(proc_is_privileged(sys_proc_))
    {
        /* updating credentials */
        proc_setrgid(sys_proc_, u_gid);
        proc_setegid(sys_proc_, u_gid);
        proc_setsvgid(sys_proc_, u_gid);
        
        /* update and return */
        goto out_update;
    }
    else
    {
        if(u_gid == proc_getrgid(sys_proc_) ||
           u_gid == proc_getsvgid(sys_proc_))
        {
            /* updating credentials */
            proc_setegid(sys_proc_, u_gid);
            
            /* update and return */
            goto out_update;
        }
    }
    
    /* setting errno on failure */
    kvo_unlock(sys_proc_);
    sys_return_failure_with_errno(EPERM);
    
out_update:
    proc_set_sugid_if_applicable(sys_proc_, ucred_backup);
    kvo_unlock(sys_proc_);
    sys_return;
}

DEFINE_SYSCALL_HANDLER(setegid)
{
    /* getting arguments */
    gid_t u_egid = (gid_t)args[0];
    
    kvo_wrlock(sys_proc_);
    ksurface_proc_ucred_backup_t ucred_backup = proc_make_ucred_backup(sys_proc_);
    
    /* checking privelege */
    if(proc_is_privileged(sys_proc_))
    {
        /* updating credentials */
        proc_setegid(sys_proc_, u_egid);
        
        /* update and return */
        goto out_update;
    }
    else
    {
        if(u_egid == proc_getrgid(sys_proc_) ||
           u_egid == proc_getegid(sys_proc_) ||
           u_egid == proc_getsvgid(sys_proc_))
        {
            /* updating credentials */
            proc_setegid(sys_proc_, u_egid);
            
            /* update and return */
            goto out_update;
        }
    }
    
    /* setting errno on failure */
    kvo_unlock(sys_proc_);
    sys_return_failure_with_errno(EPERM);
    
out_update:
    proc_set_sugid_if_applicable(sys_proc_, ucred_backup);
    kvo_unlock(sys_proc_);
    sys_return;
}

DEFINE_SYSCALL_HANDLER(setregid)
{
    kvo_wrlock(sys_proc_);
    ksurface_proc_ucred_backup_t ucred_backup = proc_make_ucred_backup(sys_proc_);
    
    /* getting arguments */
    gid_t u_rgid = (gid_t)args[0];
    gid_t u_egid = (gid_t)args[1];
    
    /* getting privele status of the process */
    bool privileged = proc_is_privileged(sys_proc_);
    
    /* performing rgid priv check */
    if(u_rgid != (gid_t)-1 &&
       !privileged)
    {
        if(u_rgid != ucred_backup.rgid &&
           u_rgid != ucred_backup.egid)
        {
            kvo_unlock(sys_proc_);
            sys_return_failure_with_errno(EPERM);
        }
    }
    
    /* performing egid priv check */
    if(u_egid != (gid_t)-1 &&
       !privileged)
    {
        if(u_egid != ucred_backup.rgid &&
           u_egid != ucred_backup.egid && u_egid != ucred_backup.svgid)
        {
            kvo_unlock(sys_proc_);
            sys_return_failure_with_errno(EPERM);
        }
    }
    
    /* setting credential */
    if(u_rgid != (gid_t)-1)
    {
        proc_setrgid(sys_proc_, u_rgid);
    }
    
    /* setting credential */
    if(u_egid != (gid_t)-1)
    {
        proc_setegid(sys_proc_, u_egid);
        if(privileged)
        {
            proc_setsvgid(sys_proc_, u_egid);
        }
    }
    
    proc_set_sugid_if_applicable(sys_proc_, ucred_backup);
    kvo_unlock(sys_proc_);
    sys_return;
}
