/*
 * iOS implementation of the camera bridge callbacks.
 *
 * Uses AVFoundation (AVCaptureSession + AVCapturePhotoOutput +
 * AVCaptureMovieFileOutput) to manage camera sessions and capture.
 * Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks are dispatched on the main thread.
 */

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <os/log.h>
#include "CameraBridge.h"

#define LOG_TAG "CameraBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI exports (dispatches camera results back to Haskell callbacks) */
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                    int32_t statusCode,
                                    const uint8_t *imageData, int32_t imageDataLen,
                                    int32_t width, int32_t height);
extern void haskellOnVideoFrame(void *ctx, int32_t requestId,
                                 const uint8_t *frameData, int32_t frameDataLen,
                                 int32_t width, int32_t height);
extern void haskellOnAudioChunk(void *ctx, int32_t requestId,
                                 const uint8_t *audioData, int32_t audioDataLen);

/* ---- Camera delegate ---- */

@interface CameraDelegate : NSObject <AVCapturePhotoCaptureDelegate,
                                       AVCaptureVideoDataOutputSampleBufferDelegate,
                                       AVCaptureAudioDataOutputSampleBufferDelegate>
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoQueue;
@property (nonatomic, strong) dispatch_queue_t audioQueue;
@property (nonatomic, assign) int32_t photoRequestId;
@property (nonatomic, assign) int32_t videoRequestId;
@property (nonatomic, assign) BOOL videoRecording;
@end

@implementation CameraDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
    if (error) {
        LOGE("Photo capture error: %{public}@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                                   CAMERA_ERROR, NULL, 0, 0, 0);
        });
        return;
    }

    NSData *data = [photo fileDataRepresentation];
    if (!data) {
        LOGE("Photo capture: no data representation");
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                                   CAMERA_ERROR, NULL, 0, 0, 0);
        });
        return;
    }

    CMVideoDimensions dimensions = photo.resolvedSettings.photoDimensions;
    int32_t imgWidth = dimensions.width;
    int32_t imgHeight = dimensions.height;

    LOGI("Photo captured: %dx%d, %lu bytes",
         imgWidth, imgHeight, (unsigned long)[data length]);
    const uint8_t *imgBytes = (const uint8_t *)[data bytes];
    int32_t imgLen = (int32_t)[data length];
    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                               CAMERA_SUCCESS,
                               imgBytes, imgLen, imgWidth, imgHeight);
    });
}

/* Video/audio sample buffer delegate for per-frame/per-chunk push */
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    if (!self.videoRecording) return;

    if (output == self.videoDataOutput) {
        /* Convert video frame to JPEG data */
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) return;

        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
        CIContext *ciContext = [CIContext context];
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        NSData *jpegData = [ciContext JPEGRepresentationOfImage:ciImage
                                                     colorSpace:colorSpace
                                                        options:@{}];
        CGColorSpaceRelease(colorSpace);
        if (!jpegData) return;

        size_t imgWidth = CVPixelBufferGetWidth(imageBuffer);
        size_t imgHeight = CVPixelBufferGetHeight(imageBuffer);

        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnVideoFrame(self.haskellCtx, self.videoRequestId,
                                 (const uint8_t *)[jpegData bytes],
                                 (int32_t)[jpegData length],
                                 (int32_t)imgWidth, (int32_t)imgHeight);
        });
    } else if (output == self.audioDataOutput) {
        /* Extract PCM audio data */
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        if (!blockBuffer) return;

        size_t length = 0;
        char *dataPointer = NULL;
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &length, &dataPointer);
        if (status != noErr || !dataPointer) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnAudioChunk(self.haskellCtx, self.videoRequestId,
                                 (const uint8_t *)dataPointer, (int32_t)length);
        });
    }
}

@end

static CameraDelegate *g_delegate = nil;

/* ---- Camera bridge implementations ---- */

