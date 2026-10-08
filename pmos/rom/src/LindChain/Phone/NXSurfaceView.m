/*
 SPDX-License-Identifier: GPL-2.0-or-later

 See NXSurfaceView.h. v1 backed by CAMetalLayer: the guest software framebuffer
 (BGRA little-endian, from QEMU's virtio-gpu + pixman) is memcpy'd into a
 shared-storage MTLTexture once per changed frame and drawn aspect-fitted — the
 phone-UI spec: nothing but Phosh, direct touch.
*/

#import "NXSurfaceView.h"
#import "NXPMOSEngine.h"

#import <Metal/Metal.h>
#import <QuartzCore/CADisplayLink.h>
#include <string.h>

static NSString * const NXMetalShaderSource =
@"#include <metal_stdlib>\n"
@"using namespace metal;\n"
@"struct VIn  { float2 pos; float2 uv; };\n"
@"struct VOut { float4 pos [[position]]; float2 uv; };\n"
@"vertex VOut nxp_vs(uint vid [[vertex_id]], const device VIn *v [[buffer(0)]]) {\n"
@"  VOut o; o.pos = float4(v[vid].pos, 0.0, 1.0); o.uv = v[vid].uv; return o;\n"
@"}\n"
@"fragment half4 nxp_fs(VOut in [[stage_in]], texture2d<half> tex [[texture(0)]]) {\n"
@"  constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_zero);\n"
@"  return tex.sample(s, in.uv);\n"
@"}\n";

@implementation NXSurfaceView
{
    id<MTLDevice>       _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLBuffer>       _quad;
    id<MTLTexture>      _frameTexture;
    CADisplayLink       *_link;
    uint64_t            _lastSequence;
    uint64_t            _lastGeneration;
    int32_t             _frameWidth;
    int32_t             _frameHeight;
    BOOL                _didPresentFirstFrame;
    CGSize              _lastHintBounds;
}

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        _device = MTLCreateSystemDefaultDevice();
        if (_device != nil)
        {
            CAMetalLayer *layer = (CAMetalLayer *)self.layer;
            layer.device = _device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.framebufferOnly = YES;
            layer.opaque = YES;
            _queue = [_device newCommandQueue];
            [self buildPipeline];
        }
    }
    return self;
}

- (void)buildPipeline
{
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:NXMetalShaderSource
                                                    options:nil
                                                      error:&error];
    if (library == nil)
    {
        NSLog(@"[nxp-surface] Metal library failed: %@", error.localizedDescription);
        return;
    }
    id<MTLFunction> vs = [library newFunctionWithName:@"nxp_vs"];
    id<MTLFunction> fs = [library newFunctionWithName:@"nxp_fs"];
    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vs;
    desc.fragmentFunction = fs;
    desc.colorAttachments[0].pixelFormat = ((CAMetalLayer *)self.layer).pixelFormat;
    _pipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (_pipeline == nil)
    {
        NSLog(@"[nxp-surface] pipeline failed: %@", error.localizedDescription);
    }
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self stopTicking];
    if (self.window != nil)
    {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)stopTicking
{
    if (_link != nil)
    {
        [_link invalidate];
        _link = nil;
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGFloat scale = self.window.screen.scale ?: 1.0;
    CGSize pixel = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    if (pixel.width > 0 && pixel.height > 0)
    {
        layer.drawableSize = pixel;
    }
}

#pragma mark - Presentation tick

- (void)tick
{
    NXPMOSEngine *engine = self.engine;
    if (engine == nil || _pipeline == nil)
    {
        return;
    }

    NXEngineFrame frame;
    if (![engine lockFrame:&frame])
    {
        return;
    }

    BOOL surfaceChanged = (frame.generation != _lastGeneration);
    BOOL frameChanged = (frame.sequence != _lastSequence || surfaceChanged);

    if (frame.pixels == NULL || frame.bpp != 32 || frame.width <= 0 || frame.height <= 0)
    {
        [engine unlockFrame];
        return;
    }

    if (surfaceChanged || _frameTexture == nil ||
        _frameWidth != frame.width || _frameHeight != frame.height)
    {
        MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
        desc.textureType = MTLTextureType2D;
        desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.width = (NSUInteger)frame.width;
        desc.height = (NSUInteger)frame.height;
        desc.storageMode = MTLStorageModeShared;
        desc.usage = MTLTextureUsageShaderRead;
        _frameTexture = [_device newTextureWithDescriptor:desc];
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _lastSequence = 0; /* force an upload for the new surface */
        frameChanged = YES;
    }

    if (frameChanged)
    {
        [_frameTexture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)frame.width,
                                                     (NSUInteger)frame.height)
                         mipmapLevel:0
                           withBytes:frame.pixels
                         bytesPerRow:(NSUInteger)frame.stride];
        _lastSequence = frame.sequence;
        _lastGeneration = frame.generation;
    }

    [engine unlockFrame];

    if (!frameChanged)
    {
        return;
    }
    [self present];
    [self hintGuestSizeOnce];
}

