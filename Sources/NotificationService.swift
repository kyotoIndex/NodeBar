import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var authorized = false
    var onStatusChange: ((String) -> Void)?
    var onDeliveryError: ((String) -> Void)?
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func refreshAuthorization(requestIfNeeded: Bool) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined && requestIfNeeded {
                self.center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
                    if let error {
                        DispatchQueue.main.async { self?.onDeliveryError?("通知权限请求失败：\(error.localizedDescription)") }
                    }
                    self?.refreshAuthorization(requestIfNeeded: false)
                }
                return
            }
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let text: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: text = "已允许"
            case .denied: text = "已关闭，请在系统设置中允许 NodeBar 通知"
            case .notDetermined: text = "尚未授权"
            default: text = "权限不可用"
            }
            DispatchQueue.main.async {
                self.authorized = allowed
                self.onStatusChange?(text)
            }
        }
    }

    func deliver(_ events: [AlertEvent], preferences: AppPreferences) {
        guard preferences.notificationsEnabled, authorized else { return }
        for event in events {
            if !preferences.recoveryNotifications && (event.kind == .recovery || event.kind == .controllerRecovery) { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            if preferences.notificationNames, let name = event.monitorName { content.body = "\(name)\n\(event.body)" }
            else { content.body = event.body }
            content.sound = .default
            content.threadIdentifier = "nodebar.monitoring"
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { [weak self] error in
                if let error {
                    DispatchQueue.main.async { self?.onDeliveryError?("通知发送失败：\(error.localizedDescription)") }
                }
            }
        }
    }

    func sendTest() {
        guard authorized else {
            refreshAuthorization(requestIfNeeded: true)
            onDeliveryError?("请允许通知后，再发送测试通知。")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "NodeBar 通知已就绪"
        content.body = "监控异常及恢复时，你会收到系统通知。"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "nodebar.test", content: content, trigger: nil)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onDeliveryError?("通知发送失败：\(error.localizedDescription)") }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        completionHandler()
    }
}
