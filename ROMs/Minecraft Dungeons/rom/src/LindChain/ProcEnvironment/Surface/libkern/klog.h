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

#ifndef LIBKERN_KLOG_H
#define LIBKERN_KLOG_H

#if __OBJC__
#import <Foundation/Foundation.h>
#endif /* __OBJC__ */
#include <stdbool.h>

extern struct timespec g_process_start_time;
extern struct timespec g_process_start_time_sysctl;;

#if HOST_ENV

#define klog_log(system, format, ...) \
    klog_log_internal((system), (format), ##__VA_ARGS__)

#else

#define klog_log(system, format, ...)

#endif

bool klog_set_obfuscation(bool enabled);

void klog_log_internal(const char *system, const char *format, ...);

#if __OBJC__
NSString *klog_dump(void);
#endif /* __OBJC__ */

#endif /* LIBKERN_KLOG_H */
