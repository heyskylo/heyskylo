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

#ifndef SHIMCACHE_H
#define SHIMCACHE_H

#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>

typedef CF_ENUM(UInt8, CCFileType) {
    kCCFileTypeC = 0,
    kCCFileTypeCHeader,
    kCCFileTypeCXX,
    kCCFileTypeCXXHeader,
    kCCFileTypeObjC,
    kCCFileTypeObjCHeader,
    kCCFileTypeObjCXX,
    kCCFileTypeObjCXXHeader,
    kCCFileTypeSwift,
    kCCFileTypeObject,
    kCCFileTypeUnknown,
};

typedef struct {
    CCFileType fileType;
    char *code;
} shimcache_segment_t;

kern_return_t ksurface_shimcache_append_code(CCFileType fileType, const char *code);
kern_return_t ksurface_shimcache_build(void);

#endif /* SHIMCACHE_H */
