import Foundation
import SwiftData

/// A body photo, to compare how the physique changes over time.
@Model
final class ProgressPhoto {
    var date: Date
    var poseRaw: String
    @Attribute(.externalStorage) var imageData: Data
    var note: String

    init(date: Date = .now, pose: PhotoPose, imageData: Data, note: String = "") {
        self.date = date
        self.poseRaw = pose.rawValue
        self.imageData = imageData
        self.note = note
    }

    var pose: PhotoPose {
        get { PhotoPose(rawValue: poseRaw) ?? .front }
        set { poseRaw = newValue.rawValue }
    }
}

enum PhotoPose: String, CaseIterable, Identifiable {
    case front, side, back

    var id: String { rawValue }

    var label: String {
        switch self {
        case .front: "Face"
        case .side: "Profil"
        case .back: "Dos"
        }
    }
}
