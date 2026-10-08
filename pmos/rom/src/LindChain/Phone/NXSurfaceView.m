/*
 SPDX-License-Identifier: GPL-2.0-or-later

 See NXSurfaceView.h. v1 keeps the layer plain black; the engine milestone
 swaps in the Metal presentation layer and frame delivery.
*/

#import "NXSurfaceView.h"

@implementation NXSurfaceView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = YES;
    }
    return self;
}

@end