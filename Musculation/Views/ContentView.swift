import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            WorkoutTabView()
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
            ProgressionView()
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
            ExerciseListView()
                .tabItem { Label("Exercices", systemImage: "list.bullet") }
        }
        .task {
            SeedData.insertDefaultExercisesIfNeeded(in: context)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, Workout.self, WorkoutTemplate.self], inMemory: true)
}
