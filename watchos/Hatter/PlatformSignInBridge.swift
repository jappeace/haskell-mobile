import Foundation
import AuthenticationServices
import os.log

/// watchOS platform sign-in bridge -- uses ASAuthorizationAppleIDProvider
/// for Sign in with Apple. Google Sign-In returns an error (not available
/// on watchOS).
///
/// On watchOS, ASAuthorizationController is presented automatically
/// without needing a presentation context provider.

private let bridgeLog = OSLog(subsystem: "me.jappie.hatter", category: "PlatformSignInBridge")

/// Delegate for ASAuthorizationController, retained globally during flow.
private class PlatformSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    let haskellCtx: UnsafeMutableRawPointer?
    let requestId: Int32

    init(ctx: UnsafeMutableRawPointer?, requestId: Int32) {
        self.haskellCtx = ctx
        self.requestId = requestId
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            var identityToken: String? = nil
            if let tokenData = appleCredential.identityToken {
                identityToken = String(data: tokenData, encoding: .utf8)
            }

            let userId = appleCredential.user

            let email = appleCredential.email

            var fullName: String? = nil
            if let nameComponents = appleCredential.fullName {
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: nameComponents)
                if !formatted.isEmpty {
                    fullName = formatted
                }
            }

            os_log("platform_sign_in: Apple success userId=%{public}@",
                   log: bridgeLog, type: .info, userId)

            let cToken = identityToken.flatMap { $0.withCString { UnsafePointer(strdup($0)) } }
            userId.withCString { cUserId in
                let cEmail = email.flatMap { $0.withCString { UnsafePointer(strdup($0)) } }
                let cFullName = fullName.flatMap { $0.withCString { UnsafePointer(strdup($0)) } }
                haskellOnPlatformSignInResult(haskellCtx, requestId,
                                               0 /* SUCCESS */,
                                               cToken, cUserId,
                                               cEmail, cFullName,
                                               0 /* APPLE */)
                if let p = cToken { free(UnsafeMutablePointer(mutating: p)) }
                if let p = cEmail { free(UnsafeMutablePointer(mutating: p)) }
                if let p = cFullName { free(UnsafeMutablePointer(mutating: p)) }
            }
        }
        activeDelegate = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            os_log("platform_sign_in: cancelled", log: bridgeLog, type: .info)
            haskellOnPlatformSignInResult(haskellCtx, requestId,
                                           1 /* CANCELLED */,
                                           nil, nil, nil, nil,
                                           0 /* APPLE */)
        } else {
            let errorMsg = error.localizedDescription
            os_log("platform_sign_in: error %{public}@",
                   log: bridgeLog, type: .error, errorMsg)
            errorMsg.withCString { cErr in
                haskellOnPlatformSignInResult(haskellCtx, requestId,
                                               2 /* ERROR */,
                                               nil, nil, nil, cErr,
                                               0 /* APPLE */)
            }
        }
        activeDelegate = nil
    }
}

/// Prevent ARC deallocation during active flow.
private var activeDelegate: PlatformSignInDelegate? = nil

@_cdecl("watchos_platform_sign_in_start")
func watchosPlatformSignInStart(_ ctx: UnsafeMutableRawPointer?,
                                 _ requestId: Int32,
                                 _ provider: Int32) {
    os_log("platform_sign_in_start(provider=%d, id=%d)",
           log: bridgeLog, type: .info, provider, requestId)

    /* Google Sign-In not available on watchOS */
    if provider == 1 /* GOOGLE */ {
        os_log("platform_sign_in_start: Google Sign-In not available on watchOS",
               log: bridgeLog, type: .error)
        "Google Sign-In not available on watchOS".withCString { cErr in
            haskellOnPlatformSignInResult(ctx, requestId,
                                           2 /* ERROR */,
                                           nil, nil, nil, cErr,
                                           1 /* GOOGLE */)
        }
        return
    }

    /* In autotest mode, return stub credentials without showing real UI. */
    let args = ProcessInfo.processInfo.arguments
    if args.contains("--autotest-buttons") || args.contains("--autotest") {
        os_log("platform_sign_in_start: autotest mode -- returning stub Apple credentials",
               log: bridgeLog, type: .info)
        "WATCHOS_AUTOTEST_APPLE_TOKEN".withCString { cToken in
            "apple-autotest-001".withCString { cUserId in
                "autotest@privaterelay.appleid.com".withCString { cEmail in
                    "Autotest User".withCString { cFullName in
                        haskellOnPlatformSignInResult(ctx, requestId,
                                                       0 /* SUCCESS */,
                                                       cToken, cUserId,
                                                       cEmail, cFullName,
                                                       0 /* APPLE */)
                    }
                }
            }
        }
        return
    }

    /* Create Apple ID request */
    let appleIDProvider = ASAuthorizationAppleIDProvider()
    let request = appleIDProvider.createRequest()
    request.requestedScopes = [.fullName, .email]

    let delegate = PlatformSignInDelegate(ctx: ctx, requestId: requestId)
    activeDelegate = delegate

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = delegate

    controller.performRequests()
}
