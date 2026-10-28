import Foundation
import Observation

struct KnownAudioDevice: Codable, Hashable, Identifiable, Sendable {
    /// `AVAudioSessionPortDescription.uid` — stable per Bluetooth device.
    var uid: String
    var name: String

    var id: String { uid }
}

/// Devices the user has told us belong to their car.
///
/// Bluetooth headphones and a car head unit look identical to the audio route API,
/// so a Bluetooth audio device only counts as a car once the user marks it.
@MainActor
@Observable
final class KnownDevicesStore {
    private(set) var carAudioDevices: [KnownAudioDevice]
    private(set) var bleAccessoryID: UUID?
    /// The Bluetooth audio device connected right now, known or not. Not persisted.
    var connectedBluetoothAudio: KnownAudioDevice?

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let carAudioDevices = "knownCarAudioDevices"
        static let bleAccessoryID = "bleAccessoryID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.carAudioDevices),
           let devices = try? JSONDecoder().decode([KnownAudioDevice].self, from: data) {
            carAudioDevices = devices
        } else {
            carAudioDevices = []
        }
        bleAccessoryID = defaults.string(forKey: Key.bleAccessoryID).flatMap(UUID.init(uuidString:))
    }

    func isCar(uid: String) -> Bool {
        carAudioDevices.contains { $0.uid == uid }
    }

    func addCar(_ device: KnownAudioDevice) {
        guard !isCar(uid: device.uid) else { return }
        carAudioDevices.append(device)
        saveCarAudioDevices()
    }

    func removeCar(uid: String) {
        carAudioDevices.removeAll { $0.uid == uid }
        saveCarAudioDevices()
    }

    func setBLEAccessory(_ id: UUID?) {
        bleAccessoryID = id
        defaults.set(id?.uuidString, forKey: Key.bleAccessoryID)
    }

    private func saveCarAudioDevices() {
        defaults.set(try? JSONEncoder().encode(carAudioDevices), forKey: Key.carAudioDevices)
    }
}
