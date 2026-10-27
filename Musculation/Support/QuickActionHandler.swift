import SwiftData
import WidgetKit

/// Applies what widgets, Siri, Control Center and the watch asked for.
@MainActor
enum QuickActionHandler {
    static func applyPending(in context: ModelContext) {
        for action in QuickActionQueue.drain() {
            apply(action, in: context)
        }
    }

    static func apply(_ action: QuickAction, in context: ModelContext) {
        switch action {
        case .addWater:
            DailyCheckIn.today(in: context).water += 1
            try? context.save()
        case .startWorkout(let name):
            startWorkout(template: name, in: context)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Starts a workout unless one is already running. Returns the running workout.
    @discardableResult
    static func startWorkout(template name: String?, in context: ModelContext) -> Workout? {
        let running = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil })
        if let current = try? context.fetch(running).first { return current }

        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        if let name, let template = templates.first(where: { $0.name == name }) {
            let programDeload = template.programName != nil
                && TrainingProgram.phase(startedAt: Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: TrainingProgram.startDateKey))).isDeload
            template.startWorkout(in: context, deload: programDeload || TrainingMode.isReduced)
        } else {
            context.insert(Workout(title: "Séance du \(Date.now.formatted(.dateTime.day().month(.wide)))"))
            try? context.save()
        }
        return try? context.fetch(running).first
    }

    /// Keeps the template names where Siri, the widgets and the watch can read them.
    static func shareTemplates(_ templates: [WorkoutTemplate]) {
        let names = templates
            .sorted { ($0.programName != nil ? 0 : 1, $0.programOrder ?? 0, $0.createdAt) < ($1.programName != nil ? 0 : 1, $1.programOrder ?? 0, $1.createdAt) }
            .map(\.name)
            .filter { !$0.isEmpty }
        WorkoutLiveSync.shared.templates = names
        guard names != SharedTemplates.load() else { return }
        SharedTemplates.save(names)
        MusculationShortcuts.updateAppShortcutParameters()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
