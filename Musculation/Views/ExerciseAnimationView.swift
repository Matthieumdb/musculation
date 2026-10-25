import SwiftUI

/// Plays the exercise's start and end positions in a loop.
struct ExerciseAnimationView: View {
    let entry: LibraryExercise
    var interval: Double = 1.0

    @State private var frames: [UIImage] = []
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.white
            if frames.count == 2 {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate / interval) % 2
                    ZStack {
                        ForEach(0..<2, id: \.self) { frame in
                            Image(uiImage: frames[frame])
                                .resizable()
                                .scaledToFit()
                                .opacity(frame == index ? 1 : 0)
                        }
                    }
                    .animation(.easeInOut(duration: interval * 0.35), value: index)
                }
            } else if let first = frames.first {
                Image(uiImage: first).resizable().scaledToFit()
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.title2)
                    Text("Illustration indisponible hors connexion").font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: entry.id) { await load() }
    }

    private func load() async {
        let cached = (0..<2).compactMap { ExerciseImageStore.cached(entry.id, frame: $0) }
        if cached.count == 2 {
            frames = cached
            return
        }
        var loaded: [UIImage] = []
        for frame in 0..<2 {
            if let image = await ExerciseImageStore.load(entry.id, frame: frame) {
                loaded.append(image)
            }
        }
        frames = loaded
        failed = loaded.isEmpty
    }
}

/// First frame of the exercise, as a small rounded thumbnail.
struct ExerciseThumbnail: View {
    let entry: LibraryExercise
    var size: CGFloat = 44

    @State private var image: UIImage?

    init(entry: LibraryExercise, size: CGFloat = 44) {
        self.entry = entry
        self.size = size
        _image = State(initialValue: ExerciseImageStore.cached(entry.id, frame: 1))
    }

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: entry.muscleGroup.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(entry.muscleGroup.color)
            }
        }
        .frame(width: size * 1.4, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .task(id: entry.id) {
            if image == nil {
                image = await ExerciseImageStore.load(entry.id, frame: 1)
            }
        }
    }
}

/// Library thumbnail when the exercise has one, otherwise its muscle icon.
struct ExerciseIcon: View {
    let exercise: Exercise
    var size: CGFloat = 32

    var body: some View {
        if let entry = exercise.libraryEntry {
            ExerciseThumbnail(entry: entry, size: size)
        } else {
            MuscleIcon(group: exercise.muscleGroup, size: size)
        }
    }
}
