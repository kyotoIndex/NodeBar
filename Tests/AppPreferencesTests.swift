import Foundation

enum AppPreferencesTests {
    static func run() throws {
        let legacy: [String: Any] = [
            "socketPath": "/tmp/custom-mihomo.sock",
            "monitors": [["kind": "group", "name": "Saved group"]],
            "refreshInterval": 60, "notificationsEnabled": false,
            "recoveryNotifications": false, "notificationNames": true, "barLimit": 2
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: data)
        precondition(migrated.activeProbing && migrated.automaticConnection)
        precondition(migrated.probeTimeoutSeconds == 10)
        precondition(migrated.socketPath == "/tmp/custom-mihomo.sock")
        precondition(migrated.monitors == [MonitorSelection(kind: .group, name: "Saved group")])
        precondition(migrated.refreshInterval == 60 && !migrated.notificationsEnabled)
        precondition(!migrated.recoveryNotifications && migrated.notificationNames && migrated.barLimit == 2)
        var manual = migrated
        manual.activeProbing = false
        manual.automaticConnection = false
        manual.probeTimeoutSeconds = 15
        let roundTrip = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(manual))
        precondition(!roundTrip.activeProbing && !roundTrip.automaticConnection)
        precondition(roundTrip.probeTimeoutSeconds == 15)
    }
}
