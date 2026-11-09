import Foundation
import AppKit
import UserNotifications
import CarapaceCore

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// 裸二进制（swift run / dev-run）没有 bundle identifier，
    /// UNUserNotificationCenter.current() 会直接抛 NSException，必须避开。
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() async {
        guard let center else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationDescription() async -> String {
        guard let center else { return "不可用（未以 .app 运行）" }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return "已允许"
        case .denied: return "已被系统拒绝"
        case .notDetermined: return "尚未请求"
        @unknown default: return "未知"
        }
    }

    func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func send(id: String, title: String, body: String, enabled: Bool, critical: Bool = false) {
        guard enabled, let center else { return }
        if !critical && Self.isQuietHours() { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// 免打扰 22:30–07:30（上海时间）。面板内的提醒不受影响。
    static func isQuietHours(at date: Date = Date()) -> Bool {
        guard CarapaceDefaults.store.object(forKey: "quietHours") as? Bool ?? false else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MarketHours.zone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let minutes = hour * 60 + minute
        return minutes >= 22 * 60 + 30 || minutes < 7 * 60 + 30
    }

    /// App 在前台时也显示横幅，否则打开主窗口时收不到价格提醒。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
