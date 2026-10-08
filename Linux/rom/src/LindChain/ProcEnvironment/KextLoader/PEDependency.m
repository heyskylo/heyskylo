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

#import <LindChain/ProcEnvironment/KextLoader/PEDependency.h>

@implementation PEDependency

+ (instancetype)dependencyForString:(NSString*)depString
{
    NSError *error = nil;
    NSString *pattern = @"^([^<]+)<min:([^,]+),max:([^>]+)>$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:depString options:0 range:NSMakeRange(0, depString.length)];
    if(match && match.numberOfRanges == 4)
    {
        PEDependency *dep = [[PEDependency alloc] init];
        dep.bundleID = [depString substringWithRange:[match rangeAtIndex:1]];
        dep.minVersion = [depString substringWithRange:[match rangeAtIndex:2]];
        dep.maxVersion = [depString substringWithRange:[match rangeAtIndex:3]];
        return dep;
    }
    
    return nil;
}

@end
