import Foundation

public struct ConflictAlertPreferences {
    private static let conflictAlertsKey = "conflictAlertsEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var areConflictAlertsEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.conflictAlertsKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.conflictAlertsKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.conflictAlertsKey)
        }
    }
}
