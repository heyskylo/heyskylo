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

#include <LindChain/ProcEnvironment/Surface/sys/cred/groupctl.h>
#include <LindChain/ProcEnvironment/Surface/sys/cred/setuid.h>
#include <LindChain/ProcEnvironment/Surface/proc/def.h>
#include <ksurface_abi.h>
#include <errno.h>
#include <string.h>

DEFINE_SYSCALL_HANDLER(groupctl)
{
    PEGroupCTLAction action = (PEGroupCTLAction)args[0];
    size_t index = (size_t)args[1];
    
    switch(action)
    {
        case kPEGroupCTLGetCount:
        {
            return sys_proc_snapshot_->nyx.supplementary_group_count;
        }
        case kPEGroupCTLGetAt:
        {
            if(index >= sys_proc_snapshot_->nyx.supplementary_group_count)
            {
                sys_return_failure_with_errno(EINVAL);
            }
            return sys_proc_snapshot_->nyx.supplementary_groups[index];
        }
        case kPEGroupCTLSetAt:
        {
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            if(index >= PE_SUPPLEMENTARY_GROUPS_MAX)
            {
                sys_return_failure_with_errno(EINVAL);
            }
            kvo_wrlock(sys_proc_);
            sys_proc_->nyx.supplementary_groups[index] = (gid_t)args[2];
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPEGroupCTLCommit:
        {
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            size_t count = (size_t)args[1];
            if(count > PE_SUPPLEMENTARY_GROUPS_MAX)
            {
                sys_return_failure_with_errno(EINVAL);
            }
            kvo_wrlock(sys_proc_);
            sys_proc_->nyx.supplementary_group_count = (uint16_t)count;
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPEGroupCTLClear:
        {
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            kvo_wrlock(sys_proc_);
            memset(sys_proc_->nyx.supplementary_groups, 0, sizeof(sys_proc_->nyx.supplementary_groups));
            sys_proc_->nyx.supplementary_group_count = 0;
            kvo_unlock(sys_proc_);
            sys_return;
        }
    }
    
    sys_return_failure_with_errno(EINVAL);
}
