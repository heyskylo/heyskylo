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

#include <LindChain/ProcEnvironment/Surface/sys/cred/loginctl.h>
#include <LindChain/ProcEnvironment/Surface/sys/cred/setuid.h>
#include <LindChain/ProcEnvironment/Surface/proc/def.h>
#include <ksurface_abi.h>
#include <errno.h>
#include <string.h>

DEFINE_SYSCALL_HANDLER(loginctl)
{
    PELoginCTLAction action = (PELoginCTLAction)args[0];
    size_t index = (size_t)args[1];
    
    switch(action)
    {
        case kPELoginCTLGetLength:
        {
            return sys_proc_snapshot_->nyx.login_name_len;
        }
            
        case kPELoginCTLGetWord:
        {
            size_t offset = index * sizeof(uint64_t);
            if(offset >= sizeof(sys_proc_snapshot_->nyx.login_name))
            {
                sys_return_failure_with_errno(EINVAL);
            }
            uint64_t word = 0;
            if(offset < sys_proc_snapshot_->nyx.login_name_len)
            {
                size_t count = sys_proc_snapshot_->nyx.login_name_len - offset;
                if(count > sizeof(word)) count = sizeof(word);
                memcpy(&word, sys_proc_snapshot_->nyx.login_name + offset, count);
            }
            return (int64_t)word;
        }
        case kPELoginCTLSetWord:
        {
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            size_t offset = index * sizeof(uint64_t);
            if(offset >= sizeof(sys_proc_->nyx.login_name))
            {
                sys_return_failure_with_errno(EINVAL);
            }
            uint64_t word = (uint64_t)args[2];
            size_t count = sizeof(word);
            if(offset + count > sizeof(sys_proc_->nyx.login_name))
            {
                count = sizeof(sys_proc_->nyx.login_name) - offset;
            }
            kvo_wrlock(sys_proc_);
            memcpy(sys_proc_->nyx.login_name + offset, &word, count);
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPELoginCTLCommit:
        {
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            size_t len = (size_t)args[1];
            if(len >= sizeof(sys_proc_->nyx.login_name))
            {
                sys_return_failure_with_errno(EINVAL);
            }
            kvo_wrlock(sys_proc_);
            sys_proc_->nyx.login_name[len] = '\0';
            sys_proc_->nyx.login_name_len = (uint16_t)len;
            kvo_unlock(sys_proc_);
            sys_return;
        }

        case kPELoginCTLClear:
            if(!proc_is_privileged(sys_proc_))
            {
                sys_return_failure_with_errno(EPERM);
            }
            kvo_wrlock(sys_proc_);
            memset(sys_proc_->nyx.login_name, 0, sizeof(sys_proc_->nyx.login_name));
            sys_proc_->nyx.login_name_len = 0;
            kvo_unlock(sys_proc_);
            sys_return;
    }
    
    sys_return_failure_with_errno(EINVAL);
}
