import Foundation
import SwiftData

/// Reads the workouts CSV exported by Hevy (Settings › Export & Import Data › Export Workouts).
enum HevyImport {
    struct ParsedWorkout {
        var title: String
        var start: Date
        var end: Date?
        var notes: String
        var exercises: [ParsedExercise]
    }

    struct ParsedExercise {
        var title: String
        var sets: [(weight: Double, reps: Int)]
    }

    enum ImportError: LocalizedError {
        case notHevy
        case empty

        var errorDescription: String? {
            switch self {
            case .notHevy: "Ce fichier ne ressemble pas à un export de séances Hevy (colonnes title, start_time, exercise_title… introuvables)."
            case .empty: "Aucune série de musculation trouvée dans ce fichier."
            }
        }
    }

    static func parse(_ text: String) throws -> [ParsedWorkout] {
        let rows = CSV.rows(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else {
            throw ImportError.empty
        }
        func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        guard let titleColumn = column("title"),
              let startColumn = column("start_time"),
              let exerciseColumn = column("exercise_title"),
              let repsColumn = column("reps")
        else { throw ImportError.notHevy }
        let endColumn = column("end_time")
        let notesColumn = column("description")
        let setTypeColumn = column("set_type")
        let kgColumn = column("weight_kg")
        let lbsColumn = column("weight_lbs")

        var workouts: [ParsedWorkout] = []
        var indexByKey: [String: Int] = [:]

        for row in rows.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            if value(setTypeColumn).lowercased() == "warmup" { continue }
            guard let repsValue = number(value(repsColumn)), repsValue >= 1,
                  let start = date(value(startColumn))
            else { continue }
            let reps = Int(repsValue)
            let weight: Double
            if let kg = number(value(kgColumn)) {
                weight = kg
            } else if let lbs = number(value(lbsColumn)) {
                weight = (lbs * 0.45359237 * 4).rounded() / 4
            } else {
                weight = 0
            }

            let title = value(titleColumn)
            let key = "\(title)|\(value(startColumn))"
            let workoutIndex: Int
            if let index = indexByKey[key] {
                workoutIndex = index
            } else {
                workouts.append(ParsedWorkout(
                    title: title.isEmpty ? "Séance Hevy" : title,
                    start: start,
                    end: date(value(endColumn)),
                    notes: value(notesColumn),
                    exercises: []
                ))
                workoutIndex = workouts.count - 1
                indexByKey[key] = workoutIndex
            }

            let exerciseTitle = value(exerciseColumn)
            guard !exerciseTitle.isEmpty else { continue }
            if workouts[workoutIndex].exercises.last?.title == exerciseTitle {
                workouts[workoutIndex].exercises[workouts[workoutIndex].exercises.count - 1].sets.append((weight, reps))
            } else {
                workouts[workoutIndex].exercises.append(ParsedExercise(title: exerciseTitle, sets: [(weight, reps)]))
            }
        }

        workouts.removeAll { $0.exercises.isEmpty }
        guard !workouts.isEmpty else { throw ImportError.empty }
        return workouts.sorted { $0.start < $1.start }
    }

