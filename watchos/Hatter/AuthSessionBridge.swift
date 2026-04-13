import Foundation
import AuthenticationServices
import os.log

/// watchOS auth session bridge — uses ASWebAuthenticationSession
/// to open the system browser for OAuth2/PKCE flows.
///
/// On watchOS, ASWebAuthenticationSession is presented automatically
/// without needing a presentation context provider.

private let bridgeLog = OSLog(subsystem: "me.jappie.hatter", category: "AuthSessionBridge")

/// Prevent ARC deallocation during active session.
private var activeSession: ASWebAuthenticationSession? = nil

@_cdecl("watchos_auth_session_start")
func watchosAuthSessionStart(_ ctx: UnsafeMutableRawPointer?,
                              _ requestId: Int32,
                              _ authUrl: UnsafePointer<CChar>?,
                              _ callbackScheme: UnsafePointer<CChar>?) {
    guard let authUrl = authUrl, let callbackScheme = callbackScheme else {
        os_log("auth_session_start: nil url or scheme (id=%d)", log: bridgeLog, type: .error, requestId)
        "auth_session_start: nil url or scheme".withCString { errorMsg in
            haskellOnAuthSessionResult(ctx, requestId, 2 /* ERROR */, nil, errorMsg)
        }
        return
    }

    let urlString = String(cString: authUrl)
    let scheme = String(cString: callbackScheme)

    os_log("auth_session_start(url=\"%{public}s\", scheme=\"%{public}s\", id=%d)",
           log: bridgeLog, type: .info, urlString, scheme, requestId)

    // In autotest mode, return stub success without opening the browser.
    // CI simulators cannot interact with ASWebAuthenticationSession.
    let args = ProcessInfo.processInfo.arguments
    if args.contains("--autotest-buttons") || args.contains("--autotest") {
        os_log("auth_session_start: autotest mode — returning stub success",
               log: bridgeLog, type: .info)
        let stubUrl = "\(scheme)://callback?code=WATCHOS_AUTOTEST_CODE&state=test"
        stubUrl.withCString { cStubUrl in
            haskellOnAuthSessionResult(ctx, requestId, 0 /* SUCCESS */, cStubUrl, nil)
        }
        return
    }

    guard let nsUrl = URL(string: urlString) else {
        os_log("auth_session_start: invalid URL (id=%d)", log: bridgeLog, type: .error, requestId)
        "invalid auth URL".withCString { errorMsg in
            haskellOnAuthSessionResult(ctx, requestId, 2 /* ERROR */, nil, errorMsg)
        }
        return
    }

    let session = ASWebAuthenticationSession(
        url: nsUrl,
        callbackURLScheme: scheme
    ) { callbackURL, error in
        if let callbackURL = callbackURL {
            os_log("auth_session_start: success url=%{public}@",
                   log: bridgeLog, type: .info, callbackURL.absoluteString)
            callbackURL.absoluteString.withCString { cUrl in
                haskellOnAuthSessionResult(ctx, requestId, 0 /* SUCCESS */, cUrl, nil)
            }
        } else if let error = error as NSError?,
                  error.domain == ASWebAuthenticationSessionErrorDomain,
                  error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            os_log("auth_session_start: cancelled", log: bridgeLog, type: .info)
            haskellOnAuthSessionResult(ctx, requestId, 1 /* CANCELLED */, nil, nil)
        } else {
            let errorMsg = error?.localizedDescription ?? "unknown error"
            os_log("auth_session_start: error %{public}@",
                   log: bridgeLog, type: .error, errorMsg)
            errorMsg.withCString { cErr in
                haskellOnAuthSessionResult(ctx, requestId, 2 /* ERROR */, nil, cErr)
            }
        }
        activeSession = nil
    }

    activeSession = session

    if !session.start() {
        os_log("auth_session_start: failed to start session", log: bridgeLog, type: .error)
        "failed to start auth session".withCString { errorMsg in
            haskellOnAuthSessionResult(ctx, requestId, 2 /* ERROR */, nil, errorMsg)
        }
        activeSession = nil
    }
}
