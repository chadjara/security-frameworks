import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID, Touch ID, or passcode lock.
@MainActor
@Observable
final class AppLock {
    enum Delay: Double, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900

        var id: Double { rawValue }
        var title: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute: return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            case .fifteenMinutes: return "After 15 minutes"
            }
        }
    }

    private static let enabledKey = "appLockEnabled"
    private static let delayKey = "appLockDelay"

    private(set) var isEnabled: Bool
    var delay: Delay {
        didSet { UserDefaults.standard.set(delay.rawValue, forKey: Self.delayKey) }
    }
    private(set) var isLocked: Bool
    private(set) var lastError: String?
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        delay = Delay(rawValue: UserDefaults.standard.double(forKey: Self.delayKey)) ?? .immediately
        isLocked = enabled
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiForceLock") {
            isEnabled = true
            isLocked = true
        }
        #endif
    }

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode".
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var methodSymbol: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock"
        }
    }

    // MARK: Scene changes

    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            if isEnabled, let since = backgroundedAt, Date().timeIntervalSince(since) >= delay.rawValue {
                isLocked = true
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    // MARK: Authentication

    @discardableResult
    func unlock() async -> Bool {
        guard await authenticate(reason: "Unlock your assessments") else { return false }
        isLocked = false
        return true
    }

    /// Turning the lock on or off requires authenticating, so someone holding an unlocked device
    /// cannot quietly disable it.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled ? "Turn on app lock" : "Turn off app lock"
        guard await authenticate(reason: reason) else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        isLocked = false
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = "Set up a device passcode in the Settings app to use app lock."
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

/// Full-screen lock shown over the app until the user authenticates.
struct LockScreenView: View {
    @Environment(AppLock.self) private var lock
    @State private var didAutoPrompt = false

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Spacer()
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text("Locked").font(.dsTitle2).foregroundStyle(Color.dsTextPrimary)
                Text("Your assessments are protected.").font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
            }
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(lock.methodName)", systemImage: lock.methodSymbol)
            }
            .buttonStyle(.dsPrimary)
            .accessibilityIdentifier("unlockButton")
            if let error = lock.lastError {
                Text(error).font(.dsFootnote).foregroundStyle(Color.dsDestructive).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsGroupedBackground.ignoresSafeArea())
        .accessibilityIdentifier("screen.lock")
        .task {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uiForceLock") { return }
            #endif
            guard !didAutoPrompt else { return }
            didAutoPrompt = true
            await lock.unlock()
        }
    }
}

/// Opaque cover shown whenever the app is not active, so the app switcher never shows assessment data.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color.dsGroupedBackground.ignoresSafeArea()
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Content hidden")
    }
}
