/*
 SPDX-License-Identifier: GPL-2.0-or-later

 See NXGuestImageManager.h. The download, SHA-256 verification, and on-device
 XZ decompression all run against the single pin in guest-images.lock.tsv, so
 the prepare script (CI/local) and the ROM host can never drift apart.
*/

#import "NXGuestImageManager.h"
#import "xzfile.h"

#import <CommonCrypto/CommonCrypto.h>

NSString * const NXGuestImageErrorDomain = @"org.emexlabs.rom.postmarketos.guest-image";

/* Keep in sync with pmos/guest-images.lock.tsv (the prepare script sources
   the same file directly). */
static NSString * const NXGuestImageName     = @"postmarketos.img.xz";
static NSString * const NXGuestImageSHA256   = @"1d7a5104e4ada62e229293ebeb4c1154b50eccf8810e7f941fbb50af33fcf522";
static NSString * const NXGuestImageURLString = @"https://images.nura.eco/bpo/v25.12/generic-x86_64/phosh/20260803-0207/20260803-0207-postmarketOS-v25.12-phosh-25-generic-x86_64-lts.img.xz";

static NSString * const NXGuestTargetName = @"postmarketos.img";
static NSString * const NXGuestMarkerName = @".postmarketos.img.staged";

static NSError *NXGuestImageError(NXGuestImageErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:NXGuestImageErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

/* Streaming SHA-256 of a file on disk (Swift-free, CommonCrypto). */
static NSString *NXSHA256OfFile(NSString *path)
{
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (fh == nil)
    {
        return nil;
    }
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    while (YES)
    {
        @autoreleasepool
        {
            NSData *chunk = [fh readDataOfLength:1u << 16];
            if (chunk.length == 0)
            {
                break;
            }
            CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [fh closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
    {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

/* C-function bridge: the XZ driver reports progress through a plain C
   pointer, hop to the main queue before touching the ObjC side. */
static void NXGuestImageXZProgress(void *ctx,
                                   unsigned long long consumed,
                                   unsigned long long total,
                                   unsigned long long produced __unused)
{
    NXGuestImageManager *manager = (__bridge NXGuestImageManager *)ctx;
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager reportXZProgress:consumed total:total];
    });
}

@interface NXGuestImageManager () <NSURLSessionDownloadDelegate>

@property (nonatomic, copy) void (^progressHandler)(NSString *phase, double progress);
@property (nonatomic, copy) void (^completionHandler)(NSError * _Nullable error);
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, assign) BOOL cancelled;

@end

@implementation NXGuestImageManager

- (instancetype)initWithSlotURL:(NSURL *)slotURL
{
    self = [super init];
    if (self)
    {
        _slotURL = slotURL;
    }
    return self;
}

#pragma mark - Paths

- (NSString *)guestDir
{
    return [self.slotURL.path stringByAppendingPathComponent:@"guest"];
}

- (NSString *)downloadPath
{
    return [self.guestDir stringByAppendingPathComponent:NXGuestImageName];
}

- (NSString *)partialPath
{
    return [self.guestDir stringByAppendingPathComponent:@"postmarketos.img.xz.part"];
}

- (NSString *)targetPath
{
    return [self.guestDir stringByAppendingPathComponent:NXGuestTargetName];
}

- (NSString *)markerPath
{
    return [self.guestDir stringByAppendingPathComponent:NXGuestMarkerName];
}

#pragma mark - State

- (BOOL)hasPinnedImage
{
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:self.targetPath] && [fm fileExistsAtPath:self.markerPath];
}

- (nullable NSString *)stagedImagePath
{
    return [self hasPinnedImage] ? self.targetPath : nil;
}

#pragma mark - Flow

- (void)beginWithProgress:(void (^)(NSString *, double))progress
               completion:(void (^)(NSError *))completion
{
    self.progressHandler = progress;
    self.completionHandler = completion;
    self.cancelled = NO;

    if (self.hasPinnedImage)
    {
        [self finishWithError:nil];
        return;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 300;
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                 delegate:self
                                            delegateQueue:nil];
    self.task = [self.session downloadTaskWithURL:[NSURL URLWithString:NXGuestImageURLString]];
    [self.task resume];
}

- (void)cancel
{
    self.cancelled = YES;
    [self.task cancel];
}

- (void)finishWithError:(NSError * _Nullable)error
{
    void (^done)(NSError *) = self.completionHandler;
    self.progressHandler = nil;
    self.completionHandler = nil;
    self.task = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    if (done)
    {
        done(error);
    }
}

- (void)emitProgress:(NSString *)phase fraction:(double)fraction
{
    if (self.progressHandler)
    {
        self.progressHandler(phase, fraction);
    }
}

- (void)reportXZProgress:(unsigned long long)consumed total:(unsigned long long)total
{
    double fraction = (total > 0) ? (double)consumed / (double)total : 1.0;
    [self emitProgress:@"decompressing" fraction:MIN(1.0, fraction)];
}

#pragma mark - URLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    double fraction = -1.0;
    if (totalBytesExpectedToWrite > 0)
    {
        fraction = MIN(1.0, (double)totalBytesWritten / (double)totalBytesExpectedToWrite);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self emitProgress:@"downloading" fraction:fraction];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.guestDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSError *moveError = nil;
    if (![fm moveItemAtURL:location
                     toURL:[NSURL fileURLWithPath:self.downloadPath]
                     error:&moveError])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithError:NXGuestImageError(NXGuestImageErrorDownload,
                                                    moveError.localizedDescription ?: @"could not store the downloaded image")];
        });
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self verifyAndStage];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error == nil)
    {
        return; /* success path is handled in didFinishDownloadingToURL: */
    }
    if (self.cancelled)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithError:NXGuestImageError(NXGuestImageErrorCancelled, @"cancelled")];
        });
        return;
    }
    NSInteger code = (error.code == NSURLErrorCancelled) ? NXGuestImageErrorCancelled : NXGuestImageErrorDownload;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishWithError:NXGuestImageError(code, error.localizedDescription)];
    });
}

#pragma mark - Stage

- (void)verifyAndStage
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self emitProgress:@"verifying" fraction:-1.0];
    });

    NSString *actual = NXSHA256OfFile(self.downloadPath);
    if (![actual.lowercaseString isEqualToString:[NXGuestImageSHA256 lowercaseString]])
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadPath error:nil];
        NSError *error = NXGuestImageError(NXGuestImageErrorVerify,
                                           @"SHA-256 mismatch: the downloaded image does not match the pinned lockfile entry");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithError:error];
        });
        return;
    }

    int rc = xzfile_extract(self.downloadPath.fileSystemRepresentation,
                            self.targetPath.fileSystemRepresentation,
                            NXGuestImageXZProgress,
                            (__bridge void *)self);
    if (rc != XZ_ERR_OK)
    {
        NSError *error = NXGuestImageError(NXGuestImageErrorDecompress,
                                           [NSString stringWithFormat:@"decompression failed (xz error %d)", rc]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithError:error];
        });
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.guestDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createFileAtPath:self.markerPath contents:[NSData data] attributes:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self emitProgress:@"ready" fraction:1.0];
        [self finishWithError:nil];
    });
}

@end