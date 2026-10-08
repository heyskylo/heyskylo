/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXPostmarketOSViewController — the ROM's single screen.
*/

#ifndef NXPOSTMARKETOSVIEWCONTROLLER_H
#define NXPOSTMARKETOSVIEWCONTROLLER_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NXPostmarketOSViewController : UIViewController

/* slotURL: the flashed slot root (Library/Boot/Slot/A). dataURL: reflash-
   surviving directory for the guest image, OVMF vars and logs. */
- (instancetype)initWithSlotURL:(NSURL *)slotURL
                        dataURL:(NSURL *)dataURL NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
#endif /* NXPOSTMARKETOSVIEWCONTROLLER_H */