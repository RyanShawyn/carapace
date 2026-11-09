import Foundation

/// App 与 CLI 共用同一套偏好设置域，避免两边的汇率、点差等取值不一致。
public enum CarapaceDefaults {
    public static var suiteName: String {
        ProcessInfo.processInfo.environment["CARAPACE_DEFAULTS_SUITE"] ?? "com.ryan.carapace"
    }

    public static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static var hkdRate: Double {
        store.object(forKey: "hkdRate") as? Double ?? 0.85
    }

    public static var cmbSpread: Double {
        store.object(forKey: "cmbSpread") as? Double ?? 5
    }
}