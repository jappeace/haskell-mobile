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
#import <os/log.h>
#include "CameraBridge.h"

#define LOG_TAG "CameraBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches camera result back to Haskell callback) */
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                    int32_t statusCode, const char *filePath);

/* ---- Camera delegate ---- */

@interface CameraDelegate : NSObject <AVCapturePhotoCaptureDelegate,
                                       AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property (nonatomic, assign) int32_t photoRequestId;
@property (nonatomic, assign) int32_t videoRequestId;
@end

@implementation CameraDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
    if (error) {
        LOGE("Photo capture error: %{public}@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                                   CAMERA_ERROR, NULL);
        });
        return;
    }

    NSData *data = [photo fileDataRepresentation];
    if (!data) {
        LOGE("Photo capture: no data representation");
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                                   CAMERA_ERROR, NULL);
        });
        return;
    }

    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"capture_%d.jpg", self.photoRequestId];
    NSString *filePath = [tempDir stringByAppendingPathComponent:fileName];
    [data writeToFile:filePath atomically:YES];

    LOGI("Photo saved: %{public}@", filePath);
    const char *cpath = [filePath UTF8String];
    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnCameraResult(self.haskellCtx, self.photoRequestId,
                               CAMERA_SUCCESS, cpath);
    });
}

- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
                        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                                  error:(NSError *)error {
    if (error) {
        LOGE("Video capture error: %{public}@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnCameraResult(self.haskellCtx, self.videoRequestId,
                                   CAMERA_ERROR, NULL);
        });
        return;
    }

    NSString *filePath = [outputFileURL path];
    LOGI("Video saved: %{public}@", filePath);
    const char *cpath = [filePath UTF8String];
    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnCameraResult(self.haskellCtx, self.videoRequestId,
                               CAMERA_SUCCESS, cpath);
    });
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
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *d in devices) {
        if (d.position == position) {
            device = d;
            break;
        }
    }
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

    /* Movie file output */
    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:movieOutput]) {
        [session addOutput:movieOutput];
    }
    g_delegate.movieOutput = movieOutput;

    g_delegate.captureSession = session;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [session startRunning];
        LOGI("Camera session started");
    });
}

static void ios_camera_stop_session(void)
{
    LOGI("ios_camera_stop_session()");

    if (g_delegate && g_delegate.captureSession) {
        [g_delegate.captureSession stopRunning];
        g_delegate.captureSession = nil;
        g_delegate.photoOutput = nil;
        g_delegate.movieOutput = nil;
    }
}

static void ios_camera_capture_photo(void *ctx, int32_t requestId)
{
    LOGI("ios_camera_capture_photo(requestId=%d)", requestId);

    if (!g_delegate || !g_delegate.photoOutput ||
        !g_delegate.captureSession || !g_delegate.captureSession.isRunning) {
        LOGE("capture_photo: no active session");
        haskellOnCameraResult(ctx, requestId, CAMERA_ERROR, NULL);
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

    if (!g_delegate || !g_delegate.movieOutput ||
        !g_delegate.captureSession || !g_delegate.captureSession.isRunning) {
        LOGE("start_video: no active session");
        haskellOnCameraResult(ctx, requestId, CAMERA_ERROR, NULL);
        return;
    }

    g_delegate.haskellCtx = ctx;
    g_delegate.videoRequestId = requestId;

    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"video_%d.mov", requestId];
    NSString *filePath = [tempDir stringByAppendingPathComponent:fileName];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    [g_delegate.movieOutput startRecordingToOutputFileURL:fileURL
                                        recordingDelegate:g_delegate];
}

static void ios_camera_stop_video(void)
{
    LOGI("ios_camera_stop_video()");

    if (g_delegate && g_delegate.movieOutput &&
        g_delegate.movieOutput.isRecording) {
        [g_delegate.movieOutput stopRecording];
    }
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
