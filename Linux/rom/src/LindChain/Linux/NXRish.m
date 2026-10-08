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

#import "NXRish.h"
#import <rish.h>

static NSString * const NXRishErrorDomain = @"org.emexlabs.rom.linuxkernel.rish";

@interface NXRish (JSON)
+ (NSData *)JSONDataWithObject:(id)object;
+ (id)JSONObjectWithUTF8String:(NSString *)string;
@end

@implementation NXRish {
    void *_session;
}

@synthesize protocolVersion = _protocolVersion;

- (instancetype)init
{
    return [super init];
}

- (nullable instancetype)initWithKernelPath:(NSString *)kernelPath
                              initramfsPath:(NSString *)initramfsPath
                                   memoryMiB:(NSUInteger)memoryMiB
                                commandLine:(NSString *)commandLine
{
    self = [super init];
    if(self)
    {
        NSDictionary *request = @{
            @"kernel_path": kernelPath,
            @"initrd_path": initramfsPath,
            @"memory_mib": @(memoryMiB),
            @"command_line": commandLine,
            @"boot_budget_units": @(60000000000ULL),
            @"handshake_budget_units": @(40000000000ULL),
        };
        NSData *payload = [NXRish JSONDataWithObject:request];
        if(!payload)
        {
            return nil;
        }
        _protocolVersion = rish_protocol_version();
        _session = rish_vm_boot_session(payload.bytes, payload.length);
        if(!_session)
        {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    if(_session)
    {
        rish_vm_session_free(_session);
        _session = NULL;
    }
}

- (BOOL)runCommandWithArguments:(NSArray<NSString *> *)arguments
                            cwd:(NSString *)cwd
                      timeoutMS:(NSUInteger)timeoutMS
                         stdout:(NSString * _Nullable * _Nullable)outStdout
                         stderr:(NSString * _Nullable * _Nullable)outStderr
                       exitCode:(int * _Nullable)outExitCode
                          error:(NSError * _Nullable * _Nullable)error
{
    if(!_session || arguments.count == 0)
    {
        if(error)
        {
            *error = [NSError errorWithDomain:NXRishErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"no live rish session"}];
        }
        return NO;
    }

    NSMutableDictionary *request = [@{ @"protocol_version": @2, @"command": arguments } mutableCopy];
    if(cwd.length > 0)
    {
        request[@"cwd"] = cwd;
    }
    request[@"timeout_ms"] = @(timeoutMS);

    NSData *payload = [NXRish JSONDataWithObject:request];
    if(!payload)
    {
        if(error)
        {
            *error = [NSError errorWithDomain:NXRishErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"failed to encode rish exec request"}];
        }
        return NO;
    }

    char *reply = rish_vm_session_exec_json(_session, payload.bytes, payload.length);
    if(!reply)
    {
        if(error)
        {
            *error = [NSError errorWithDomain:NXRishErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"rish exec returned no reply"}];
        }
        return NO;
    }
    NSString *replyString = [NSString stringWithCString:reply encoding:NSUTF8StringEncoding];
    rish_string_free(reply);
    if(!replyString)
    {
        if(error)
        {
            *error = [NSError errorWithDomain:NXRishErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"rish exec reply was not UTF-8"}];
        }
        return NO;
    }

    NSDictionary *object = [NXRish JSONObjectWithUTF8String:replyString];
    if(![object isKindOfClass:NSDictionary.class])
    {
        if(error)
        {
            *error = [NSError errorWithDomain:NXRishErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"rish exec reply was not a JSON object"}];
        }
        return NO;
    }

    /* rish encodes `ok` as (exit_code == 0), so a command that runs and exits
     * non-zero still arrives with stdout/stderr and an exit_code. A genuine
     * VM-level failure (timeout, boot lost, channel error) replies without an
     * exit_code and carries an `error` string. Distinguish the two on that. */
    NSNumber *exitCodeNumber = object[@"exit_code"];
    if([exitCodeNumber isKindOfClass:NSNumber.class])
    {
        if(outStdout)
        {
            *outStdout = [object[@"stdout"] isKindOfClass:NSString.class] ? object[@"stdout"] : @"";
        }
        if(outStderr)
        {
            *outStderr = [object[@"stderr"] isKindOfClass:NSString.class] ? object[@"stderr"] : @"";
        }
        if(outExitCode)
        {
            *outExitCode = exitCodeNumber.intValue;
        }
        return YES;
    }

    if(outStdout)
    {
        *outStdout = @"";
    }
    if(outStderr)
    {
        *outStderr = @"";
    }
    if(outExitCode)
    {
        *outExitCode = -1;
    }
    if(error)
    {
        NSString *message = [object[@"error"] isKindOfClass:NSString.class] ? object[@"error"] : @"rish exec failed";
        *error = [NSError errorWithDomain:NXRishErrorDomain
                                     code:6
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

#pragma mark - JSON helpers

+ (NSData *)JSONDataWithObject:(id)object
{
    if(!object)
    {
        return nil;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if(!data || error)
    {
        return nil;
    }
    return data;
}

+ (id)JSONObjectWithUTF8String:(NSString *)string
{
    if(string.length == 0)
    {
        return nil;
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if(!data)
    {
        return nil;
    }
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    return (error == nil) ? object : nil;
}

@end