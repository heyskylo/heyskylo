/*
 SPDX-License-Identifier: GPL-2.0-or-later

 Phone boot flow states for the postmarketOS ROM host.
*/

#ifndef NXBOOTSTATE_H
#define NXBOOTSTATE_H

typedef NS_ENUM(NSUInteger, NXBootState)
{
    NXBootStateChecking = 0,          /* slot scanned for a staged image */
    NXBootStateNeedsDownload,         /* image missing: show Download button */
    NXBootStateDownloading,           /* fetching + verifying + decompressing */
    NXBootStateBooting,               /* QEMU/JIT engine bringing the VM up */
    NXBootStateRunning,               /* full-screen phone UI (Phosh) */
    NXBootStateEngineUnavailable,     /* engine not bundled in this ROM build */
    NXBootStateFailed,                /* last operation failed */
};

#endif /* NXBOOTSTATE_H */