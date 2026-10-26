#if os(iOS)
import AppIntents
import WidgetKit

/// Adds a glass of water, from Siri, a widget or Control Center.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un verre d'eau"
    static var description = IntentDescription("Ajoute un verre d'eau de 25 cl à ta journée.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        QuickActionQueue.push(.addWater)
        // Shown right away by the widgets, before the app records it.
        var glasses = 1
        if var snapshot = WidgetSnapshot.load() {
            glasses = snapshot.waterToday + 1
            snapshot.water = glasses
            snapshot.waterDay = WidgetSnapshot.todayKey
            snapshot.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "C'est noté : \(glasses) verre\(glasses > 1 ? "s" : "") aujourd'hui.")
    }
}

/// A workout template, by name.
struct TemplateEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Modèle de séance"
    static var defaultQuery = TemplateQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct TemplateQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TemplateEntity] {
        identifiers.map { TemplateEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [TemplateEntity] {
        SharedTemplates.load()
            .filter { $0.localizedCaseInsensitiveContains(string) }
            .map { TemplateEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [TemplateEntity] {
        SharedTemplates.load().map { TemplateEntity(id: $0) }
    }
}

/// Opens the app on a new workout, from a template or free.
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer une séance"
    static var description = IntentDescription("Ouvre Musculation sur une nouvelle séance.")
    static var openAppWhenRun = true

    @Parameter(title: "Modèle")
    var template: TemplateEntity?

    init() {}

    init(template: String?) {
        self.template = template.map { TemplateEntity(id: $0) }
    }

    func perform() async throws -> some IntentResult {
        QuickActionQueue.push(.startWorkout(template: template?.id))
        return .result()
    }
}
#endif
