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

#ifndef LDEAPPLICATIONWORKSPACESERVICE_H
#define LDEAPPLICATIONWORKSPACESERVICE_H

#import <Foundation/Foundation.h>
#if __has_include(<LiveShim/Service.h>)
#import <LiveShim/Service.h>
#import <LindChain/ProcEnvironment/PEArchiveHandle.h>
#import <LindChain/Services/bootstrapd/LDEApplicationObject.h>
#import <LindChain/Services/bootstrapd/LDEApplicationWorkspaceObserver.h>

@protocol LDEApplicationWorkspaceService

@required
- (void)ping;

- (void)openApplicationWithBundleID:(NSString*)bundleIdentifier withReply:(void (^)(BOOL))reply;

- (void)installApplicationWithArchiveHandle:(PEArchiveHandle*)archiveHandle withReply:(void (^)(BOOL))reply;
- (void)deleteApplicationWithBundleID:(NSString*)bundleID withReply:(void (^)(BOOL))reply;
- (void)applicationInstalledWithBundleID:(NSString*)bundleID withReply:(void (^)(BOOL))reply;
- (void)applicationObjectForBundleID:(NSString*)bundleID withReply:(void (^)(LDEApplicationObject*))reply;
- (void)applicationContainerForBundleID:(NSString*)bundleID withReply:(void (^)(NSURL*))reply;
- (void)clearContainerForBundleID:(NSString*)bundleID withReply:(void (^)(BOOL))reply;
- (void)fastpathUtility:(PEFileHandle*)object withName:(NSString*)name withReply:(void (^)(NSString*,BOOL))reply;
- (void)applicationObjectForExecutablePath:(NSString*)executablePath withReply:(void (^)(LDEApplicationObject*))reply;
- (void)utilityHomePathWithReply:(void (^)(NSString*))reply;

@end

@interface LDEApplicationWorkspaceService : NSObject <LDEApplicationWorkspaceService,PEServiceProtocol>
@end

#endif /* __has_include(<LiveShim/Service.h>) */

#endif /* LDEAPPLICATIONWORKSPACESERVICE_H */
