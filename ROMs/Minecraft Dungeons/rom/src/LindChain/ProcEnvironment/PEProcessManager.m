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

#import <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#import <LindChain/ProcEnvironment/Surface/libkern/kpanic.h>
#import <LindChain/ProcEnvironment/Surface/proc/proc.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>
#import <LindChain/Services/bootstrapd/LDEApplicationWorkspace.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <os/lock.h>

@implementation PEProcessManager {
    NSMutableDictionary<NSNumber*,PEProcess*> *_processes;
    os_unfair_lock _lock;
}

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        _processes = [[NSMutableDictionary alloc] init];
        if(_processes == nil)
        {
            return nil;
        }
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

+ (instancetype)shared
{
    static PEProcessManager *processManagerSingletone = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        processManagerSingletone = [[PEProcessManager alloc] init];
    });
    return processManagerSingletone;
}

- (pid_t)spawnProcessWithItems:(NSDictionary*)items
      withKernelSurfaceProcess:(ksurface_proc_t*)proc
{    
    /* creating a process */
    PEProcess *process = [[PEProcess alloc] initWithItems:items withKernelSurfaceProcess:proc ?: kernel_proc_];
    if(process == nil)
    {
        return -1;
    }
    
    /* getting process identifier */
    pid_t pid = process.pid;
    if(pid < 0)
    {
        return -1;
    }
    
    /* inserting process */
    [process addObserver:self];
    os_unfair_lock_lock(&_lock);
    [_processes setObject:process forKey:@(pid)];
    os_unfair_lock_unlock(&_lock);
    
    /* returning pid */
    return pid;
}

- (pid_t)spawnProcessWithBundleIdentifier:(NSString *)bundleIdentifier
                                withItems:(NSDictionary*)items
                 withKernelSurfaceProcess:(ksurface_proc_t*)proc
                       doRestartIfRunning:(BOOL)doRestartIfRunning
{
    PEProcess *existingProcess = [self processForBundleIdentifier:bundleIdentifier];
    if(existingProcess != nil)
    {
        NXWindowSession *windowSession = [[NXWindowServer shared] windowSessionForBundleIdentifier:existingProcess.bundleIdentifier];
        if(windowSession != nil && windowSession.window != nil && !doRestartIfRunning)
        {
            
            if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone)
            {
                [[NXWindowServer shared] activateWindowForIdentifier:windowSession.windowIdentifier animated:true withCompletion:nil];
            }
            else
            {
                [windowSession.window focusWindow];
            }
            return existingProcess.pid;
        }
        else
        {
            [existingProcess forceTerminate];
        }
    }
    
    LDEApplicationObject *applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForBundleID:bundleIdentifier];
    if(applicationObject == nil)
    {
        errno = EAGAIN;
        return -1;
    }
    
    /* creating process */
    NSMutableDictionary *mutableItems = [items mutableCopy];
    
    [mutableItems setValuesForKeysWithDictionary:@{
        @"PEExecutablePath": applicationObject.executablePath,
        @"PEArguments": @[
            applicationObject.executablePath
        ],
        @"PEEnvironment": @{
            @"HOME": applicationObject.containerPath,
            @"CFFIXED_USER_HOME": applicationObject.containerPath,
            @"TMPDIR": [applicationObject.containerPath stringByAppendingPathComponent:@"/Tmp"]
        },
        @"PEWorkingDirectory": [applicationObject.containerPath stringByAppendingPathComponent:@"/Documents"],
    }];
    
    PEProcess *process = [[PEProcess alloc] initWithItems:mutableItems withKernelSurfaceProcess:proc ?: kernel_proc_];
    if(process == nil)
    {
        return -1;
    }
    
    /* getting pid of process */
    pid_t pid = process.pid;
    if(pid < 0)
    {
        return -1;
    }
    
    /* setting process */
    [process addObserver:self];
    os_unfair_lock_lock(&_lock);
    [_processes setObject:process forKey:@(pid)];
    os_unfair_lock_unlock(&_lock);

    return pid;
}

- (PEProcess*)processForProcessIdentifier:(pid_t)pid
{
    PEProcess *process = nil;
    os_unfair_lock_lock(&_lock);
    process = [_processes objectForKey:@(pid)];
    os_unfair_lock_unlock(&_lock);
    return process;
}

- (PEProcess*)processForBundleIdentifier:(NSString*)bundleIdentifier
{
    os_unfair_lock_lock(&_lock);
    for(PEProcess *process in _processes.allValues)
    {
        if(process && [process.bundleIdentifier isEqualToString:bundleIdentifier])
        {
            os_unfair_lock_unlock(&_lock);
            return process;
        }
    }
    os_unfair_lock_unlock(&_lock);
    return nil;
}

- (void)process:(PEProcess *)process didExitWithWait4Code:(int)code
{
    [process removeObserver:self];
    os_unfair_lock_lock(&_lock);
    [_processes removeObjectForKey:@(process.pid)];
    os_unfair_lock_unlock(&_lock);
}

- (void)closeIfRunningUsingBundleIdentifier:(NSString*)bundleIdentifier
{
    PEProcess *process = [self processForBundleIdentifier:bundleIdentifier];
    if(process)
    {
        [process forceTerminate];
    }
}

- (void)killAllRunningProcesses;
{
    os_unfair_lock_lock(&_lock);
    for(PEProcess *process in _processes.allValues)
    {
        [process sendSignal:SIGKILL];
    }
    os_unfair_lock_unlock(&_lock);
}

@end
