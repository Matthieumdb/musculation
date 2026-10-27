import SwiftUI
import SwiftData

@main
struct MusculationApp: App {
    @AppStorage(AppSettings.appearanceKey) private var appearance = Appearance.light

    /// One store for the screens and for what runs without them (the watch starting a workout).
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for:
                Exercise.self,
                Workout.self,
                WorkoutExercise.self,
                WorkoutSet.self,
                WorkoutTemplate.self,
                TemplateExercise.self,
                BodyWeightEntry.self,
                BodyMeasurement.self,
                DailyCheckIn.self,
                ProgressPhoto.self
            )
        } catch {
            fatalError("Impossible d'ouvrir les données : \(error)")
        }
    }()

    init() {
        WorkoutLiveSync.shared.container = Self.container
        WorkoutLiveSync.shared.activate()
        QuickActionQueue.observeOtherProcesses()
        WeeklyRecapNotifier.schedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(Self.container)
    }
}
