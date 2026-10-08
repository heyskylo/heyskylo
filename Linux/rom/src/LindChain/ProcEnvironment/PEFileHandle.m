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

#import <LindChain/ProcEnvironment/PEFileHandle.h>
#include <LindChain/ProcEnvironment/Utils/fd.h>
#include <LindChain/ProcEnvironment/Utils/vnode.h>
#include <copyfile.h>
#include <fcntl.h>

@implementation PEFileHandle

- (instancetype)init
{
    self = [super init];
    return self;
}

+ (instancetype)handleForFileDescriptor:(int)fd
{
    if(fd_is_guarded(fd))
    {
        return nil;
    }
    
    PEFileHandle *object = [[self alloc] init];
    if(object != nil)
    {
        object.fd = xpc_fd_create(fd);
    }
    return object;
}

+ (instancetype)handleForFilePort:(fileport_t)fp
{
    int fd = fileport_makefd(fp);
    if(fd < 0)
    {
        return nil;
    }
    
    PEFileHandle *object = [self handleForFileDescriptor:fd];
    close(fd);
    return object;
}

+ (instancetype)handleForFileAtPath:(NSString*)path
                          withFlags:(int)flags
                    withPermissions:(int)perm
{
    int fd = open([path UTF8String], flags, perm);
    if(fd < 0)
    {
        return nil;
    }
    
    PEFileHandle *object = [self handleForFileDescriptor:fd];
    close(fd);
    return object;
}

+ (instancetype)handleForFileAtPath:(NSString*)path
                          withFlags:(int)flags
{
    return [self handleForFileAtPath:path withFlags:flags withPermissions:0777];
}

+ (instancetype)handleForFileAtPath:(NSString*)path
{
    return [self handleForFileAtPath:path withFlags:O_RDWR];
}

- (void)setFileDescriptor:(int)fd
{
    _fd = xpc_fd_create(fd);
}

- (int)extractFileDescriptor
{
    return xpc_fd_dup(_fd);
}

- (BOOL)extractFileDescriptorToLoc:(int)loc
{
    if(loc < 0 || fd_is_guarded(loc))
    {
        return NO;
    }
    
    int cfd = xpc_fd_dup(_fd);
    if(cfd == loc)
    {
        return YES;
    }
    else
    {
        int retval = dup2(cfd, loc);
        close(cfd);
        if(retval < 0)
        {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)writeOut:(NSString*)path
{
    int tmpfd = xpc_fd_dup(_fd);
    if(tmpfd < 0)
    {
        return NO;
    }
    
    /* reset temporary file descriptor to the beginning of the file */
    if(lseek(tmpfd, 0, SEEK_SET) == -1)
    {
        close(tmpfd);
        return NO;
    }
    
    bool success = vnode_recover_with_fd_to_path(tmpfd, [path UTF8String]);
    close(tmpfd);
    if(!success)
    {
        close(tmpfd);
        return NO;
    }
    
    return tmpfd == 0;
}

- (BOOL)writeIn:(NSString*)path
{
    int tmpfd = xpc_fd_dup(_fd);
    if(tmpfd < 0)
    {
        return NO;
    }
    
    int srcFd = open([path UTF8String], O_RDONLY);
    if(srcFd < 0)
    {
        close(tmpfd);
        return NO;
    }
    
    ftruncate(tmpfd, 0);
    lseek(tmpfd, 0, SEEK_SET);
    
    int ret = fcopyfile(srcFd, tmpfd, NULL, COPYFILE_DATA);
    
    close(srcFd);
    close(tmpfd);
    
    return ret == 0;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder
{
    [(id)coder encodeXPCObject:_fd forKey:@"fd"];
    return;
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder
{
    self = [super init];
    if(self)
    {
        _fd = [(id)coder decodeXPCObjectOfType:XPC_TYPE_FD forKey:@"fd"];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    PEFileHandle *copy = [[[self class] allocWithZone:zone] init];
    copy.fd = [self.fd copy];
    return copy;
}

@end
