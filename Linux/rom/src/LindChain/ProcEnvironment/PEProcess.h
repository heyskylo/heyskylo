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

#ifndef PRPROCESS_H
#define PRPROCESS_H

#import <Foundation/Foundation.h>
#import <LindChain/Private/FoundationPrivate.h>
#import <LindChain/Private/UIKitPrivate.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/PEFileTable.h>
#import <LindChain/ProcEnvironment/PEProcessObserver.h>
#import <LindChain/ProcEnvironment/Surface/proc/proc.h>
#import <LindChain/Services/bootstrapd/LDEApplicationWorkspace.h>

@interface PEProcess : NSObject <FBProcessObserver>

@property (nonatomic) ksurface_proc_t *proc;

@property (nonatomic,strong) FBProcess *process;
@property (nonatomic,strong) UIImage *snapshot;

@property (nonatomic,strong) LDEApplicationObject *applicationObject;
@property (nonatomic,strong) NSString *bundleIdentifier;
@property (nonatomic,strong) NSString *displayName;
@property (nonatomic,strong) NSString *executablePath;

@property (nonatomic,readonly) pid_t pid;
@property (nonatomic,readonly) int pidv;

- (instancetype)initWithItems:(NSDictionary*)items withKernelSurfaceProcess:(ksurface_proc_t*)proc;

- (void)sendSignal:(int)signal;

- (void)forceTerminate;
- (void)terminate;
- (void)suspend;
- (void)resume;

- (void)addObserver:(id<PEProcessObserver>)observer;
- (void)removeObserver:(id<PEProcessObserver>)observer;

@end

#endif /* PRPROCESS_H */
