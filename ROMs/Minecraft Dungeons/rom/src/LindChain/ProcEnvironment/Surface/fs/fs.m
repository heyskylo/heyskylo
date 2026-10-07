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
#include <CoreFoundation/CoreFoundation.h>
#include <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#include <LindChain/ProcEnvironment/Surface/fs/fs.h>
#include <LindChain/ProcEnvironment/Surface/fs/mount.h>
#include <LindChain/ProcEnvironment/Surface/fs/preserver.h>
#include <LindChain/ProcEnvironment/Surface/trust/signing.h>
#include <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Surface/libkern/kxld/kxopen.h>
#import <LindChain/ProcEnvironment/Surface/libkern/kpanic.h>
#include <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#import <LindChain/ProcEnvironment/KextLoader/PEKext.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <dlfcn.h>

NSString *kextFSRoot = nil;

static NSString *NXROMApplicationSourcePath(void)
{
    Dl_info info = {0};
    if(dladdr((const void *)&ksurface_fs_init, &info) == 0 || info.dli_fname == NULL)
    {
        return nil;
    }
    NSString *mainPath = [NSString stringWithUTF8String:info.dli_fname];
    if(mainPath.length == 0)
    {
        return nil;
    }
    return [[[mainPath stringByDeletingLastPathComponent]
             stringByAppendingPathComponent:@"Application"] stringByStandardizingPath];
}

