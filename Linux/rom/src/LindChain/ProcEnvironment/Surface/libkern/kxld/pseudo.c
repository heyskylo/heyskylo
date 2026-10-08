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

#include <LindChain/ProcEnvironment/Surface/libkern/kxld/pseudo.h>

kern_return_t kxopen_pseudo(const char *identifier,
                            uint32_t version,
                            uint64_t flags,
                            kxld_image_info_t **out_image_info)
{
    if(identifier == NULL || out_image_info == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    kxld_image_info_t *image_info = kvo_alloc_fastpath(kxld_image);
    if(image_info == NULL)
    {
        return KERN_RESOURCE_SHORTAGE;
    }
    
    kinfo_mod_t *pseudo_mod = calloc(1, sizeof(kinfo_mod_t));
    if(pseudo_mod == NULL)
    {
        kvo_release(image_info);
        return KERN_RESOURCE_SHORTAGE;
    }
    image_info->mod = pseudo_mod;
    
    strlcpy((char*)pseudo_mod->identifier, identifier, sizeof(pseudo_mod->identifier));
    pseudo_mod->magic = KSURFACE_KMOD_MAGIC;
    pseudo_mod->version = version;
    pseudo_mod->abi_version = KSURFACE_KMOD_ABI_VERSION;
    pseudo_mod->flags = flags;
    
    *out_image_info = image_info;
    return KERN_SUCCESS;
}
