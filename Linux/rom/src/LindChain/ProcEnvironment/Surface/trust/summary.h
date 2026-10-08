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

#ifndef TRUST_SUMMARY_H
#define TRUST_SUMMARY_H

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/Surface/trust/entitlement.h>

typedef NS_ENUM(NSUInteger, KSNXT2Section) {
    KSNXT2SectionIdentity = 0,
    KSNXT2SectionProcesses,
    KSNXT2SectionDebugging,
    KSNXT2SectionFilesystem,
    KSNXT2SectionServices,
    KSNXT2SectionManagement,
    KSNXT2SectionStealth,
    KSNXT2SectionTrust,
    KSNXT2SectionUnrecognized,
    KSNXT2SectionCount
};

static NSString *const kKSNXT2SectionTitles[KSNXT2SectionCount] = {
    @"Identity",
    @"Processes",
    @"Debugging",
    @"Filesystem",
    @"Services",
    @"System Management",
    @"Stealth",
    @"Trust",
    @"Unrecognized Entitlements",
};

typedef NS_ENUM(NSUInteger, KSNXT2Severity) {
    KSNXT2SeverityInfo = 0,
    KSNXT2SeverityNote,
    KSNXT2SeverityWarn,
    KSNXT2SeverityCrit,
};

typedef NS_ENUM(NSUInteger, KSNXT2ValueKind) {
    KSNXT2ValueBool = 0,
    KSNXT2ValueString,
    KSNXT2ValueInteger,
    KSNXT2ValueStringArray,
    KSNXT2ValuePathArray,
};

typedef struct {
    CFStringRef         identifier;
    KSNXT2Section       section;
    KSNXT2ValueKind     kind;
    KSNXT2Severity      severity;
    BOOL                restrictive;
    CFStringRef         summary;
} KSNXT2Descriptor;

typedef struct {
    BOOL            active;
    CFStringRef     required[4];
} KSNXT2RuleSet;

typedef struct {
    KSNXT2RuleSet   set[4];
    KSNXT2Section   section;
    KSNXT2Severity  severity;
    CFStringRef     summary;
} KSNXT2Rule;

NSAttributedString *KSurfaceNXT2CreateEntitlementSummary(NSDictionary *entitlements);

#endif /* TRUST_SUMMARY_H */
