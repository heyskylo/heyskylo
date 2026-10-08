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

#include <LindChain/ProcEnvironment/Surface/libkern/kpanic.h>
#include <LindChain/ProcEnvironment/Surface/proc/proctil.h>
#include <LindChain/ProcEnvironment/Surface/surface.h>
#include <stdatomic.h>
#include <os/lock.h>

static _Atomic uint32_t counter = 1;    /* kernel_proc_ is already one process */
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

kern_return_t proctil(ProctilAction action)
{
    switch(action)
    {
        case kProctilActionCount:
        {
            uint32_t cur = atomic_load_explicit(&counter, memory_order_relaxed);
            do
            {
                if(cur >= PROC_MAX)
                {
                    return KERN_POLICY_LIMIT;
                }
            }
            while(!atomic_compare_exchange_weak_explicit(&counter, &cur, cur + 1, memory_order_acq_rel, memory_order_relaxed));
            return KERN_SUCCESS;
        }
        case kProctilActionUncount:
        {
            uint32_t cur = atomic_load_explicit(&counter, memory_order_relaxed);
            do
            {
                if(cur == 0)
                {
                    kpanic("process count did underflow");
                }
            }
            while(!atomic_compare_exchange_weak_explicit(&counter, &cur, cur - 1, memory_order_release, memory_order_relaxed));
            return KERN_SUCCESS;
        }
        case kProctilActionLock:
            os_unfair_lock_lock(&lock);
            return KERN_SUCCESS;
        case kProctilActionUnlock:
            os_unfair_lock_unlock(&lock);
            return KERN_SUCCESS;
        case kProctilActionTrylock:
            return os_unfair_lock_trylock(&lock) ? KERN_SUCCESS : KERN_FAILURE;
        default:
            return KERN_INVALID_ARGUMENT;
    }
}

