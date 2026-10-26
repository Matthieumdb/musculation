import SwiftUI
import SwiftData

@main
struct MusculationApp: App {
    init() {
        WorkoutLiveSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            BodyWeightEntry.self,
        ])
    }
}
