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

#include <LindChain/ProcEnvironment/Surface/fs/mount.h>
#include <sys/stat.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>
#include <os/lock.h>

static os_unfair_lock g_mount_lock = OS_UNFAIR_LOCK_INIT;

static kern_return_t __ksurface_fs_mount_clear_directory(const char *dir_path)
{
    DIR *dir = opendir(dir_path);
    if(!dir)
    {
        return KERN_NOT_FOUND;
    }
    
    struct dirent *entry;
    char path[PATH_MAX];
    
    while((entry = readdir(dir)) != NULL)
    {
        if(strcmp(entry->d_name, ".") == 0 ||
           strcmp(entry->d_name, "..") == 0)
        {
            continue;
        }
        
        snprintf(path, sizeof(path), "%s/%s", dir_path, entry->d_name);
        
        struct stat statbuf;
        if(lstat(path, &statbuf) == 0)
        {
            if(S_ISDIR(statbuf.st_mode))
            {
                __ksurface_fs_mount_clear_directory(path);
                rmdir(path);
            }
            else
            {
                unlink(path);
            }
        }
    }
    
    closedir(dir);
    return KERN_SUCCESS;
}

kern_return_t ksurface_fs_mount(FSMountAttr attributes,
                                const char *old_mount_dir,
                                const char *old_bind_dir,
                                ...)
{
    if(old_mount_dir == NULL || old_mount_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(old_bind_dir != NULL && old_bind_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /*
     * mount2 is much better since it solves many confusion problems
     * you shall use mount2 instead of mount since mount has a problem.
     *
     * either mount_dir is the path that is user accessible or
     * mount_dir is the path that represents the device, the problem
     * with that is that then bind_dir_becomes the mount_dir.
     */
    
    const char *device_dir = NULL;
    const char *mount_dir = NULL;
    
    if(old_mount_dir && old_bind_dir)
    {
        device_dir = old_bind_dir;
        mount_dir = old_mount_dir;
    }
    else
    {
        device_dir = "/dev/nounlink";
        mount_dir = old_mount_dir;
    }
    
    return ksurface_fs_mount2(attributes, device_dir, mount_dir);
}

kern_return_t ksurface_fs_mount2(FSMountAttr attributes,
                                 const char *device_dir,
                                 const char *mount_dir,
                                 ...)
{
    if(mount_dir == NULL || mount_dir[0] != '/' ||
       device_dir == NULL || device_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /* check for yet unsupported flags */
    if(attributes & (kFSMountAttrReadPlatform | kFSMountAttrWritePlatform | kFSMountAttrReadEntitlement | kFSMountAttrWriteEntitlement))
    {
        return KERN_NOT_SUPPORTED;
    }
    
    /* manage permissions */
    FSMountPermissionFlags permissions = kFSMountPermissionNone;
    if((attributes & kFSMountAttrWrite) && !(attributes & kFSMountAttrRead))
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(attributes & kFSMountAttrWrite)
    {
        permissions = kFSMountPermissionReadWrite;
    }
    else if(attributes & kFSMountAttrRead)
    {
        permissions = kFSMountPermissionRead;
    }
    else
    {
        permissions = kFSMountPermissionNone;
    }
    
    /* if bind_dir is givven it becomes a directory */
    FSNodeType type = kFSNodeTypeSymbolicLink;
    static const char preserver_device[PATH_MAX] = "/dev/nounlink";
    if(strncmp(device_dir, preserver_device, sizeof(preserver_device)) == 0)
    {
        type = kFSNodeTypeDirectory;
    }
    
    /* shall this be cleared? */
    if(attributes & kFSMountAttrClear)
    {
        switch(type)
        {
            case kFSNodeTypeDirectory:
                __ksurface_fs_mount_clear_directory(mount_dir);
                break;
            case kFSNodeTypeSymbolicLink:
                __ksurface_fs_mount_clear_directory(device_dir);
                break;
            default:
                return KERN_FAILURE;
        }
    }
    
    /* preparing node */
    FSPreserverNode node = { .type = type, 0 };
    strlcpy(node.name, mount_dir, PATH_MAX);
    if(device_dir != NULL && type != kFSNodeTypeDirectory)
    {
        strlcpy(node.target, device_dir, PATH_MAX);
    }
    
    os_unfair_lock_lock(&g_mount_lock);
    
    /* and register it */
    kern_return_t kr = ksurface_fs_preserver_add_node(node);
    if(kr != KERN_SUCCESS)
    {
        os_unfair_lock_unlock(&g_mount_lock);
        return kr;
    }
    
    /* adding sandbox filesystem register for mount */
    kr = ksurface_fs_sandbox_registry_add(permissions, type, mount_dir, (type == kFSNodeTypeDirectory) ? NULL : device_dir);
    os_unfair_lock_unlock(&g_mount_lock);
    return kr;
}

kern_return_t ksurface_fs_umount(const char *mount_dir)
{
    if(mount_dir == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    char rpath[PATH_MAX];
    if(realpath(mount_dir, rpath) == NULL)
    {
        /* path doesn't exist so mount does not? */
        strlcpy(rpath, mount_dir, PATH_MAX);
    }
    
    /* perform userspace unmount */
    os_unfair_lock_lock(&g_mount_lock);
    kern_return_t kr = ksurface_fs_sandbox_registry_remove(rpath);
    if(kr != KERN_SUCCESS)
    {
        os_unfair_lock_unlock(&g_mount_lock);
        return kr;
    }
    
    kr = ksurface_fs_preserver_remove_node(rpath);
    if(kr != KERN_SUCCESS)
    {
        os_unfair_lock_unlock(&g_mount_lock);
        return kr;
    }
    os_unfair_lock_unlock(&g_mount_lock);
    
    return KERN_SUCCESS;
}
