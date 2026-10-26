import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var nutrition = NutritionStore.shared
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    /// Changes whenever a recent workout starts or ends.
    private var workoutsKey: String {
        workouts.prefix(40).map { "\($0.startedAt.timeIntervalSince1970)-\($0.endedAt?.timeIntervalSince1970 ?? 0)" }.joined(separator: ",")
    }

    var body: some View {
        TabView {
            WorkoutTabView()
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
            ProgressionView()
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .minimizingTabBar()
        .environment(nutrition)
        .task {
            SeedData.insertDefaultExercisesIfNeeded(in: context)
        }
        .onChange(of: workoutsKey, initial: true) { updateTraining() }
        .onChange(of: scenePhase) { if scenePhase == .active { updateTraining() } }
    }

    private func updateTraining() {
        nutrition.training = TrainingLoad.today(Array(workouts.prefix(60)))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, Workout.self, WorkoutTemplate.self], inMemory: true)
}
