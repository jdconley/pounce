import AuthenticationServices
import PounceKit
import SwiftUI
import UIKit

enum AppleSignInError: Error, Equatable {
    /// The person closed Apple's sheet.
    case cancelled
    case failed
}

/// Gets a Sign in with Apple proof for the server (spec §4.6, §13.1).
@MainActor
protocol AppleSigning {
    func proof() async throws -> AppleProof
}

/// AuthenticationServices: no scopes (no email, no name), a fresh nonce every time. Apple gets
/// the nonce's SHA-256 hex; the server gets the raw nonce and checks it against the token.
@MainActor
final class LiveAppleSignIn: NSObject, AppleSigning, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var pending: CheckedContinuation<AppleProof, any Error>?
    private var nonce = ""

    func proof() async throws -> AppleProof {
        pending?.resume(throwing: AppleSignInError.cancelled)
        nonce = Nonce.raw()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = Nonce.sha256Hex(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleProof, any Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            guard let token else { return finish(.failure(AppleSignInError.failed)) }
            finish(.success(AppleProof(identityToken: token, nonce: nonce, authorizationCode: code)))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        MainActor.assumeIsolated {
            finish(.failure(cancelled ? AppleSignInError.cancelled : AppleSignInError.failed))
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            // A sign-in only starts from a button on screen, so a scene is always there.
            guard let scene = scenes.first else { preconditionFailure("a sign-in with no window scene") }
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}

#if DEBUG
/// `-stub-accounts`: a made-up proof (the stub service takes anything), or a cancel.
struct StubAppleSignIn: AppleSigning {
    let scenario: StubScenario

    func proof() async throws -> AppleProof {
        try await Task.sleep(for: .milliseconds(100))
        if scenario == .cancel { throw AppleSignInError.cancelled }
        return AppleProof(identityToken: "stub.token.sig", nonce: Nonce.raw(), authorizationCode: nil)
    }
}
#endif

/// Apple's own Sign in with Apple button (its text is the one sentence allowed on screen). The
/// tap runs `action`, which drives the request, so a Debug stub can stand in for Apple.
struct AppleSignInButton: UIViewRepresentable {
    let identifier: String
    var style: ASAuthorizationAppleIDButton.Style = .black
    var cornerRadius: CGFloat = 28
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: style)
        button.cornerRadius = cornerRadius
        button.accessibilityIdentifier = identifier
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @MainActor @objc func tapped() { action() }
    }
}
