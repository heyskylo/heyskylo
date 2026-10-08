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

#import <mach/mach.h>
#import <LindChain/ProcEnvironment/Server/ServerSession.h>
#import <LindChain/Services/bootstrapd/LDEApplicationWorkspace.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>
#import <LindChain/ProcEnvironment/Surface/trust/entitlement.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>
#import <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#import <LindChain/ProcEnvironment/Surface/proc/list.h>
#import <LindChain/ProcEnvironment/Surface/proc/proc.h>
#import <LindChain/ProcEnvironment/Surface/proc/permit.h>
#import <ksurface_config.h>

@interface ServerSession ()

@property (nonatomic,getter=proc) ksurface_proc_t *proc;

@end

@implementation ServerSession {
    pid_t _processIdentifier;
}

- (instancetype)initWithProcessidentifier:(pid_t)pid
{
    self = [super init];
    _processIdentifier = pid;
    return self;
}

- (ksurface_proc_t*)proc
{
    if(_proc == NULL)
    {
        /* attempting to get proc from ksurface */
        kern_return_t ret = proc_for_pid(_processIdentifier, &(_proc));
        if(ret != KERN_SUCCESS)
        {
            return NULL;
        }
    }
    
    return _proc;
}

#if KSURFACE_SYS_PROC_ENABLED

/*
 posix_spawn
 */
- (void)spawnProcessWithPath:(NSString*)path
               withArguments:(NSArray<NSObject<NSSecureCoding,NSCopying>*>*)arguments
    withEnvironmentVariables:(NSDictionary *)environment
               withFileTable:(PEFileTable*)fileTable
        withWorkingDirectory:(NSString *)workingDirectory
              withSpawnFlags:(short)spawnFlags
             withSpawnPgroup:(pid_t)spawnPgroup
                   withReply:(void (^)(int64_t))reply
{
    static dispatch_queue_t spawnQueue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        spawnQueue = dispatch_queue_create("org.emexlabs.nyxian.oldserver.spawnqueue", DISPATCH_QUEUE_SERIAL);
    });
    __weak typeof(self) weakSelf = self;
    dispatch_async(spawnQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if(strongSelf == nil)
        {
            /* sead server session */
            return;
        }
        
        /* sanity checking proc */
        if(strongSelf.proc == NULL)
        {
            reply(-1);
            return;
        }
        
        if(path &&
           arguments &&
           environment &&
           workingDirectory &&
           (entitlement_got_entitlement(proc_getentitlements(strongSelf->_proc), kPEEntitlementFlagProcessSpawn) ||
            entitlement_got_entitlement(proc_getentitlements(strongSelf->_proc), kPEEntitlementFlagProcessSpawnSignedOnly)))
        {
            NSMutableDictionary *mutableItems = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"PEExecutablePath": path,
                @"PEArguments": arguments,
                @"PEEnvironment": environment,
                @"PEWorkingDirectory": workingDirectory,
                @"PEPOSIXSpawnFlags": @(spawnFlags),
                @"PEPOSIXSpawnPgroup": @(spawnPgroup),
            }];
            
            if(fileTable != nil)
            {
                [mutableItems setObject:fileTable forKey:@"PEFileTable"];
            }
            
            /* invoking spawn */
            pid_t pid = [[PEProcessManager shared] spawnProcessWithItems:mutableItems withKernelSurfaceProcess:strongSelf->_proc];
            
            /* replying with pid of spawn */
            reply(pid);
            
            return;
        }
        
        reply(-1);
    });
}

#endif /* KSURFACE_SYS_PROC_ENABLED */

/*
 App switcher services
 */
- (void)setSnapshot:(UIImage*)image
{
    /* null pointer check */
    if(image == NULL)
    {
        return;
    }
    
    /* finding process */
    PEProcess *process = [[PEProcessManager shared] processForProcessIdentifier:_processIdentifier];
    if(process != nil)
    {
        /* setting snapshot */
        process.snapshot = image;
    }
}

- (void)dealloc
{
    /* null pointer check */
    if(_proc != NULL)
    {
        kvo_release(_proc);
    }
}

@end
