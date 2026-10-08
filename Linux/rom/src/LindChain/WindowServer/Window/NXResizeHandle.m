/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2023 - 2025 LiveContainer
 Copyright (C) 2025 - 2026 mach-port

 This file is part of LiveContainer.

 LiveContainer is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 LiveContainer is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import <LindChain/WindowServer/Window/NXResizeHandle.h>

@implementation NXResizeHandle {
    UIView *_backgroundView;
    dispatch_block_t _restoreBlock;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if(self)
    {
        self.layer.masksToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        
        _backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width*sqrt(2), frame.size.height*sqrt(2))];
        if(_backgroundView == nil)
        {
            return nil;
        }
        
        _backgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2]; // Normal state
        _backgroundView.center = CGPointMake(frame.size.width, frame.size.height);
        _backgroundView.transform = CGAffineTransformMakeRotation(M_PI_4);
        _backgroundView.layer.cornerRadius = 8;
        
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        [self addGestureRecognizer:doubleTap];
        
        [self addSubview:_backgroundView];
    }
    return self;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{
    [self hideTemporarilyForDuration:2.0];
}

- (void)hideTemporarilyForDuration:(NSTimeInterval)duration
{
    if(_restoreBlock != NULL)
    {
        dispatch_block_cancel(_restoreBlock);
        _restoreBlock = NULL;
    }
    
    self.userInteractionEnabled = NO;
    
    [UIView animateWithDuration:0.30 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alpha = 0.0;
    } completion:nil];
    
    __weak typeof(self) weakSelf = self;
    _restoreBlock = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        if(strongSelf == nil)
        {
            return;
        }
        strongSelf->_restoreBlock = NULL;
        [UIView animateWithDuration:0.50 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            strongSelf.alpha = 1.0;
        } completion:^(BOOL finished) {
            strongSelf.userInteractionEnabled = YES;
            [strongSelf setGlowing:NO];
        }];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), _restoreBlock);
}

- (void)setGlowing:(BOOL)glowing
{
    [UIView animateWithDuration:0.30 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if(glowing)
        {
            self->_backgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.6];
        }
        else
        {
            self->_backgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
        }
    } completion:nil];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    [self setGlowing:YES];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    [self setGlowing:NO];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    [self setGlowing:NO];
}

#if DEBUG

- (void)dealloc
{
    NSLog(@"deallocated %@", self);
}

#endif /* DEBUG */

@end
