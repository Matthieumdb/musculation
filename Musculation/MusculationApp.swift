import SwiftUI
import SwiftData

@main
struct MusculationApp: App {
    @AppStorage(AppSettings.appearanceKey) private var appearance = Appearance.light

    init() {
        WorkoutLiveSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: [
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            BodyWeightEntry.self,
            BodyMeasurement.self,
            DailyCheckIn.self,
        ])
    }
}