- (void)present
{
    CGSize viewPixels = ((CAMetalLayer *)self.layer).drawableSize;
    if (viewPixels.width <= 0 || viewPixels.height <= 0 || _frameWidth <= 0)
    {
        return;
    }
    id<CAMetalDrawable> drawable = [(CAMetalLayer *)self.layer nextDrawable];
    if (drawable == nil)
    {
        return;
    }
    [self updateQuadForView:viewPixels frameWidth:(CGFloat)_frameWidth
                        frameHeight:(CGFloat)_frameHeight];

    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    MTLRenderPassDescriptor *pass = [[MTLRenderPassDescriptor alloc] init];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLRenderCommandEncoder> enc = [buffer renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:_pipeline];
    [enc setVertexBuffer:_quad offset:0 atIndex:0];
    [enc setFragmentTexture:_frameTexture atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [enc endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];

    if (!_didPresentFirstFrame)
    {
        _didPresentFirstFrame = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(surfaceViewDidPresentFirstFrame:)])
            {
                [self.delegate surfaceViewDidPresentFirstFrame:self];
            }
        });
    }
}

/* Aspect-fit quad in clip coordinates, uvs mapped 0..1. Rebuilt only when the
   view or frame size changes (cheap enough to rebuild every present). */
- (void)updateQuadForView:(CGSize)view frameWidth:(CGFloat)fw frameHeight:(CGFloat)fh
{
    CGFloat va = view.width / view.height;
    CGFloat fa = fw / fh;
    CGFloat scale; /* fit frame into view, uniformly */
    if (fa > va)
    {
        scale = view.width / fw;
    }
    else
    {
        scale = view.height / fh;
    }
    CGFloat halfW = (fw * scale) / view.width;   /* in clip units (-1..1) */
    CGFloat halfH = (fh * scale) / view.height;

    struct V { float x, y, u, v; };
    struct V verts[6] = {
        { -halfW, -halfH, 0, 1 },
        {  halfW, -halfH, 1, 1 },
        { -halfW,  halfH, 0, 0 },
        {  halfW, -halfH, 1, 1 },
        {  halfW,  halfH, 1, 0 },
        { -halfW,  halfH, 0, 0 },
    };
    if (_quad == nil)
    {
        _quad = [_device newBufferWithLength:sizeof(verts) options:MTLResourceStorageModeShared];
    }
    memcpy(_quad.contents, verts, sizeof(verts));
}

/* Ask the guest to modeset to a phone-shaped resolution, so Phosh renders a
   phone UI instead of a 4:3 blob. Re-issued only when the view bounds change
   (rotation, layout): TCG + llvmpipe has to fill this in software, so the
   guest is also told once and the size is deliberately modest. */
- (void)hintGuestSizeOnce
{
    NXPMOSEngine *engine = self.engine;
    if (engine == nil)
    {
        return;
    }
    CGSize bounds = self.bounds.size;
    if (bounds.width == _lastHintBounds.width && bounds.height == _lastHintBounds.height)
    {
        return;
    }
    _lastHintBounds = bounds;
    BOOL landscape = bounds.width > bounds.height;
    int32_t w = landscape ? 2340 : 1080;
    int32_t h = landscape ? 1080 : 2340;
    [engine setUISizeWidth:w height:h];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self hintGuestSizeOnce];
}

- (void)dealloc
{
    [self stopTicking];
}

#pragma mark - Touch (virtio-tablet absolute)

- (CGPoint)pointToGuest:(UITouch *)touch
{
    CGPoint p = [touch locationInView:self];
    CGSize view = self.bounds.size;
    [self updateQuadForView:view frameWidth:(CGFloat)_frameWidth
                        frameHeight:(CGFloat)_frameHeight];
    /* Aspect-fit mapping: the guest rect within the view. */
    CGFloat scale;
    CGFloat fa = (CGFloat)_frameWidth / (CGFloat)(_frameHeight ?: 1);
    CGFloat va = view.width / (view.height ?: 1);
    scale = (fa > va) ? (view.width / (CGFloat)_frameWidth)
                      : (view.height / (CGFloat)_frameHeight);
    CGFloat drawW = (CGFloat)_frameWidth * scale;
    CGFloat drawH = (CGFloat)_frameHeight * scale;
    CGFloat offX = (view.width - drawW) / 2.0;
    CGFloat offY = (view.height - drawH) / 2.0;
    if (drawW <= 0 || drawH <= 0 || _frameWidth <= 0 || _frameHeight <= 0)
    {
        return CGPointMake(0, 0);
    }
    CGFloat gx = (p.x - offX) * (CGFloat)_frameWidth / drawW;
    CGFloat gy = (p.y - offY) * (CGFloat)_frameHeight / drawH;
    gx = MAX(0.0, MIN((CGFloat)_frameWidth - 1.0, gx));
    gy = MAX(0.0, MIN((CGFloat)_frameHeight - 1.0, gy));
    return CGPointMake(gx, gy);
}

