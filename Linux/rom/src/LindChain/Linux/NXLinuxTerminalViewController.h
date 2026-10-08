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

#ifndef NXLINUXTERMINALVIEWCONTROLLER_H
#define NXLINUXTERMINALVIEWCONTROLLER_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The ROM host UI. On appear it boots a real x86-64 Linux kernel inside rish's
 * pure-Rust, JIT-less interpreter (the guest is pinned to
 * kernel/vmlinuz-virt-6.18.35 + initramfs/rish-container.cpio inside the slot)
 * and drops you into an interactive shell.
 */
@interface NXLinuxTerminalViewController : UIViewController

- (instancetype)initWithSlotURL:(NSURL *)slotURL NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif /* NXLINUXTERMINALVIEWCONTROLLER_H */