import SwiftUI
import SwiftData
import PhotosUI
import ImageIO

/// Body photos by pose, with a before/after comparison.
struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var pose: PhotoPose = .front
    @State private var pickerItem: PhotosPickerItem?
    @State private var isComparing = false
    @State private var isLoading = false

    private var shown: [ProgressPhoto] { photos.filter { $0.pose == pose } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Pose", selection: $pose) {
                    ForEach(PhotoPose.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if shown.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune photo de \(pose.label.lowercased())", systemImage: "person.crop.rectangle")
                    } description: {
                        Text("Prends-toi en photo toutes les 2 à 4 semaines, même lumière et même pose, pour voir les changements que le miroir ne montre pas.")
                    }
                    .padding(.top, 40)
                } else {
                    if shown.count >= 2 {
                        Button {
                            isComparing = true
                        } label: {
                            Label("Comparer avant et après", systemImage: "rectangle.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .glassProminentButton()
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(shown) { photo in
                            NavigationLink {
                                ProgressPhotoDetailView(photo: photo)
                            } label: {
                                PhotoThumbnail(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background { AppBackground() }
        .navigationTitle("Photos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Ajouter une photo", systemImage: "plus")
                }
                .disabled(isLoading)
            }
        }
        .overlay {
            if isLoading { ProgressView().controlSize(.large) }
        }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            isLoading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = await Task.detached(priority: .userInitiated, operation: { ImageDownsampler.jpeg(from: data) }).value {
                    context.insert(ProgressPhoto(pose: pose, imageData: jpeg))
                    try? context.save()
                }
                pickerItem = nil
                isLoading = false
            }
        }
        .sheet(isPresented: $isComparing) {
            NavigationStack { PhotoCompareView(photos: shown) }
        }
    }
}

private struct PhotoThumbnail: View {
    let photo: ProgressPhoto
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(photo.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo du \(photo.date.formatted(date: .long, time: .omitted))")
            .task(id: photo.persistentModelID) {
                let data = photo.imageData
                image = await Task.detached { ImageDownsampler.image(from: data, maxPixels: 400) }.value
            }
    }
}

struct ProgressPhotoDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var photo: ProgressPhoto
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                if let image = UIImage(data: photo.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Photo de progression")
                }
            }
            Section {
                DatePicker("Date", selection: $photo.date, in: ...Date.now, displayedComponents: .date)
                Picker("Pose", selection: $photo.pose) {
                    ForEach(PhotoPose.allCases) { Text($0.label).tag($0) }
                }
                TextField("Note (poids, forme…)", text: $photo.note, axis: .vertical)
            }
            Section {
                Button("Supprimer la photo", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Supprimer cette photo ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                context.delete(photo)
                try? context.save()
                dismiss()
            }
        }
    }
}

/// Two photos of the same pose, one over the other, with a handle to slide between them.
struct PhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [ProgressPhoto]
    @State private var beforeID: PersistentIdentifier?
    @State private var afterID: PersistentIdentifier?
    @State private var split = 0.5

    private var before: ProgressPhoto? { photos.first { $0.persistentModelID == beforeID } ?? photos.last }
    private var after: ProgressPhoto? { photos.first { $0.persistentModelID == afterID } ?? photos.first }

    var body: some View {
        VStack(spacing: 16) {
            if let before, let after, let a = UIImage(data: before.imageData), let b = UIImage(data: after.imageData) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Image(uiImage: b).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        Image(uiImage: a).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: proxy.size.width * split)
                            }
                        Rectangle()
                            .fill(.white)
                            .frame(width: 3)
                            .overlay {
                                Image(systemName: "arrow.left.and.right.circle.fill")
                                    .font(.largeTitle)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.black, .white)
                            }
                            .offset(x: proxy.size.width * split - 1.5)
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        split = min(1, max(0, value.location.x / proxy.size.width))
                    })
                    .accessibilityElement()
                    .accessibilityLabel("Comparaison avant et après")
                    .accessibilityValue("\(Int(split * 100)) % avant")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: split = min(1, split + 0.1)
                        case .decrement: split = max(0, split - 0.1)
                        @unknown default: break
                        }
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    picker("Avant", selection: $beforeID, current: before)
                    Spacer()
                    picker("Après", selection: $afterID, current: after)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Avant / après")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
        }
    }

    private func picker(_ title: String, selection: Binding<PersistentIdentifier?>, current: ProgressPhoto) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(photos) { photo in
                    Text(photo.date.formatted(date: .abbreviated, time: .omitted)).tag(Optional(photo.persistentModelID))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Label(current.date.formatted(date: .abbreviated, time: .omitted), systemImage: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Shrinks photos before they are stored or shown, so the library stays light.
enum ImageDownsampler {
    static func image(from data: Data, maxPixels: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnail = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func jpeg(from data: Data) -> Data? {
        image(from: data, maxPixels: 1600)?.jpegData(compressionQuality: 0.8)
    }
}
