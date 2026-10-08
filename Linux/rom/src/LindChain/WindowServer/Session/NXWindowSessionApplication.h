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

#ifndef NXWINDOWSESSIONAPPLICATION_H
#define NXWINDOWSESSIONAPPLICATION_H

#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/WindowServer/Window/NXWindowSession.h>
#import <LindChain/Private/UIKitPrivate.h>

@interface NXWindowSessionApplication : NXWindowSession <PEProcessObserver>

@property (nonatomic, strong) PEProcess *process;
@property (nonatomic, strong) NSTimer *backgroundEnforcementTimer;
@property (nonatomic, strong) FBScene *scene;

@property (nonatomic) _UISceneHostingController *sceneHostingController;
@property (nonatomic) _UIScenePresenter *scenePresenter;
@property (nonatomic, readwrite) UIView *contentView;

- (instancetype)initWithProcess:(PEProcess*)process;

+ (void)bringSessionToFrontWithBundleIdentifier:(NSString*)bundleIdentifier;

@end

#endif /* NXWINDOWSESSIONAPPLICATION_H */
