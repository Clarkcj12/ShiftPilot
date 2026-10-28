import AVFoundation

/// Detects the car's infotainment system through the audio route.
///
/// Car head units connect over Classic Bluetooth (HFP/A2DP) or CarPlay, neither of
/// which CoreBluetooth can see. The audio route can: when the car connects, iOS
/// routes audio to it and posts `routeChangeNotification`.
///
/// Notifications only arrive while the app is running, so `refresh()` re-reads the
/// current route whenever iOS wakes or relaunches the app.
@MainActor
final class CarAudioRouteMonitor: DriveSignalSource {
    private let devices: KnownDevicesStore
    private var observer: (any NSObjectProtocol)?
    private var continuation: AsyncStream<DriveSignal>.Continuation?
    private var current: CarConnection?

    init(devices: KnownDevicesStore) {
        self.devices = devices
    }

    func start() -> AsyncStream<DriveSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: DriveSignal.self)
        self.continuation = continuation

        // We only read the route; the audio session is never activated, so other apps' audio is untouched.
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
        return stream
    }

    func refresh() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let bluetooth = outputs.first { Self.bluetoothPorts.contains($0.portType) }
        devices.connectedBluetoothAudio = bluetooth.map { KnownAudioDevice(uid: $0.uid, name: $0.portName) }

        let detected: CarConnection?
        if outputs.contains(where: { $0.portType == .carAudio }) {
            detected = .carPlay
        } else if let bluetooth, devices.isCar(uid: bluetooth.uid) {
            detected = .bluetoothAudio(uid: bluetooth.uid, name: bluetooth.portName)
        } else {
            detected = nil
        }

        guard detected != current else { return }
        if let current {
            continuation?.yield(.carDisconnected(current))
        }
        if let detected {
            continuation?.yield(.carConnected(detected))
        }
        current = detected
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        continuation?.finish()
        continuation = nil
        current = nil
    }

    private static let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
}