- (void)sendTouch:(UITouch *)touch pressed:(BOOL)pressed
{
    CGPoint g = [self pointToGuest:touch];
    [self.engine sendPointerAtX:(int32_t)lround(g.x) y:(int32_t)lround(g.y) pressed:pressed];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    for (UITouch *t in touches)
    {
        [self sendTouch:t pressed:YES];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    for (UITouch *t in touches)
    {
        [self sendTouch:t pressed:YES];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    for (UITouch *t in touches)
    {
        [self sendTouch:t pressed:NO];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    for (UITouch *t in touches)
    {
        [self sendTouch:t pressed:NO];
    }
}

#pragma mark - Hardware keyboard (QKeyCode names)

static NSString *NXQCodeForSpecial(UIKey *key)
{
    /* Map by HID usage first (stable across layouts). */
    switch (key.keyCode)
    {
        case UIKeyboardHIDUsageKeyboardReturnOrEnter:       return @"ret";
        case UIKeyboardHIDUsageKeyboardEscape:              return @"esc";
        case UIKeyboardHIDUsageKeyboardTab:                 return @"tab";
        case UIKeyboardHIDUsageKeyboardSpacebar:            return @"spc";
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace:   return @"backspace";
        case UIKeyboardHIDUsageKeyboardDeleteForward:       return @"delete";
        case UIKeyboardHIDUsageKeyboardUpArrow:             return @"up";
        case UIKeyboardHIDUsageKeyboardDownArrow:           return @"down";
        case UIKeyboardHIDUsageKeyboardLeftArrow:           return @"left";
        case UIKeyboardHIDUsageKeyboardRightArrow:          return @"right";
        case UIKeyboardHIDUsageKeyboardHome:                return @"home";
        case UIKeyboardHIDUsageKeyboardEnd:                 return @"end";
        case UIKeyboardHIDUsageKeyboardPageUp:              return @"pgup";
        case UIKeyboardHIDUsageKeyboardPageDown:            return @"pgdn";
        default: break;
    }
    if (key.keyCode >= UIKeyboardHIDUsageKeyboardF1 && key.keyCode <= UIKeyboardHIDUsageKeyboardF12)
    {
        return [NSString stringWithFormat:@"f%lu", (unsigned long)(key.keyCode -
                                       UIKeyboardHIDUsageKeyboardF1 + 1)];
    }
    return nil;
}

static NSString *NXQCodeForCharacter(unichar c)
{
    switch (c)
    {
        case ' ':  return @"spc";
        case '\n': return @"ret";
        case '\t': return @"tab";
        case 0x08: return @"backspace";
        case '-':  return @"minus";
        case '=':  return @"equal";
        case '[':  return @"bracketleft";
        case ']':  return @"bracketright";
        case '\\': return @"backslash";
        case ';':  return @"semicolon";
        case '\'': return @"apostrophe";
        case '`':  return @"grave_accent";
        case ',':  return @"comma";
        case '.':  return @"period";
        case '/':  return @"slash";
        default:
            if (c >= 'a' && c <= 'z')
            {
                return [NSString stringWithFormat:@"%C", c];
            }
            if (c >= 'A' && c <= 'Z')
            {
                return [NSString stringWithFormat:@"%C", (unichar)(c - 'A' + 'a')];
            }
            if (c >= '0' && c <= '9')
            {
                return [NSString stringWithFormat:@"%C", c];
            }
            return nil;
    }
}

- (void)handleKeyPresses:(NSSet<UIPress *> *)presses down:(BOOL)down
{
    for (UIPress *press in presses)
    {
        UIKey *key = press.key;
        NSString *qcode = nil;
        if (key != nil)
        {
            qcode = NXQCodeForSpecial(key);
            if (qcode == nil && key.charactersIgnoringModifiers.length > 0)
            {
                qcode = NXQCodeForCharacter([key.charactersIgnoringModifiers characterAtIndex:0]);
            }
        }
        if (qcode != nil)
        {
            [self.engine sendKey:qcode down:down];
        }
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    [super pressesBegan:presses withEvent:event];
    [self handleKeyPresses:presses down:YES];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    [super pressesEnded:presses withEvent:event];
    [self handleKeyPresses:presses down:NO];
}

@end