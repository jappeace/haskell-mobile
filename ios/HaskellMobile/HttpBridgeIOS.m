/*
 * iOS implementation of the HTTP bridge callback.
 *
 * Uses NSURLSession to perform HTTP requests on a background queue,
 * then dispatches results back to Haskell on the main thread via
 * dispatch_async(dispatch_get_main_queue(), ...).
 * Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks run on the main thread.
 */

#import <Foundation/Foundation.h>
#import <os/log.h>
#include "HttpBridge.h"

#define LOG_TAG "HttpBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnHttpResult(void *ctx, int32_t requestId,
                                 int32_t resultCode, int32_t httpStatus,
                                 const char *headers,
                                 const char *body, int32_t bodyLen);

/* ---- Global state ---- */
static void *g_haskell_ctx = NULL;

/* ---- HTTP method string from integer code ---- */

static NSString *httpMethodString(int32_t method) {
    switch (method) {
        case HTTP_METHOD_GET:    return @"GET";
        case HTTP_METHOD_POST:   return @"POST";
        case HTTP_METHOD_PUT:    return @"PUT";
        case HTTP_METHOD_DELETE: return @"DELETE";
        default:                 return @"GET";
    }
}

/* ---- HTTP bridge implementation ---- */

static void ios_http_request(void *ctx, int32_t requestId, int32_t method,
                              const char *url, const char *headers,
                              const char *body, int32_t bodyLen)
{
    LOGI("http_request(method=%d, url=\"%{public}s\", id=%d)", method, url, requestId);

    /* In autotest mode, return stub success without making a real request.
     * CI simulators may not have network access to arbitrary hosts. */
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    if ([args containsObject:@"--autotest-buttons"] || [args containsObject:@"--autotest"]) {
        LOGI("http_request: autotest mode -- returning stub success");
        const char *stubHeaders = "Content-Type: text/plain\n";
        const char *stubBody = "";
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnHttpResult(ctx, requestId, HTTP_RESULT_SUCCESS, 200,
                                stubHeaders, stubBody, 0);
        });
        return;
    }

    NSString *nsUrl = [NSString stringWithUTF8String:url];
    NSURL *nsURL = [NSURL URLWithString:nsUrl];
    if (!nsURL) {
        LOGE("http_request: invalid URL \"%{public}s\"", url);
        dispatch_async(dispatch_get_main_queue(), ^{
            haskellOnHttpResult(ctx, requestId, HTTP_RESULT_NETWORK_ERROR, 0,
                                NULL, NULL, 0);
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsURL];
    [request setHTTPMethod:httpMethodString(method)];
    [request setTimeoutInterval:30.0];

    /* Parse and set headers (newline-delimited "Key: Value\n") */
    if (headers) {
        NSString *nsHeaders = [NSString stringWithUTF8String:headers];
        NSArray<NSString *> *lines = [nsHeaders componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if (line.length == 0) continue;
            NSRange colonRange = [line rangeOfString:@": "];
            if (colonRange.location != NSNotFound) {
                NSString *key = [line substringToIndex:colonRange.location];
                NSString *value = [line substringFromIndex:colonRange.location + colonRange.length];
                [request setValue:value forHTTPHeaderField:key];
            }
        }
    }

    /* Set body */
    if (body && bodyLen > 0) {
        [request setHTTPBody:[NSData dataWithBytes:body length:bodyLen]];
    }

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                LOGE("http_request: error %{public}@", [error localizedDescription]);
                int32_t resultCode = HTTP_RESULT_NETWORK_ERROR;
                if (error.code == NSURLErrorTimedOut) {
                    resultCode = HTTP_RESULT_TIMEOUT;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    haskellOnHttpResult(ctx, requestId, resultCode, 0,
                                        NULL, NULL, 0);
                });
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            int32_t httpStatus = (int32_t)[httpResponse statusCode];

            /* Serialize response headers as newline-delimited "Key: Value\n" */
            NSDictionary<NSString *, NSString *> *respHeaders = [httpResponse allHeaderFields];
            NSMutableString *headerStr = [NSMutableString string];
            for (NSString *key in respHeaders) {
                [headerStr appendFormat:@"%@: %@\n", key, respHeaders[key]];
            }
            const char *cHeaders = [headerStr UTF8String];

            const char *cBody = data ? [data bytes] : NULL;
            int32_t cBodyLen = data ? (int32_t)[data length] : 0;

            LOGI("http_request: response status=%d, bodyLen=%d", httpStatus, cBodyLen);

            dispatch_async(dispatch_get_main_queue(), ^{
                haskellOnHttpResult(ctx, requestId, HTTP_RESULT_SUCCESS,
                                    httpStatus, cHeaders, cBody, cBodyLen);
            });
        }];

    [task resume];
}

/* ---- Public API ---- */

/*
 * Set up the iOS HTTP bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_http_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.haskellmobile", LOG_TAG);
    g_haskell_ctx = haskellCtx;

    http_register_impl(ios_http_request);

    LOGI("iOS HTTP bridge initialized");
}
