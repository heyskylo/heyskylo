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

/* I definetly trust apple OwO */
#ifndef TRUST_APPLE_H
#define TRUST_APPLE_H

/* ----------------------------------------------------------------------
 *  System Headers
 * -------------------------------------------------------------------- */
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/trust/entitlement.h>

/* ----------------------------------------------------------------------
 *  Function Prototypes
 * -------------------------------------------------------------------- */
CFDictionaryRef CopyAppleCSEntitlementsForPath(CFStringRef path, OSStatus *outErr);
CFDictionaryRef ExtractNXT2OutOfAppleCSEntitlements(CFDictionaryRef appleCSEntitlements);

kern_return_t CDHashMatchesCodeDirectory(const uint8_t *base, size_t size, const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN]);
kern_return_t CDHashMatchesCodeDirectoryFD(int fd, const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN]);
kern_return_t CDHashMatchesCodeDirectoryOfPath(const char *path, const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN]);

#endif /* TRUST_APPLE_H */
