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

#ifndef PELAUNCHSERVICE_H
#define PELAUNCHSERVICE_H

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/PEProcess.h>
#import <LindChain/ProcEnvironment/PELaunchServiceInstance.h>

@interface PELaunchService : NSObject <PELaunchServiceInstanceDelegate>

@property (atomic,readonly,copy) NSMutableArray<PELaunchServiceInstance*> *instances;
@property (nonatomic,readonly) NSString *executablePath;
@property (nonatomic,readonly) NSString *serviceIdentifier;
@property (nonatomic,readonly) BOOL autoRestart;
@property (nonatomic,readonly) BOOL enabled;
@property (nonatomic,readonly) BOOL isMultiInstanceDaemon;

+ (instancetype)launchServiceWithPlistPath:(NSString*)plistPath;
- (instancetype)initWithPlistPath:(NSString*)plistPath;
- (BOOL)isServiceWithServiceIdentifier:(NSString*)serviceIdentifier;

- (PELaunchServiceInstance*)newInstance;

@end

#endif /* PELAUNCHSERVICE_H */
