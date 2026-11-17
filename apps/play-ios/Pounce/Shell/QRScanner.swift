import SwiftUI
import UIKit
import VisionKit

/// The camera looking for a QR code ("Show on TV"): VisionKit's `DataScannerViewController`,
/// recognising QR codes and nothing else. Only each code's text comes out of it; the frames stay
/// inside VisionKit, which runs the camera on its own queue, and nothing here keeps or sends them.
///
/// Off on a device without the scanner (the simulator, an old phone) and when the camera isn't
/// allowed: `canScan` says so, and the sheet shows the typed code instead.
struct QRScanner: UIViewControllerRepresentable {
    /// Looking for codes. False stops the camera (a found code is being linked, or the sheet left).
    var active: Bool
    /// The text of each QR code as it comes into view or changes. The caller decides if it is the
    /// one it wants; anything else is ignored and the scanner keeps looking.
    let onText: (String) -> Void
    /// The scanner stopped working (the camera was taken away or turned off).
    let onUnavailable: () -> Void

    /// This device has the scanner and the camera may be used now.
    @MainActor static var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    /// This device has the scanner at all (whatever the camera permission says).
    @MainActor static var supported: Bool { DataScannerViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText, onUnavailable: onUnavailable) }

    func makeUIViewController(context: Context) -> Host {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            // VisionKit's own hints are words on the camera; the sheet says what to do.
            isGuidanceEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        let coordinator = context.coordinator
        return Host(scanner: scanner, active: active) { coordinator.onUnavailable() }
    }

    func updateUIViewController(_ host: Host, context: Context) {
        context.coordinator.onText = onText
        context.coordinator.onUnavailable = onUnavailable
        host.active = active
    }

    static func dismantleUIViewController(_ host: Host, coordinator: Coordinator) {
        host.active = false
    }

    /// Holds the scanner as a child and starts it only once it is on screen (VisionKit asks for
    /// that), and stops it whenever `active` goes false or the view goes away.
    final class Host: UIViewController {
        let scanner: DataScannerViewController
        /// The camera wouldn't start: the sheet shows the code entry instead of a black square.
        private let onFail: () -> Void
        private var onScreen = false
        var active: Bool {
            didSet { if active != oldValue { apply() } }
        }

        init(scanner: DataScannerViewController, active: Bool, onFail: @escaping () -> Void) {
            self.scanner = scanner
            self.active = active
            self.onFail = onFail
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onScreen = true
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onScreen = false
            apply()
        }

        private func apply() {
            if active && onScreen {
                guard !scanner.isScanning else { return }
                do {
                    try scanner.startScanning()
                } catch {
                    // `active` is set from `updateUIViewController`, in the middle of a view
                    // update: the fallback changes the sheet's state, so it waits a turn.
                    let onFail = onFail
                    Task { @MainActor in onFail() }
                }
            } else if scanner.isScanning {
                scanner.stopScanning()
            }
        }
    }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: (String) -> Void
        var onUnavailable: () -> Void

        init(onText: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onText = onText
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            report(added)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            report(updated)
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let text = code.payloadStringValue { onText(text) }
            }
        }
    }
}
