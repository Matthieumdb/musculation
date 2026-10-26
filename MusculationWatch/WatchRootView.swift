import SwiftUI

struct WatchRootView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        NavigationStack {
            if let workout = session.workout {
                TabView {
                    CurrentSetView(workout: workout)
                    WorkoutOverviewView(workout: workout)
                }
                .tabViewStyle(.verticalPage)
                .navigationTitle(workout.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                    Text("Aucune séance")
                        .font(.headline)
                    Text("Démarre une séance sur ton iPhone, elle s'affichera ici.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .navigationTitle("Musculation")
            }
        }
    }
}

/// The next set to do, or the rest countdown.
private struct CurrentSetView: View {
    @Environment(WatchSession.self) private var session
    let workout: LiveWorkout

    var body: some View {
        if let end = workout.restEnd, end > .now {
            RestView(start: end.addingTimeInterval(-workout.restTotal), end: end, next: nextLine)
        } else if let position = workout.current {
            let exercise = workout.exercises[position.exercise]
            let set = exercise.sets[position.set]
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
                Text("Série \(position.set + 1) sur \(exercise.sets.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(set.weight.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("kg").font(.footnote).foregroundStyle(.secondary)
                    Text("× \(set.reps)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                }
                Spacer(minLength: 0)
                Button {
                    session.send(.complete(exercise: position.exercise, set: position.set))
                } label: {
                    Label("Série faite", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!session.isPhoneReachable)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Tout est fait !").font(.headline)
                Text("Termine la séance sur ton iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var nextLine: String? {
        guard let position = workout.current else { return nil }
        let exercise = workout.exercises[position.exercise]
        let set = exercise.sets[position.set]
        return "\(exercise.name) · \(set.weight.liveKgText) × \(set.reps)"
    }
}

private struct RestView: View {
    @Environment(WatchSession.self) private var session
    let start: Date
    let end: Date
    let next: String?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.accentColor)
                Text(timerInterval: start...end, countsDown: true)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: 90)
            if let next {
                Text(next).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Button("+30 s") { session.send(.addRest) }
                Button("Passer") { session.send(.skipRest) }
            }
            .font(.footnote.weight(.semibold))
            .disabled(!session.isPhoneReachable)
        }
    }
}

/// Elapsed time and progress of every exercise.
private struct WorkoutOverviewView: View {
    let workout: LiveWorkout

    var body: some View {
        List {
            Section {
                HStack {
                    Text(workout.startedAt, style: .timer)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Spacer()
                    Text("\(workout.doneSets)/\(workout.totalSets)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
            Section("Exercices") {
                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                    let done = exercise.sets.filter(\.done).count
                    HStack {
                        Text(exercise.name).lineLimit(2)
                        Spacer()
                        Text("\(done)/\(exercise.sets.count)")
                            .monospacedDigit()
                            .foregroundStyle(done == exercise.sets.count ? Color.green : Color.secondary)
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
