//
//  AppGroup.swift
//  Roost
//
//  Shared infrastructure for the main app + RoostWidgets extension.
//
//  The App Group container is the *only* place the widget extension can read
//  domain data from. We use it for:
//    1. The SwiftData store (see LocalDataManager) — so the widget and the
//       main app read/write the same CachedShoppingItem / PendingMutation rows.
//    2. A shared UserDefaults suite — so the widget knows which home/user
//       is currently signed in without touching Supabase auth.
//
//  Target membership: BOTH `Roost_iOS` and `RoostWidgets`.
//

import Foundation

enum AppGroup {
    /// The App Group identifier declared in both targets' Signing & Capabilities.
    /// Must match the string entered in Xcode exactly.
    static let identifier = "group.com.roostapp.ios"

    /// The shared container URL for the App Group. Nil only if the capability
    /// isn't wired up correctly — callers should fall back to the default
    /// container and log.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Location of the shared SwiftData store. We nest it under
    /// `Library/Application Support/` to follow Apple's layout conventions
    /// (the default SwiftData store goes there too).
    static var swiftDataStoreURL: URL? {
        guard let container = containerURL else { return nil }
        let supportDir = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        // Ensure the directory exists; SwiftData won't create intermediate dirs.
        try? FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true
        )
        return supportDir.appendingPathComponent("roost.sqlite")
    }

    /// Shared UserDefaults suite used for auth/home context the widget needs
    /// to function (currentHomeID, currentUserID, activeTripStartedAt).
    /// Never store secrets here — this file is visible to the widget
    /// extension but is still backed up / synced per normal iOS rules.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

// MARK: - Typed accessors for shared UserDefaults

/// Keys used in the shared UserDefaults suite. Kept in one place so the
/// widget and main app can't drift apart.
enum SharedDefaultsKey {
    static let currentHomeID = "roost.currentHomeID"
    static let currentUserID = "roost.currentUserID"
    static let currentUserDisplayName = "roost.currentUserDisplayName"
    static let activeTripActivityID = "roost.activeTripActivityID"
    static let activeTripStartedAt = "roost.activeTripStartedAt"
    static let activeTripStoreName = "roost.activeTripStoreName"
}

extension AppGroup {
    /// Lightweight read/write helpers for the values the widget cares about.
    /// These are the *only* source of truth the widget has for auth context —
    /// AuthManager is responsible for keeping them fresh on sign-in / sign-out.
    enum Context {
        static var currentHomeID: UUID? {
            get { AppGroup.defaults.string(forKey: SharedDefaultsKey.currentHomeID).flatMap(UUID.init) }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue.uuidString, forKey: SharedDefaultsKey.currentHomeID)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.currentHomeID)
                }
            }
        }

        static var currentUserID: UUID? {
            get { AppGroup.defaults.string(forKey: SharedDefaultsKey.currentUserID).flatMap(UUID.init) }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue.uuidString, forKey: SharedDefaultsKey.currentUserID)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.currentUserID)
                }
            }
        }

        static var currentUserDisplayName: String? {
            get { AppGroup.defaults.string(forKey: SharedDefaultsKey.currentUserDisplayName) }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue, forKey: SharedDefaultsKey.currentUserDisplayName)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.currentUserDisplayName)
                }
            }
        }

        static var activeTripActivityID: String? {
            get { AppGroup.defaults.string(forKey: SharedDefaultsKey.activeTripActivityID) }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue, forKey: SharedDefaultsKey.activeTripActivityID)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.activeTripActivityID)
                }
            }
        }

        static var activeTripStartedAt: Date? {
            get {
                let value = AppGroup.defaults.double(forKey: SharedDefaultsKey.activeTripStartedAt)
                return value > 0 ? Date(timeIntervalSince1970: value) : nil
            }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue.timeIntervalSince1970, forKey: SharedDefaultsKey.activeTripStartedAt)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.activeTripStartedAt)
                }
            }
        }

        static var activeTripStoreName: String? {
            get { AppGroup.defaults.string(forKey: SharedDefaultsKey.activeTripStoreName) }
            set {
                if let newValue {
                    AppGroup.defaults.set(newValue, forKey: SharedDefaultsKey.activeTripStoreName)
                } else {
                    AppGroup.defaults.removeObject(forKey: SharedDefaultsKey.activeTripStoreName)
                }
            }
        }

        /// Called by AuthManager on sign-out / account deletion.
        static func clearAll() {
            currentHomeID = nil
            currentUserID = nil
            currentUserDisplayName = nil
            activeTripActivityID = nil
            activeTripStartedAt = nil
            activeTripStoreName = nil
        }
    }
}
