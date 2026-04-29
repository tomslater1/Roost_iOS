import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthManager {
    var currentUser: AuthUser?
    var currentSession: AuthSession?
    var homeId: UUID?
    var hasHome: Bool?
    var isRestoringSession = true
    var pendingJoinCode: String?
    /// True only after a *fresh* sign-in (not session restore). Consumed by ContentView
    /// to show the one-shot AuthLoadingView; reset when the cover dismisses.
    var isNewSignIn = false

    @ObservationIgnored
    private var authStateTask: Task<Void, Never>?

    @ObservationIgnored
    private let homeService = HomeService()

    var isAuthenticated: Bool {
        currentSession != nil
    }

    func startSessionListener() {
        guard authStateTask == nil else { return }

        authStateTask = Task { [weak self] in
            guard
                let self,
                let client = try? SupabaseClientProvider.shared.requireClient()
            else {
                self?.clearSessionState()
                return
            }

            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                await self.applyAuthStateChange(event: event, session: session)
            }
        }
    }

    func handle(url: URL) {
        // Handle OAuth callbacks (roost-ios://auth/callback)
        if url.host == "auth" {
            Task {
                guard let client = try? SupabaseClientProvider.shared.requireClient() else { return }
                _ = try? await client.auth.session(from: url)
            }
            return
        }

        // Handle join deep links (roost-ios://join?code=<code>)
        if url.host == "join",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let raw = components.queryItems?.first(where: { $0.name == "code" })?.value {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            guard !code.isEmpty,
                  (4...32).contains(code.count),
                  code.unicodeScalars.allSatisfy({ validChars.contains($0) }) else { return }
            pendingJoinCode = code
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func applyAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let session else {
                clearSessionState()
                return
            }

            currentSession = AuthSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
            currentUser = AuthUser(
                id: session.user.id,
                email: session.user.email ?? "",
                displayName: session.user.userMetadata["display_name"]?.stringValue
            )
            isRestoringSession = false
            if event == .signedIn {
                isNewSignIn = true
            }

            // Only reset hasHome (and re-check) on initial load or fresh sign-in.
            // Token refresh / user-metadata updates should not reset hasHome — doing so
            // tears down RootAuthenticatedView and shows the loading screen again for no reason.
            if event == .initialSession || event == .signedIn || hasHome == nil {
                hasHome = nil
                await refreshHomeStatus()
            }

            // Mirror user + home into the shared App Group UserDefaults so the
            // widget extension can read current context without touching auth.
            updateSharedAppGroupContext()

        case .signedOut, .userDeleted:
            clearSessionState()
            AppGroup.Context.clearAll()

        case .passwordRecovery, .mfaChallengeVerified:
            isRestoringSession = false
        }
    }

    private func clearSessionState() {
        currentUser = nil
        currentSession = nil
        homeId = nil
        hasHome = nil
        isRestoringSession = false
        pendingJoinCode = nil
        try? SyncEngine().clearAllCachedData()
        AppGroup.Context.clearAll()
    }

    func refreshHomeStatus() async {
        do {
            homeId = try await homeService.getUserHomeID()
            hasHome = homeId != nil
        } catch {
            homeId = nil
            hasHome = false
        }
        // Keep the shared App Group context in sync whenever home status changes.
        updateSharedAppGroupContext()
    }

    /// Writes `currentUser.id`, `homeId`, and the display name into the shared
    /// App Group UserDefaults so the RoostWidgets extension can read the
    /// current auth context without hitting Supabase. Call this whenever any
    /// of those values change.
    func updateSharedAppGroupContext() {
        AppGroup.Context.currentUserID = currentUser?.id
        AppGroup.Context.currentHomeID = homeId
        AppGroup.Context.currentUserDisplayName = currentUser?.displayName
    }

    func validAccessToken() async throws -> String {
        let client = try SupabaseClientProvider.shared.requireClient()
        let session = try await client.auth.session

        currentSession = AuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
        currentUser = AuthUser(
            id: session.user.id,
            email: session.user.email ?? currentUser?.email ?? "",
            displayName: session.user.userMetadata["display_name"]?.stringValue ?? currentUser?.displayName
        )

        return session.accessToken
    }

    func consumePendingJoinCode() -> String? {
        let code = pendingJoinCode
        pendingJoinCode = nil
        return code
    }
}
