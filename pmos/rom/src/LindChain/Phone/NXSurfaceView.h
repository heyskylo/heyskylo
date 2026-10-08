/*
 SPDX-License-Identifier: GPL-2.0-or-later

 NXSurfaceView — the full-screen guest display surface. No chrome: no gamepad,
 no keyboard, no window bars; just the phone UI.

 The layer is a CAMetalLayer. Every display-link tick the view snapshots the
 guest framebuffer through NXPMOSEngine (lock/unlockFrame: — a software
 DisplayChangeListener bridge inside the engine dylib), uploads it to a
 Metal texture, aspect-fits it full-screen, and presents. Touch hits are
 forwarded to the guest as virtio-tablet absolute input; hardware keyboards
 map to QKeyCode names.
*/

#ifndef NXSURFACEVIEW_H
#define NXSURFACEVIEW_H

#import <UIKit/UIKit.h>

@class NXPMOSEngine;

NS_ASSUME_NONNULL_BEGIN

@protocol NXSurfaceViewDelegate <NSObject>
@optional
/* Called once, after the first guest frame has been presented. */
- (void)surfaceViewDidPresentFirstFrame:(UIView *)surfaceView;
@end

@interface NXSurfaceView : UIView

/* The running engine that owns the framebuffer. The view stays black while
   this is nil. */
@property (nonatomic, weak, nullable) NXPMOSEngine *engine;
@property (nonatomic, weak, nullable) id<NXSurfaceViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
#endif /* NXSURFACEVIEW_H */