    /// Body weights from Hevy's measurements export, or nil when the file is not one.
    static func parseBodyWeights(_ text: String) -> [(date: Date, weight: Double)]? {
        let rows = CSV.rows(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }),
              !header.contains("exercise_title"),
              let dateColumn = header.firstIndex(of: "date")
        else { return nil }
        let kgColumn = header.firstIndex(of: "weight_kg")
        let lbsColumn = header.firstIndex(of: "weight_lbs")
        guard kgColumn != nil || lbsColumn != nil else { return nil }
        return rows.dropFirst().compactMap { row in
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            guard let date = date(value(dateColumn)) else { return nil }
            if let kg = number(value(kgColumn)), kg > 0 { return (date, kg) }
            if let lbs = number(value(lbsColumn)), lbs > 0 { return (date, (lbs * 0.45359237 * 10).rounded() / 10) }
            return nil
        }
    }

    /// Adds the weigh-ins whose day has none yet. Returns how many were added.
    @discardableResult
    static func importBodyWeights(_ entries: [(date: Date, weight: Double)], in context: ModelContext) -> Int {
        let calendar = Calendar.current
        var days = Set(((try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []).map { calendar.startOfDay(for: $0.date) })
        var added = 0
        for entry in entries where days.insert(calendar.startOfDay(for: entry.date)).inserted {
            context.insert(BodyWeightEntry(date: entry.date, weight: entry.weight))
            added += 1
        }
        try? context.save()
        return added
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static let dateFormatters: [DateFormatter] = {
        let patterns: [(String, String)] = [
            ("en_US_POSIX", "d MMM yyyy, HH:mm"),
            ("en_US_POSIX", "d MMM yyyy, H:mm"),
            ("en_US_POSIX", "d MMMM yyyy, HH:mm"),
            ("fr_FR", "d MMM yyyy, HH:mm"),
            ("fr_FR", "d MMMM yyyy, HH:mm"),
            ("en_US_POSIX", "yyyy-MM-dd HH:mm:ss"),
            ("en_US_POSIX", "yyyy-MM-dd HH:mm"),
            ("en_US_POSIX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"),
            ("en_US_POSIX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"),
            ("en_US_POSIX", "MMM d, yyyy, HH:mm"),
            ("en_US_POSIX", "MMM d, yyyy, h:mm a"),
            ("en_US_POSIX", "dd/MM/yyyy HH:mm"),
        ]
        return patterns.map { locale, pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.dateFormat = pattern
            formatter.isLenient = true
            return formatter
        }
    }()

    private static let months: [String: Int] = [
        "janv": 1, "janvier": 1, "jan": 1, "january": 1,
        "févr": 2, "fevr": 2, "février": 2, "fev": 2, "feb": 2, "february": 2,
        "mars": 3, "mar": 3, "march": 3,
        "avr": 4, "avril": 4, "apr": 4, "april": 4,
        "mai": 5, "may": 5,
        "juin": 6, "jun": 6, "june": 6,
        "juil": 7, "juillet": 7, "jul": 7, "july": 7,
        "août": 8, "aout": 8, "aug": 8, "august": 8,
        "sept": 9, "septembre": 9, "sep": 9, "september": 9,
        "oct": 10, "octobre": 10, "october": 10,
        "nov": 11, "novembre": 11, "november": 11,
        "déc": 12, "dec": 12, "décembre": 12, "december": 12,
    ]

    /// "14 oct. 2026, 09:26" or "14 Oct 2026, 09:26", as Hevy writes dates in each language.
    private static func dayMonthYear(_ text: String) -> Date? {
        let parts = text
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { String($0).lowercased() }
        guard parts.count >= 3,
              let day = Int(parts[0]),
              let month = months[parts[1]],
              let year = Int(parts[2])
        else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        if parts.count >= 4 {
            let time = parts[3].split(separator: ":").compactMap { Int($0) }
            components.hour = time.first
            components.minute = time.count > 1 ? time[1] : 0
        }
        return Calendar.current.date(from: components)
    }

    static func date(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if let date = dayMonthYear(text) { return date }
        for formatter in dateFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

// MARK: - Exercise matching

extension HevyImport {
    /// Where the sets of a Hevy exercise go.
    enum Target: Hashable {
        case existing(PersistentIdentifier, name: String)
        case library(String)
        case new(name: String)

        var label: String {
            switch self {
            case .existing(_, let name): name
            case .library(let id): ExerciseLibrary.entry(id: id)?.nameFR ?? id
            case .new(let name): name
            }
        }
    }

    /// Hevy's names for the app's built-in exercises.
    private static let knownTitles: [String: String] = [
        "bench press (barbell)": "Développé couché",
        "incline bench press (dumbbell)": "Développé incliné haltères",
        "chest dip": "Dips",
        "pull up": "Tractions",
        "bent over row (barbell)": "Rowing barre",
        "lat pulldown (cable)": "Tirage vertical",
        "dumbbell row": "Rowing haltère",
        "deadlift (barbell)": "Soulevé de terre",
        "overhead press (barbell)": "Développé militaire",
        "lateral raise (dumbbell)": "Élévations latérales",
        "face pull": "Face pull",
        "bicep curl (barbell)": "Curl barre",
        "hammer curl (dumbbell)": "Curl marteau",
        "triceps pushdown": "Extension triceps poulie",
        "skullcrusher (barbell)": "Barre au front",
        "squat (barbell)": "Squat",
        "leg press (machine)": "Presse à cuisses",
        "lunge (dumbbell)": "Fentes",
        "lying leg curl (machine)": "Leg curl allongé",
        "leg extension (machine)": "Leg extension",
        "standing calf raise (machine)": "Mollets debout",
        "romanian deadlift (barbell)": "Soulevé de terre roumain",
        "hip thrust (barbell)": "Hip thrust",
        "plank": "Gainage",
        "crunch": "Crunch",
        "chest supported incline row (dumbbell)": "Rowing poitrine appuyée",
        "lat pulldown - close grip (cable)": "Tirage vertical prise neutre",
        "ez bar biceps curl": "Curl barre EZ",
        "overhead triceps extension (cable)": "Extension triceps au-dessus de la tête",
        "seated leg curl (machine)": "Leg curl assis",
        "cable crunch": "Crunch poulie",
        "incline bench press (smith machine)": "Développé incliné machine",
        "shoulder press (dumbbell)": "Développé épaules",
        "seated overhead press (dumbbell)": "Développé épaules",
        "chest fly (machine)": "Pec deck",
        "butterfly (pec deck)": "Pec deck",
        "triceps rope pushdown": "Pushdown triceps",
        "seated cable row - v grip (cable)": "Rowing assis poulie",
        "straight arm lat pulldown (cable)": "Pull-over poulie",
        "rear delt reverse fly (machine)": "Oiseau (reverse pec deck)",
        "seated incline curl (dumbbell)": "Curl incliné haltères",
        "bulgarian split squat": "Fentes bulgares",
        "seated calf raise": "Mollets assis",
        "hip adduction (machine)": "Adducteurs machine",
        // Hevy in French
        "curl incliné assis (haltère)": "Curl incliné haltères",
        "extension triceps poulie haute": "Extension triceps poulie",
        "extension triceps (poulie)": "Extension triceps poulie",
        "élévation latérale (haltère)": "Élévations latérales",
        "chest press (machine)": "Développé pectoraux machine",
        "développé couché incliné (machine smith)": "Développé incliné machine",
        "tirage vers visage": "Face pull",
        "extension des triceps au-dessus de la tête (câble)": "Extension triceps au-dessus de la tête",
        "curl biceps (poulie)": "Curl biceps poulie debout",
        "curl biceps (haltère)": "Curl haltères",
        "curl marteau (haltère)": "Curl marteau",
        "rowing assis (machine)": "Rowing iso machine",
        "tirage poitrine (machine)": "Tirage vertical",
        "tirage poitrine (poulie)": "Tirage vertical",
        "vertical traction (machine)": "Tirage vertical",
        "tirage poitrine - prise serrée (poulie)": "Tirage vertical prise serrée",
        "tirage poitrine bras tendus (poulie)": "Pull-over poulie",
        "curl derrière le dos (poulie)": "Curl derrière le dos (poulie)",
        "curl derrière le dos (câble)": "Curl derrière le dos (poulie)",
        "élévation frontale (haltère)": "Élévation frontale haltères",
        "développé couché décliné (machine)": "Développé décliné machine",
        "élévation latérale un bras (poulie)": "Élévation deltoïde poulie basse",
        "élévation latérale à un bras (câble)": "Élévation deltoïde poulie basse",
        "extension jambes": "Leg extension",
        "leg curl assis": "Leg curl assis",
        "leg curl assis (machine)": "Leg curl assis",
        "curl pupitre (machine)": "Curl pupitre machine",
        "curl pupitre (haltère)": "Curl pupitre haltères",
        "presse à cuisses": "Presse à cuisses",
        "presse à cuisses horizontal": "Presse à cuisses",
        "rowing barre t": "Rowing T-bar",
        "oiseau (machine)": "Oiseau (reverse pec deck)",
        "oiseau penché (haltère)": "Oiseau",
        "rowing poulie assis - prise en v": "Rowing assis poulie",
        "tirage assis à la poulie - prise en v (poulie)": "Rowing assis poulie",
        "développé couché incliné (haltère)": "Développé incliné haltères",
        "développé couché (haltère)": "Développé couché haltères",
        "développé couché (barre)": "Développé couché",
        "écartés poulie": "Écarté à la poulie",
        "écarté (machine)": "Pec deck",
        "split squat bulgare (haltère)": "Fentes bulgares",
        "squat (barre)": "Squat",
        "soulevé de terre (barre)": "Soulevé de terre",
        "traction": "Tractions",
    ]

    /// Best guess for a Hevy exercise among the user's exercises and the library.
    static func suggestedTarget(for title: String, exercises: [Exercise]) -> Target {
        func findExercise(named name: String) -> Exercise? {
            exercises.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        if let exercise = findExercise(named: title) {
            return .existing(exercise.persistentModelID, name: exercise.name)
        }
        if let name = knownTitles[title.lowercased()] {
            if let exercise = findExercise(named: name) {
                return .existing(exercise.persistentModelID, name: exercise.name)
            }
            if let entry = ExerciseLibrary.entry(name: name) {
                return .library(entry.id)
            }
            return .new(name: name)
        }
        if let entry = bestLibraryMatch(for: title) {
            if let exercise = exercises.first(where: { $0.libraryEntry?.id == entry.id }) {
                return .existing(exercise.persistentModelID, name: exercise.name)
            }
            return .library(entry.id)
        }
        return .new(name: title)
    }

    private static func tokens(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "e-z", with: "ez")
            .replacingOccurrences(of: "pull-up", with: "pullup")
            .replacingOccurrences(of: "pull up", with: "pullup")
            .replacingOccurrences(of: "chin-up", with: "chinup")
            .replacingOccurrences(of: "chin up", with: "chinup")
            .replacingOccurrences(of: "push-up", with: "pushup")
            .replacingOccurrences(of: "push up", with: "pushup")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        let ignored: Set<String> = ["with", "the", "a", "on", "to", "of", "medium", "grip", "version", "attachment"]
        return Set(cleaned.compactMap { word -> String? in
            guard !word.isEmpty, !ignored.contains(word) else { return nil }
            return word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
        })
    }

    private static let libraryTokens: [(LibraryExercise, Set<String>)] = ExerciseLibrary.all.map { entry in
        var words = tokens(entry.name)
        switch entry.equipment {
        case "barbell": words.insert("barbell")
        case "dumbbell": words.insert("dumbbell")
        case "cable": words.insert("cable")
        case "machine": words.insert("machine")
        case "e-z curl bar": words.formUnion(["ez", "bar"])
        case "kettlebells": words.insert("kettlebell")
        case "bands": words.insert("band")
        default: break
        }
        return (entry, words)
    }

    private static func bestLibraryMatch(for title: String) -> LibraryExercise? {
        let words = tokens(title)
        guard !words.isEmpty else { return nil }
        var best: (LibraryExercise, Double)?
        for (entry, entryWords) in libraryTokens {
            let shared = Double(words.intersection(entryWords).count)
            let score = shared / Double(words.union(entryWords).count)
            if score > (best?.1 ?? 0) { best = (entry, score) }
        }
        guard let best, best.1 >= 0.6 else { return nil }
        return best.0
    }

    static func guessMuscleGroup(for title: String) -> MuscleGroup {
        let name = title.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        if has("développé", "écarté", "pompe") { return .chest }
        if has("rowing", "tirage", "traction") { return .back }
        if has("élévation", "épaule", "oiseau") { return .shoulders }
        if has("jambe", "fente", "presse", "mollet") { return .legs }
        if has("leg curl", "leg extension", "squat", "lunge", "leg press", "calf", "step up") { return .legs }
        if has("hip thrust", "glute", "kickback", "abduct") { return .glutes }
        if has("tricep", "skull", "pushdown", "dip") { return .triceps }
        if has("curl") { return .biceps }
        if has("bench", "chest", "fly", "push up", "pec") { return .chest }
        if has("shoulder", "lateral", "overhead press", "military", "face pull", "rear delt", "shrug") { return .shoulders }
        if has("row", "pull", "lat ", "deadlift", "chin") { return .back }
        if has("crunch", "plank", "ab ", "sit up", "leg raise") { return .abs }
        return .fullBody
    }

    /// Creates the workouts, skipping those already in the app (same start time). Returns how many were added.
    @discardableResult
    static func importWorkouts(
        _ workouts: [ParsedWorkout],
        targets: [String: Target],
        in context: ModelContext
    ) -> Int {
        let existingStarts = ((try? context.fetch(FetchDescriptor<Workout>())) ?? []).map(\.startedAt)
        var resolved: [Target: Exercise] = [:]

        func exercise(for target: Target, title: String) -> Exercise? {
            if let exercise = resolved[target] { return exercise }
            let exercise: Exercise?
            switch target {
            case .existing(let id, _):
                exercise = context.model(for: id) as? Exercise
            case .library(let id):
                guard let entry = ExerciseLibrary.entry(id: id) else { return nil }
                let created = Exercise(name: entry.nameFR, muscleGroup: entry.muscleGroup)
                created.libraryId = entry.id
                context.insert(created)
                exercise = created
            case .new(let name):
                let created = Exercise(name: name, muscleGroup: guessMuscleGroup(for: title))
                context.insert(created)
                exercise = created
            }
            resolved[target] = exercise
            return exercise
        }

        var added = 0
        for parsed in workouts where !existingStarts.contains(where: { abs($0.timeIntervalSince(parsed.start)) < 60 }) {
            let workout = Workout(title: parsed.title, startedAt: parsed.start)
            context.insert(workout)
            workout.notes = parsed.notes
            workout.endedAt = parsed.end ?? parsed.start.addingTimeInterval(3600)
            for (order, parsedExercise) in parsed.exercises.enumerated() {
                let target = targets[parsedExercise.title] ?? .new(name: parsedExercise.title)
                guard let exercise = exercise(for: target, title: parsedExercise.title) else { continue }
                let entry = WorkoutExercise(order: order)
                context.insert(entry)
                entry.exercise = exercise
                entry.workout = workout
                for set in parsedExercise.sets {
                    entry.addSet(reps: set.reps, weight: set.weight, in: context).isCompleted = true
                }
            }
            added += 1
        }
        try? context.save()
        return added
    }
}

/// Minimal RFC 4180 reader: quoted fields, doubled quotes, commas and newlines inside quotes.
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()

        while let scalar = pending {
            pending = iterator.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.unicodeScalars.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r":
                if scalar == "\r", pending == "\n" { pending = iterator.next() }
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            case "\u{FEFF}":
                break
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