kern_return_t ksurface_fs_init(void)
{
    const char *home = getenv("HOME");
    if(!home)
    {
        klog_log("ksurface:fs", "HOME unset");
        return KERN_FAILURE;
    }
    
    klog_log("ksurface:fs", "initializing mntfs");
    klog_log("ksurface:fs", "preparing userspace mounts");
    
    kextFSRoot = [NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home];
    
    kern_return_t kr = ksurface_fs_sandbox_init();
    if(kr != KERN_SUCCESS)
    {
        kpanic("failed to initialize fs sandbox");
    }

    NSString *romApplicationSource = NXROMApplicationSourcePath();
    NSString *rootApplicationMount = [NSString stringWithFormat:@"%s/Documents/rootfs/Application", home];
    if(romApplicationSource.length == 0 ||
       ![[NSFileManager defaultManager] fileExistsAtPath:romApplicationSource])
    {
        klog_log("ksurface:fs", "ROM Application source missing: %s",
                 romApplicationSource ? romApplicationSource.fileSystemRepresentation : "(null)");
        return KERN_NOT_FOUND;
    }

    /* The bind mount is read-only. Register the physical source as a read-only
     * sandbox backing region as well, because realpath() canonicalizes the
     * logical rootfs mount to Slot/A/Application before token issuance. */
    kr = ksurface_fs_sandbox_registry_add(kFSMountPermissionRead,
                                          kFSNodeTypeDirectory,
                                          romApplicationSource.fileSystemRepresentation,
                                          NULL);
    if(kr != KERN_SUCCESS)
    {
        klog_log("ksurface:fs", "failed to register ROM Application source sandbox region");
        return kr;
    }
    
    typedef struct {
        FSMountAttr permissionFlags;
        __strong NSString *device_dir;
        __strong NSString *mount_dir;
    } FSMountInitRegistry;
    
    /* something like fstab x3 */
    FSMountInitRegistry fstab[] = {
        /* virtual file systems */
        {
            kFSMountAttrNone,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs", home]
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrClear,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/devfs", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrClear,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs", home],
        },
        {
            kFSMountAttrRead,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,   /* write will later be allowed through entitlement org.emexlabs.nyxian.launch-services.toggle */
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/lsfs", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,   /* write will later be allowed through entitlement org.emexlabs.nyxian.storage.etc.allow */
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/etcfs", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrClear,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/libexec", home],
        },
        
        /* bind mounts */
        {
            kFSMountAttrRead,
            [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"/Frameworks/bootstrapd.dylib"].path,
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/libexec/bootstrapd", home],
        },
        {
            kFSMountAttrRead,
            [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"/Frameworks/MobileDevelopmentService.dylib"].path,
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/libexec/MobileDevelopmentService", home],
        },
        {
            kFSMountAttrRead,
            NSBundle.mainBundle.bundlePath,
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/bootloader", home],
        },
        {
            kFSMountAttrRead,
            [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/Shared/kernel"],
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/headers", home],
        },
        {
            kFSMountAttrRead,
            [NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home],
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/kexts", home],
        },
        {
            kFSMountAttrRead,
            [NSString stringWithFormat:@"%s/Documents/mntfs/devfs", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/dev", home],
        },
        {
            kFSMountAttrRead,
            [NSString stringWithFormat:@"%s/Documents/mntfs/bootfs", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/boot", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            [NSString stringWithFormat:@"%s/Documents/mntfs/lsfs", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/System/Library/LaunchDaemons", home],
        },
        {
            kFSMountAttrRead,
            [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/Shared/LaunchServices/org.emexlabs.bootstrapd.plist"],
            [NSString stringWithFormat:@"%s/Documents/mntfs/lsfs/org.emexlabs.bootstrapd.plist", home],
        },
        {
            kFSMountAttrRead,
            [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/Shared/LaunchServices/org.emexlabs.compilerd.plist"],
            [NSString stringWithFormat:@"%s/Documents/mntfs/lsfs/org.emexlabs.compilerd.plist", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            [NSString stringWithFormat:@"%s/Documents/mntfs/etcfs", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/etc", home],
        },
        
        /* ROM guest applications: immutable payload mounted into rootfs. */
        {
            kFSMountAttrRead,
            romApplicationSource,
            rootApplicationMount,
        },
        
        /* root mounts */
        {
            kFSMountAttrRead | kFSMountAttrWrite | kFSMountAttrClear,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/tmp", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/var/containers", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/var/mobile/Containers", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/var/mobile/tmp", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite | kFSMountAttrClear,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/var/root", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/bin", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/sbin", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/lib", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            @"/dev/nounlink",
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/include", home],
        },
        
        /* root bind mounts */
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/bin", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/bin", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/sbin", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/sbin", home],
        },
        {
            kFSMountAttrRead | kFSMountAttrWrite,
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/lib", home],
            [NSString stringWithFormat:@"%s/Documents/rootfs/lib", home],
        },
        {
            kFSMountAttrRead,
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"libexec"],
            [NSString stringWithFormat:@"%s/Documents/rootfs/usr/libexec", home],
        },
    };
    
    for(int i = 0; i < sizeof(fstab) / sizeof(FSMountInitRegistry); i++)
    {
        kr = ksurface_fs_mount2(fstab[i].permissionFlags, fstab[i].device_dir.fileSystemRepresentation, fstab[i].mount_dir.fileSystemRepresentation);
        if(kr != KERN_SUCCESS)
        {
            klog_log("ksurface:fs", "failed to create %s userspace mount", fstab[i].mount_dir);
            return KERN_FAILURE;
        }
    }
    
    klog_log("ksurface:fs", "starting mount preserver");
    kr = ksurface_fs_preserver_kickstart();
    if(kr != KERN_SUCCESS)
    {
        kpanic("failed to start mount preserver");
        return kr;
    }
    
    return KERN_SUCCESS;
}

kern_return_t ksurface_fs_install_kext_at_path(const char *path)
{
    if(path == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    NSString *nsPath = [NSString stringWithCString:path encoding:NSUTF8StringEncoding];
    if(nsPath == nil)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /* gather bundle and executable */
    NSBundle *bundle = [NSBundle bundleWithPath:nsPath];
    if(bundle == nil)
    {
        return KERN_DENIED;
    }
    
    NSString *executable = bundle.executablePath;
    if(executable == nil)
    {
        return KERN_DENIED;
    }
    
    /* validate apple signature */
    LCMachO *machO = LCMapMachO(executable.UTF8String, true);
    if(machO == NULL)
    {
        return KERN_DENIED;
    }
    
    bool isAppleSigned = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!isAppleSigned)
    {
        return KERN_DENIED;
    }
    
    /* validate kext's nxt2 blob */
    ksurface_nxt2_t result = {};
    kern_return_t kr = trust_nxt2_read(executable.UTF8String, &result);
    if(kr != KERN_SUCCESS ||
       !result.isValid ||
       !result.isSigned ||
       !result.isCdHashValid)
    {
        if(result.entitlements != nil)
        {
            CFRelease(result.entitlements);
        }
        return KERN_DENIED;
    }
    
    /* check entitlements */
    bool hasEntitlement = CFDictionaryGetValue(result.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) == kCFBooleanTrue;
    CFRelease(result.entitlements);
    if(!hasEntitlement)
    {
        return KERN_DENIED;
    }
    
    /* ready to go, we trust that thing */
    NSString *kextPath = [kextFSRoot stringByAppendingFormat:@"/%@.kext", bundle.bundleIdentifier];
    [[NSFileManager defaultManager] removeItemAtPath:kextPath error:nil];
    if(![[NSFileManager defaultManager] copyItemAtPath:nsPath toPath:kextPath error:nil])
    {
        return KERN_FAILURE;
    }
    
    return KERN_SUCCESS;
}
