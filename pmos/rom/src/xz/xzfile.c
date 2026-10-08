/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 xzfile.c — streaming .xz decompression for the postmarketOS ROM.

 Decodes a full .xz stream (LZMA2 + CRC32/CRC64/SHA-256 checks) from one file
 to another using the vendored XZ-Embedded decoder (0BSD, tukaani-project,
 pinned at ae63ae3a36ed01724674e8f3d750dc47bf125410), reporting input-consumed
 progress so the host UI can drive a progress bar while the guest disk image is
 staged inside the slot's writable storage.

 The image server publishes postmarketOS images as .img.xz, and iOS has no
 liblzma, so the ROM carries its own decoder.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "xz.h"

/* xz_crc32_init / xz_crc64_init are declared in xz_private.h (decoder internals)
   which a public driver should not include; declare them here instead. */
extern void xz_crc32_init(void);
extern void xz_crc64_init(void);

#define XZFILE_IN_SZ      (256u * 1024u)
#define XZFILE_OUT_SZ     (256u * 1024u)
#define XZFILE_DICT_LIMIT (256u * 1024u * 1024u)

/* No-progress guard: two consecutive runs that consume nothing and produce
   nothing are treated as a corrupt/truncated stream. */
#define XZFILE_MAX_STALL  2

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
    XZ_ERR_MEMLIMIT  = -8,
    XZ_ERR_LIMIT_CTX = -9
};

typedef void (*xzfile_progress)(void *ctx,
                                unsigned long long consumed_in,
                                unsigned long long total_in,
                                unsigned long long produced_out);

static int xzfile_map_error(struct xz_dec *decoder, enum xz_ret ret)
{
    xz_dec_end(decoder);
    switch (ret)
    {
        case XZ_MEM_ERROR:
        case XZ_MEMLIMIT_ERROR:
            return XZ_ERR_MEMLIMIT;
        case XZ_OPTIONS_ERROR:
        case XZ_FORMAT_ERROR:
            return XZ_ERR_OPTIONS;
        case XZ_DATA_ERROR:
        case XZ_BUF_ERROR:
        default:
            return XZ_ERR_CORRUPT;
    }
}

int xzfile_extract(const char *in_path, const char *out_path,
                   xzfile_progress progress, void *ctx)
{
    FILE *in = NULL;
    FILE *out = NULL;
    uint8_t *ibuf = NULL;
    uint8_t *obuf = NULL;
    struct xz_dec *decoder = NULL;
    int rc = XZ_ERR_ALLOC;

    in = fopen(in_path, "rb");
    if (in == NULL)
    {
        return XZ_ERR_OPEN_IN;
    }
    out = fopen(out_path, "wb");
    if (out == NULL)
    {
        fclose(in);
        return XZ_ERR_OPEN_OUT;
    }

    unsigned long long total_in = 0;
    {
        fseek(in, 0, SEEK_END);
        long end = ftell(in);
        if (end > 0)
        {
            total_in = (unsigned long long)end;
        }
        fseek(in, 0, SEEK_SET);
    }

    ibuf = malloc(XZFILE_IN_SZ);
    obuf = malloc(XZFILE_OUT_SZ);
    if (ibuf == NULL || obuf == NULL)
    {
        goto done;
    }

    xz_crc32_init();
    xz_crc64_init();
    decoder = xz_dec_init(XZ_DYNALLOC, XZFILE_DICT_LIMIT);
    if (decoder == NULL)
    {
        goto done;
    }

    struct xz_buf b;
    memset(&b, 0, sizeof(b));
    b.in = ibuf;
    b.out = obuf;
    b.out_size = XZFILE_OUT_SZ;

    unsigned long long read_total = 0;
    unsigned long long produced = 0;
    int stall = 0;
    enum xz_ret ret = XZ_OK;
    rc = XZ_ERR_CORRUPT;

    for (;;)
    {
        /* Refill input when the decoder consumed everything we handed it. */
        if (b.in_pos == b.in_size)
        {
            size_t n = fread(ibuf, 1, XZFILE_IN_SZ, in);
            if (n == 0 && ferror(in))
            {
                rc = XZ_ERR_READ;
                goto done;
            }
            b.in_pos = 0;
            b.in_size = n;
            read_total += n;
        }

        size_t in_before = b.in_pos;
        size_t out_before = b.out_pos;
        ret = xz_dec_run(decoder, &b);

        unsigned long long consumed_in = read_total - (b.in_size - b.in_pos);
        if (progress != NULL)
        {
            progress(ctx, consumed_in, total_in, produced);
        }

        if (ret == XZ_OK
            && b.in_pos == in_before
            && b.out_pos == out_before)
        {
            if (++stall >= XZFILE_MAX_STALL)
            {
                rc = XZ_ERR_CORRUPT;
                goto done;
            }
        }
        else
        {
            stall = 0;
        }

        /* Flush full output buffers and anything pending at stream end. */
        if (b.out_pos == XZFILE_OUT_SZ
            || (ret == XZ_STREAM_END && b.out_pos > 0))
        {
            if (fwrite(obuf, 1, b.out_pos, out) != b.out_pos)
            {
                rc = XZ_ERR_WRITE;
                goto done;
            }
            produced += b.out_pos;
            b.out_pos = 0;
        }

        if (ret == XZ_STREAM_END)
        {
            rc = XZ_ERR_OK;
            goto done;
        }
        if (ret != XZ_OK)
        {
            rc = xzfile_map_error(decoder, ret);
            decoder = NULL; /* map_error already released it */
            goto done;
        }
    }

done:
    if (progress != NULL && rc == XZ_ERR_OK)
    {
        progress(ctx, total_in, total_in, produced);
    }
    if (decoder != NULL)
    {
        xz_dec_end(decoder);
    }
    if (obuf != NULL)
    {
        free(obuf);
    }
    if (ibuf != NULL)
    {
        free(ibuf);
    }
    if (in != NULL)
    {
        fclose(in);
    }
    if (out != NULL)
    {
        if (rc == XZ_ERR_OK)
        {
            int ferr = fflush(out);
            if (ferr != 0)
            {
                rc = XZ_ERR_WRITE;
            }
        }
        if (rc != XZ_ERR_OK)
        {
            fclose(out);
            remove(out_path);
        }
        else
        {
            fclose(out);
        }
    }
    return rc;
}