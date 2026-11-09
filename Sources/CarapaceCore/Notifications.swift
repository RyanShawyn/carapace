import Foundation

public enum CarapaceNotify {
    public static let name = "com.ryan.carapace.changed"

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true)
    }
}
