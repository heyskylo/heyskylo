/*
 SPDX-License-Identifier: GPL-2.0-or-later

 Minimal public interface for the streaming .xz decoder used by the ROM host
 (see xzfile.c for details). Consumed-input fraction is reported through
 `progress` so the host can drive a progress bar across a large image.
 */

#ifndef XZFILE_H
#define XZFILE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*xzfile_progress)(void *ctx,
                                unsigned long long consumed_in,
                                unsigned long long total_in,
                                unsigned long long produced_out);

/* Decodes the .xz stream at in_path into out_path. Returns 0 on success,
   a negative XZ_ERR_* code otherwise (see xzfile.c: defined there, mirrored
   here for callers that need to distinguish error classes). */
int xzfile_extract(const char *in_path,
                   const char *out_path,
                   xzfile_progress progress,
                   void *ctx);

enum
{
    XZ_ERR_OK        = 0,
    XZ_ERR_OPEN_IN   = -1,
    XZ_ERR_OPEN_OUT  = -2,
    XZ_ERR_ALLOC     = -3,
    XZ_ERR_READ      = -4,
    XZ_ERR_WRITE     = -5,
    XZ_ERR_CORRUPT   = -6,
    XZ_ERR_OPTIONS   = -7,
    XZ_ERR_MEMLIMIT  = -8
};

#ifdef __cplusplus
}
#endif

#endif /* XZFILE_H */