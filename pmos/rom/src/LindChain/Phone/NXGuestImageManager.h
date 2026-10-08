/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXGuestImageManager — the on-boot download gate for the postmarketOS image.

 Slots in this ROM do NOT ship the guest OS. On first boot the host checks
 whether a verified image is staged under <slot>/guest/postmarketos.img; if
 not, this manager downloads the .img.xz pinned in guest-images.lock.tsv,
 verifies its SHA-256 against the same pin, and decompresses it on-device
 with the vendored XZ decoder (rom/src/xz). Only then does the host hand the
 engine the disk path and boot the VM.
*/

#ifndef NXGUESTIMAGEMANAGER_H
#define NXGUESTIMAGEMANAGER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NXGuestImageErrorDomain;

typedef NS_ENUM(NSInteger, NXGuestImageErrorCode)
{
    NXGuestImageErrorDownload = 1,
    NXGuestImageErrorVerify,
    NXGuestImageErrorDecompress,
    NXGuestImageErrorCancelled,
};

@interface NXGuestImageManager : NSObject

@property (nonatomic, readonly) NSURL *slotURL;
@property (nonatomic, readonly) NSURL *dataURL;
@property (nonatomic, readonly, getter=isDownloading) BOOL downloading;

/* slotURL is the flashed slot root (read-only ROM payloads). The guest image
   lives under dataURL's guest/ directory instead of inside the slot, because
   reflashing Nyxian wipes Library/Boot/Slot/A wholesale and the 4 GB image
   must survive that. */
- (instancetype)initWithSlotURL:(NSURL *)slotURL dataURL:(NSURL *)dataURL;

/* YES when a previously verified image is already staged (fast marker check,
   no re-hash of a 4 GB file on every launch). */
- (BOOL)hasPinnedImage;

/* Path of the staged bootable disk (guest/postmarketos.img), if present. */
- (nullable NSString *)stagedImagePath;

/* progress: phase string + fraction in [0,1]. phase ∈ {downloading,
   verifying, decompressing} (verifying is indeterminate, progress -1). */
- (void)beginWithProgress:(void (^)(NSString *phase, double progress))progress
               completion:(void (^)(NSError * _Nullable error))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
#endif /* NXGUESTIMAGEMANAGER_H */