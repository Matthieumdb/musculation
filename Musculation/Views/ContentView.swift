import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var nutrition = NutritionStore.shared
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @Query private var checkIns: [DailyCheckIn]

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
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                updateTraining()
                QuickActionHandler.applyPending(in: context)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickActionQueue.didPush)) { _ in
            QuickActionHandler.applyPending(in: context)
        }
        .onChange(of: templates.map(\.name), initial: true) {
            QuickActionHandler.shareTemplates(templates)
        }
        .onChange(of: widgetSnapshot, initial: true) { _, snapshot in
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func updateTraining() {
        nutrition.training = TrainingLoad.today(Array(workouts.prefix(60)))
    }

    private var widgetSnapshot: WidgetSnapshot {
        let finished = workouts.filter { $0.endedAt != nil }
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)
        let trained = Set(finished.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start })
        var streak = 0
        if var start = week?.start {
            if !trained.contains(start), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: start) { start = previous }
            while trained.contains(start) {
                streak += 1
                guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: start) else { break }
                start = previous
            }
        }
        let t = nutrition.settings.dayTargets, e = nutrition.eaten()
        let water = checkIns.first { $0.day == DayKey.today }?.water ?? 0
        return WidgetSnapshot(
            day: DayKey.today,
            workoutsThisWeek: finished.filter { week?.contains($0.startedAt) == true }.count,
            weekStreak: streak,
            kcalLeft: Int((t.kcal - e.kcal).rounded()),
            kcalTarget: Int(t.kcal),
            proteinLeft: max(0, Int((t.p - e.p).rounded())),
            trainingBonus: nutrition.training.map { Int($0.kcal) },
            proteinTarget: Int(t.p.rounded()),
            carbsLeft: max(0, Int((t.c - e.c).rounded())),
            carbsTarget: Int(t.c.rounded()),
            fatLeft: max(0, Int((t.f - e.f).rounded())),
            fatTarget: Int(t.f.rounded()),
            water: water,
            waterGoal: nutrition.settings.waterGoal,
            waterDay: DayKey.today
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, Workout.self, WorkoutTemplate.self], inMemory: true)
}