static void ios_camera_start_session(void *ctx, int32_t source)
{
    LOGI("ios_camera_start_session(source=%d)", source);

    if (!g_delegate) {
        g_delegate = [[CameraDelegate alloc] init];
    }
    g_delegate.haskellCtx = ctx;

    /* Stop any existing session */
    if (g_delegate.captureSession && g_delegate.captureSession.isRunning) {
        [g_delegate.captureSession stopRunning];
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetPhoto;

    AVCaptureDevicePosition position = (source == CAMERA_SOURCE_FRONT)
        ? AVCaptureDevicePositionFront
        : AVCaptureDevicePositionBack;

    AVCaptureDevice *device = nil;
    AVCaptureDeviceDiscoverySession *discoverySession =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                                                              mediaType:AVMediaTypeVideo
                                                               position:position];
    device = discoverySession.devices.firstObject;
    if (!device) {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    if (!device) {
        LOGE("No camera device available");
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error || !input) {
        LOGE("Failed to create camera input: %{public}@",
             error ? error.localizedDescription : @"unknown");
        return;
    }

    if ([session canAddInput:input]) {
        [session addInput:input];
    }

    /* Photo output */
    AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
    if ([session canAddOutput:photoOutput]) {
        [session addOutput:photoOutput];
    }
    g_delegate.photoOutput = photoOutput;

    /* Video data output for per-frame push */
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoDataOutput.videoSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
    videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    g_delegate.videoQueue = dispatch_queue_create("me.jappie.haskellmobile.videoQueue",
                                                    DISPATCH_QUEUE_SERIAL);
    if ([session canAddOutput:videoDataOutput]) {
        [session addOutput:videoDataOutput];
    }
    g_delegate.videoDataOutput = videoDataOutput;

    /* Audio data output for per-chunk push */
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (audioDevice) {
        NSError *audioError = nil;
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                                 error:&audioError];
        if (audioInput && [session canAddInput:audioInput]) {
            [session addInput:audioInput];
        }

        AVCaptureAudioDataOutput *audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        g_delegate.audioQueue = dispatch_queue_create("me.jappie.haskellmobile.audioQueue",
                                                        DISPATCH_QUEUE_SERIAL);
        if ([session canAddOutput:audioDataOutput]) {
            [session addOutput:audioDataOutput];
        }
        g_delegate.audioDataOutput = audioDataOutput;
    }

    g_delegate.captureSession = session;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [session startRunning];
        LOGI("Camera session started");
    });
}

static void ios_camera_stop_session(void)
{
    LOGI("ios_camera_stop_session()");

    if (g_delegate) {
        g_delegate.videoRecording = NO;
        if (g_delegate.captureSession) {
            [g_delegate.captureSession stopRunning];
            g_delegate.captureSession = nil;
        }
        g_delegate.photoOutput = nil;
        g_delegate.videoDataOutput = nil;
        g_delegate.audioDataOutput = nil;
    }
}

static void ios_camera_capture_photo(void *ctx, int32_t requestId)
{
    LOGI("ios_camera_capture_photo(requestId=%d)", requestId);

    if (!g_delegate || !g_delegate.photoOutput ||
        !g_delegate.captureSession || !g_delegate.captureSession.isRunning) {
        LOGE("capture_photo: no active session");
        haskellOnCameraResult(ctx, requestId, CAMERA_ERROR, NULL, 0, 0, 0);
        return;
    }

    g_delegate.haskellCtx = ctx;
    g_delegate.photoRequestId = requestId;

    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    [g_delegate.photoOutput capturePhotoWithSettings:settings delegate:g_delegate];
}

static void ios_camera_start_video(void *ctx, int32_t requestId)
{
    LOGI("ios_camera_start_video(requestId=%d)", requestId);

    if (!g_delegate || !g_delegate.videoDataOutput ||
        !g_delegate.captureSession || !g_delegate.captureSession.isRunning) {
        LOGE("start_video: no active session");
        haskellOnCameraResult(ctx, requestId, CAMERA_ERROR, NULL, 0, 0, 0);
        return;
    }

    g_delegate.haskellCtx = ctx;
    g_delegate.videoRequestId = requestId;
    g_delegate.videoRecording = YES;

    /* Attach sample buffer delegates to start receiving frames/audio */
    [g_delegate.videoDataOutput setSampleBufferDelegate:g_delegate
                                                  queue:g_delegate.videoQueue];
    if (g_delegate.audioDataOutput) {
        [g_delegate.audioDataOutput setSampleBufferDelegate:g_delegate
                                                      queue:g_delegate.audioQueue];
    }
}

static void ios_camera_stop_video(void)
{
    LOGI("ios_camera_stop_video()");

    if (!g_delegate) return;

    g_delegate.videoRecording = NO;

    /* Remove sample buffer delegates */
    if (g_delegate.videoDataOutput) {
        [g_delegate.videoDataOutput setSampleBufferDelegate:nil queue:nil];
    }
    if (g_delegate.audioDataOutput) {
        [g_delegate.audioDataOutput setSampleBufferDelegate:nil queue:nil];
    }

    /* Fire completion callback */
    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnCameraResult(g_delegate.haskellCtx, g_delegate.videoRequestId,
                               CAMERA_SUCCESS, NULL, 0, 0, 0);
    });
}

/* ---- Public API ---- */

/*
 * Set up the iOS camera bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_camera_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.haskellmobile", LOG_TAG);

    camera_register_impl(ios_camera_start_session,
                          ios_camera_stop_session,
                          ios_camera_capture_photo,
                          ios_camera_start_video,
                          ios_camera_stop_video);

    LOGI("iOS camera bridge initialized");
}
