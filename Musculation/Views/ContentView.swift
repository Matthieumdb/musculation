import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var nutrition = NutritionStore.shared

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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, Workout.self, WorkoutTemplate.self], inMemory: true)
}
