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
#import <LindChain/ProcEnvironment/PEProcess.h>

typedef NS_ENUM(NSUInteger, PELaunchServiceInstanceState) {
    PELaunchServiceInstanceStateIdle =      0,
    PELaunchServiceInstanceStateLaunching,
    PELaunchServiceInstanceStateRunning,
    PELaunchServiceInstanceStateExited,
    PELaunchServiceInstanceStateTerminated
};

@class PELaunchServiceInstance;

@protocol PELaunchServiceInstanceDelegate <NSObject>

- (void)instanceDidExit:(PELaunchServiceInstance *)instance withWaitCode:(int)code;

@end

@interface PELaunchServiceInstance : NSObject <PEProcessObserver>

@property (nonatomic, readonly) NSDictionary *items;
@property (nonatomic, readonly) NSString *uniqueBootstrapRegistryIdentifier;
@property (nonatomic, readonly) PEProcess *process;
@property (nonatomic, readonly) pid_t processIdentifier;
@property (nonatomic, readonly) PELaunchServiceInstanceState state;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, weak) id<PELaunchServiceInstanceDelegate> delegate;

- (instancetype)initWithItems:(NSDictionary *)items;
- (BOOL)launch;
- (void)terminate;

- (mach_port_name_t)getEndpoint;
- (NSXPCListenerEndpoint*)xpcEndpoint;

@end
