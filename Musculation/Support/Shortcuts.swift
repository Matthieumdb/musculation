import AppIntents

/// Siri phrases and the Shortcuts app actions.
struct MusculationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Démarre ma séance \(\.$template) dans \(.applicationName)",
                "Lance la séance \(\.$template) avec \(.applicationName)",
                "Démarre une séance dans \(.applicationName)",
                "Lance une séance avec \(.applicationName)",
            ],
            shortTitle: "Démarrer une séance",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: [
                "Ajoute un verre d'eau dans \(.applicationName)",
                "J'ai bu un verre d'eau \(.applicationName)",
            ],
            shortTitle: "Verre d'eau",
            systemImageName: "drop.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .red
}
