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

#import <LindChain/ProcEnvironment/Utils/misc.h>
#import <LindChain/Private/UIKitPrivate.h>
#import <Foundation/Foundation.h>

@interface _LSOpenConfiguration : NSObject
@property(nonatomic, copy) NSDictionary *frontBoardOptions;
@end

extern NSString* FBSOpenApplicationOptionKeyActivateAsClassic;
extern NSString* FBSOpenApplicationOptionKeyPayloadURL;

@interface LSApplicationWorkspace (LiveContainerSkid)
- (BOOL)openURL:(id)url;
- (BOOL)isApplicationAvailableToOpenURL:(id)arg1 error:(id*)arg2;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleID configuration:(_LSOpenConfiguration *)configuration completionHandler:(void (^)(BOOL, NSError *))completion;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleID usingConfiguration:(_LSOpenConfiguration *)configuration completionHandler:(void (^)(BOOL, NSError *))completion;
@end

void PERestartSelf(void)
{
    /* thanks Duy Tran */
    void (^completionHandler)(BOOL) = ^(BOOL success) {
        // syscall(SYS_ptrace, PT_DENY_ATTACH, 0, 0, 0);
        __asm__ __volatile__ ("mov x0, #31\n"
                              "mov x16, #26\n"
                              "svc #0x80");
        raise(SIGKILL);
    };
    
    _LSOpenConfiguration *configuration = [[PrivClass(_LSOpenConfiguration) alloc] init];
    LSApplicationWorkspace* workspace = [PrivClass(LSApplicationWorkspace) defaultWorkspace];
    
    int tries = 2;
    for(int i = 0; i < tries; i++)
    {
        [workspace openApplicationWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier configuration:configuration completionHandler:^(BOOL success, NSError* error) {
            completionHandler(success);
        }];
    }
}

BOOL PEURLIsContainedIn(NSURL *candidate,
                        NSURL *root)
{
    NSURL *candidateSatnderized = candidate.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *rootSatnderized = root.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    
    NSString *candidatePath = candidateSatnderized.path;
    NSString *rootPath = rootSatnderized.path;
    
    if(![rootPath hasSuffix:@"/"])
    {
        rootPath = [rootPath stringByAppendingString:@"/"];
    }
    NSString *canditateSlash = [candidatePath hasSuffix:@"/"] ? candidatePath : [candidatePath stringByAppendingString:@"/"];
    return [canditateSlash isEqualToString:rootPath] || [canditateSlash hasPrefix:rootPath];
}
