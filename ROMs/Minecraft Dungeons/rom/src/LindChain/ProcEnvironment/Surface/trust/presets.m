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

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/Surface/libkern/kpanic.h>
#import <LindChain/ProcEnvironment/Surface/trust/presets.h>

CFDictionaryRef kPEEntitlementsNXT2PresetsKernel;
CFDictionaryRef kPEEntitlementsNXT2PresetsDaemonBootstrap;
CFDictionaryRef kPEEntitlementsNXT2PresetsDaemonCompiler;

__attribute__((constructor))
static void TrustPresetsInit(void)
{
    kPEEntitlementsNXT2PresetsKernel = (__bridge_retained CFDictionaryRef)@{
        /* platformization */
        (__bridge NSString*)kNXT2EntitlementPlatform: @(YES),   /* needed so trust layer allows creation of other platform identities */
        
        /* debugging */
        (__bridge NSString*)kNXT2EntitlementGetTaskAllow: @(NO),
    };
    
    kPEEntitlementsNXT2PresetsDaemonBootstrap = (__bridge_retained CFDictionaryRef)@{
        /* platformization */
        (__bridge NSString*)kNXT2EntitlementPlatform: @(YES),
        (__bridge NSString*)kNXT2EntitlementPlatformRoot: @(YES),
        
        /* debugging */
        (__bridge NSString*)kNXT2EntitlementGetTaskAllow: @(NO),
        
        /* management */
        (__bridge NSString*)kNXT2EntitlementManagementProcEnvironment: @(YES),  /* needed to open apps for other processes that issue a request */
        
        /* launch services */
        (__bridge NSString*)kNXT2EntitlementLaunchServicesSetEndpointAllowList: @[
            @"org.emexlabs.bootstrapd",
        ],
        
        /* sandbox */
        (__bridge NSString*)kNXT2EntitlementSandboxFileRead: @[
            @"$(NXROOT)/Application",           /* read only ROM application payloads */
        ],
        (__bridge NSString*)kNXT2EntitlementSandboxFileReadWrite: @[
            @"$(NXROOT)/usr/bin",               /* needs access to fastpath binaries */
            @"$(NXROOT)/var/containers",        /* needs access to application bundles */
            @"$(NXROOT)/var/mobile/Containers", /* needs access to application data containers */
            @"$(NXROOT)/var/mobile/tmp",        /* needs access to tmp of root home */
        ],
    };
    
    kPEEntitlementsNXT2PresetsDaemonCompiler = (__bridge_retained CFDictionaryRef)@{
        /* platformization */
        (__bridge NSString*)kNXT2EntitlementPlatform: @(YES),
        (__bridge NSString*)kNXT2EntitlementPlatformRoot: @(YES),
        
        /* debugging */
        (__bridge NSString*)kNXT2EntitlementGetTaskAllow: @(NO),
        
        /* launch services */
        (__bridge NSString*)kNXT2EntitlementLaunchServicesSetEndpoint: @(YES),  /* needed so it can set the unique service */
        
        /* sandbox */
        (__bridge NSString*)kNXT2EntitlementSandboxHost: @(YES),                /* allows file access to all of Nyxian, EXTREMELY POWERFUL */
    };
}
