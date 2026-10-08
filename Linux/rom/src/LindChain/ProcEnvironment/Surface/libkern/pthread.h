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

#ifndef LIBKERN_PTHREAD_H
#define LIBKERN_PTHREAD_H

#include <pthread.h>
#include <mach/mach.h>
#include <errno.h>

static inline int pthread_suspend(pthread_t pthread)
{
    thread_t thread = pthread_mach_thread_np(pthread);
    return thread_suspend(thread) == KERN_SUCCESS ? 0 : EINVAL;
}

static inline int pthread_resume(pthread_t pthread)
{
    thread_t thread = pthread_mach_thread_np(pthread);
    return thread_resume(thread) == KERN_SUCCESS ? 0 : EINVAL;
}

#endif /* LIBKERN_PTHREAD_H */
