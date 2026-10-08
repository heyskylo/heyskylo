/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab
 Copyright (C) 2026 ruri1208

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

#ifndef PEUSERSPACEMANAGER_H
#define PEUSERSPACEMANAGER_H

#import <Foundation/Foundation.h>

typedef enum: UInt8 {
    kPEUserspaceRebootTypeDefault,
    kPEUserspaceRebootTypeMinimal,  /* only containerd launches */
    kPEUserspaceRebootTypeEmpty,    /* without daemons, just ksurface */
} PEUserspaceRebootType;

typedef enum: UInt8 {
    kPEUserspaceModeDefault,
    kPEUserspaceModeMinimal,
    kPEUserspaceModeEmpty,
} PEUserspaceMode;

@interface PEUserspaceManager : NSObject

@property (atomic,readonly) BOOL isBooted;
@property (atomic,readonly) BOOL isLaunchServiceManagerStable;
@property (readonly) PEUserspaceMode mode;

+ (instancetype)shared;

- (void)bootWithKextLoadingEnabled:(BOOL)enabled;
- (BOOL)rebootUserspace;
- (BOOL)restore;
- (BOOL)restoreEverything;
- (BOOL)reloadDaemons;
- (BOOL)clearApplicationCaches;

@end

#endif /* PEUSERSPACEMANAGER_H */
