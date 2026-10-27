#if os(iOS)
import Foundation

/// Something asked from outside the app (a widget, Siri, Control Center, the watch), applied by the app.
enum QuickAction: Codable, Hashable {
    case addWater
    case startWorkout(template: String?)
}

/// Pending actions, kept in the App Group so the widget extension can add to them.
enum QuickActionQueue {
    private static let key = "quickActions"
    private static let darwinName = "com.matthieumdb.musculation.quickActions" as CFString
    /// Posted in the app when an action was queued, by this process or by the widget extension.
    static let didPush = Notification.Name("QuickActionQueue.didPush")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard
    }

    static func push(_ action: QuickAction) {
        var actions = pending
        actions.append(action)
        defaults.set(try? JSONEncoder().encode(actions), forKey: key)
        NotificationCenter.default.post(name: didPush, object: nil)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(darwinName), nil, nil, true)
    }

    /// Returns the pending actions and empties the queue.
    static func drain() -> [QuickAction] {
        let actions = pending
        if !actions.isEmpty { defaults.removeObject(forKey: key) }
        return actions
    }

    private static var pending: [QuickAction] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([QuickAction].self, from: data)) ?? []
    }

    /// Relays pushes made by the widget extension as `didPush` in this process.
    static func observeOtherProcesses() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async { NotificationCenter.default.post(name: QuickActionQueue.didPush, object: nil) }
            },
            darwinName, nil, .deliverImmediately
        )
    }
}

/// Names of the workout templates, for Siri, the widgets and the watch.
enum SharedTemplates {
    private static let key = "templateNames"

    static func load() -> [String] {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.stringArray(forKey: key) ?? []
    }

    static func save(_ names: [String]) {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(names, forKey: key)
    }
}
#endif
