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

#ifndef NXRISH_H
#define NXRISH_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Thin Objective-C wrapper over the rish C ABI (rom/include/rish.h).
 *
 * rish is the pure-Rust, JIT-less x86-64 interpreter: it boots a real Linux
 * kernel (kernel_path/initrd_path are plain host file paths) and every guest
 * instruction is decoded and interpreted — nothing runs natively, so this is
 * one hundred percent JIT-less.
 *
 * Both boot and exec BLOCK on the interpreter thread. Always call them from a
 * background queue and marshal results back to the main thread yourself.
 */
@interface NXRish : NSObject

/** The `rish_protocol_version()` reported by the linked library. */
@property (nonatomic, readonly) uint32_t protocolVersion;

/**
 * Boots an interactive Linux guest and returns a session (or nil on failure).
 * Blocks until the guest has booted and the guest agent has handed the kernel
 * over. Call from a worker thread.
 *
 * @param kernelPath      absolute path to an x86-64 bzImage
 * @param initramfsPath   absolute path to a newc initramfs with the guest agent
 * @param memoryMiB       guest RAM in MiB
 * @param commandLine     Linux kernel command line
 */
- (nullable instancetype)initWithKernelPath:(NSString *)kernelPath
                              initramfsPath:(NSString *)initramfsPath
                                   memoryMiB:(NSUInteger)memoryMiB
                                commandLine:(NSString *)commandLine;

/**
 * Runs one argv in the live guest and returns its output. Blocks. Call from a
 * worker thread. `ok` in the reply is separate from the command exit code: a
 * command that fails still returns YES here with a non-zero exitCode; VM-level
 * failures (boot lost, timeout, output cap) return NO.
 */
- (BOOL)runCommandWithArguments:(NSArray<NSString *> *)arguments
                            cwd:(nullable NSString *)cwd
                      timeoutMS:(NSUInteger)timeoutMS
                         stdout:(NSString * _Nullable * _Nullable)outStdout
                         stderr:(NSString * _Nullable * _Nullable)outStderr
                       exitCode:(int * _Nullable)outExitCode
                          error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* NXRISH_H */