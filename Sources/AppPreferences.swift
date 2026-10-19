import Foundation

struct AppPreferences: Codable {
    static let storageKey = "nodebar.preferences.v1"
    static let intervals: [Double] = [15, 30, 60, 300]
    var socketPath = LocalMihomoClient.defaultSocketPath
    var automaticConnection = true
    var activeProbing = true
    var probeTimeoutSeconds: Double = 10
    var monitors: [MonitorSelection] = []
    var refreshInterval: Double = 30
    var notificationsEnabled = true
    var recoveryNotifications = true
    var notificationNames = false
    var barLimit = 3

    init() {}

    private enum CodingKeys: String, CodingKey {
        case socketPath, automaticConnection, activeProbing, probeTimeoutSeconds, monitors, refreshInterval
        case notificationsEnabled, recoveryNotifications, notificationNames, barLimit
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        socketPath = try values.decodeIfPresent(String.self, forKey: .socketPath) ?? LocalMihomoClient.defaultSocketPath
        automaticConnection = try values.decodeIfPresent(Bool.self, forKey: .automaticConnection) ?? true
        activeProbing = try values.decodeIfPresent(Bool.self, forKey: .activeProbing) ?? true
        probeTimeoutSeconds = try values.decodeIfPresent(Double.self, forKey: .probeTimeoutSeconds) ?? 10
        monitors = try values.decodeIfPresent([MonitorSelection].self, forKey: .monitors) ?? []
        refreshInterval = try values.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 30
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        recoveryNotifications = try values.decodeIfPresent(Bool.self, forKey: .recoveryNotifications) ?? true
        notificationNames = try values.decodeIfPresent(Bool.self, forKey: .notificationNames) ?? false
        barLimit = try values.decodeIfPresent(Int.self, forKey: .barLimit) ?? 3
    }

    static func load(from defaults: UserDefaults = .standard) -> AppPreferences {
        guard let data = defaults.data(forKey: storageKey),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        if !intervals.contains(value.refreshInterval) { value.refreshInterval = 30 }
        if ![5.0, 10.0, 15.0].contains(value.probeTimeoutSeconds) { value.probeTimeoutSeconds = 10 }
        value.barLimit = min(8, max(1, value.barLimit))
        var seen = Set<String>()
        value.monitors = value.monitors.filter { seen.insert($0.id).inserted }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}
