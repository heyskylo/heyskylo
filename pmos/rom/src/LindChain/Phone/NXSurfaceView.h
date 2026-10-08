/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXSurfaceView — the full-screen guest display surface. No chrome: no gamepad,
 no keyboard, no window bars; just the phone UI. The engine milestone backs
 this view with CAMetalLayer and feeds it DisplayChangeListener frames; touch
 hits are forwarded to the guest as virtio-tablet absolute input.
*/

#ifndef NXSURFACEVIEW_H
#define NXSURFACEVIEW_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NXSurfaceView : UIView

@end

NS_ASSUME_NONNULL_END
#endif /* NXSURFACEVIEW_H */