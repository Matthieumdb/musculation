import SwiftUI
import VisionKit
import AVFoundation

/// Live barcode scanner (EAN and UPC) shown in a sheet.
struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void

    @State private var cameraAllowed: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if cameraAllowed == nil {
                    ProgressView()
                } else if cameraAllowed == true && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScannerView { code in
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                        onCode(code)
                    }
                    .ignoresSafeArea()
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                            .frame(width: 280, height: 160)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottom) {
                        Text("Vise le code-barres du produit")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassSurface(in: Capsule(), fallback: .regularMaterial)
                            .padding(.bottom, 40)
                    }
                } else {
                    ContentUnavailableView(
                        "Caméra indisponible",
                        systemImage: "camera.fill",
                        description: Text("Autorise la caméra dans Réglages > Musculation, ou tape le code-barres à la main.")
                    )
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
                } else {
                    cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                }
            }
        }
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, !code.isEmpty {
                    done = true
                    dataScanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}
