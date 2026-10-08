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

#include <LindChain/ProcEnvironment/Surface/surface.h>
#include <LindChain/ProcEnvironment/Surface/tty/lookup.h>
#include <LindChain/ProcEnvironment/Surface/libkern/bsd/proc_info.h>

kern_return_t tty_for_port(fileport_t port,
                           ksurface_tty_t **tty)
{
    /* sanity check */
    assert(tty != NULL);
    
    /* getting file descriptor */
    int fd = fileport_makefd(port);
    if(fd < 0)
    {
        return KERN_INVALID_RIGHT;
    }
    
    /* getting unique object pointer */
    struct socket_fdinfo si;
    int ret = proc_pidfdinfo(getpid(), fd, PROC_PIDFDSOCKETINFO, &si, sizeof(si));
    close(fd);
    if(ret <= 0)
    {
        return KERN_FAILURE;
    }
    
    /* tty tree lookup */
    tty_table_rdlock();
    ksurface_tty_t *found = radix_lookup(&(ksurface->tty_info.tty), si.psi.soi_proto.pri_kern_ctl.kcsi_id);
    if(found == NULL)
    {
        tty_table_unlock();
        return KERN_NOT_FOUND;
    }
    
    /*
     * caller expects retained tty object, so
     * attempting to retain it and if it doesnt work
     * returning with an error.
     */
    bool retained = kvo_retain(found);
    tty_table_unlock();
    if(!retained)
    {
        return KERN_FAILURE;
    }
    
    *tty = found;
    
    return KERN_SUCCESS;
}
