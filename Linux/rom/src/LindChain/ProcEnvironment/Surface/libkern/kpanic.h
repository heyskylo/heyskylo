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

#ifndef LIBKERN_KPANIC_H
#define LIBKERN_KPANIC_H

#include <stdint.h>

#define KPANIC_BUF_SIZE (16 * 1024)

struct ksurface_panic_header {
    uint32_t magic;
    uint32_t version;
    uint32_t len;
    uint32_t _pad;
    char body[KPANIC_BUF_SIZE];
};

void kpanic_append(const char *fmt, ...) __printflike(1, 2);

__attribute__((noreturn))
void kpanic(const char *fmt, ...) __printflike(1, 2);

const struct ksurface_panic_header *kpanic_log_get(void);

#endif /* LIBKERN_KPANIC_H */
