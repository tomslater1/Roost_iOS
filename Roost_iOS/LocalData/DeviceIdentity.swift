import Foundation

/// Stable, per-install device identifier used to tag offline mutations.
///
/// Generated once on first launch and persisted to UserDefaults. Not shared
/// across reinstalls (intentional — a reinstall is treated as a new device so
/// pending-mutation conflicts can be resolved cleanly).
enum DeviceIdentity {
    private static let storageKey = "com.roostapp.ios.deviceID"

    /// The device ID for this install. Stable across launches, rotates on reinstall.
    ///
    /// Backed by the shared App Group UserDefaults so the main app and the
    /// RoostWidgets extension tag their mutations with the same device ID —
    /// otherwise LWW conflict resolution on the server would see them as
    /// two separate devices.
    static var current: UUID {
        let defaults = AppGroup.defaults
        if let raw = defaults.string(forKey: storageKey),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        // Migrate an older value that may still live in UserDefaults.standard
        // from a pre-App-Group build.
        if let legacy = UserDefaults.standard.string(forKey: storageKey),
           let uuid = UUID(uuidString: legacy) {
            defaults.set(legacy, forKey: storageKey)
            return uuid
        }
        let new = UUID()
        defaults.set(new.uuidString, forKey: storageKey)
        return new
    }
}
