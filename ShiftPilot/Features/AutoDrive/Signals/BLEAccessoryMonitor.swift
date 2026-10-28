import CoreBluetooth
import Observation

struct DiscoveredAccessory: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var rssi: Int
}

/// Optional car signal from a user-paired BLE accessory (e.g. an OBD-II dongle).
///
/// Keeps a pending `connect` to the saved peripheral. Pending connections never time
/// out, and with state restoration iOS relaunches the app in the background when
/// the accessory powers up with the car.
///
/// The central is only created once an accessory is saved (or the user opens the
/// picker), so drivers without one never see the Bluetooth permission prompt.
@MainActor
@Observable
final class BLEAccessoryMonitor: NSObject, DriveSignalSource {
    static let restoreIdentifier = "com.shiftpilot.ble-central"

    private(set) var discovered: [DiscoveredAccessory] = []
    private(set) var isScanning = false
    private(set) var isConnected = false

    @ObservationIgnored private let devices: KnownDevicesStore
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var continuation: AsyncStream<DriveSignal>.Continuation?

    init(devices: KnownDevicesStore) {
        self.devices = devices
    }

    func start() -> AsyncStream<DriveSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: DriveSignal.self)
        self.continuation = continuation
        if devices.bleAccessoryID != nil {
            ensureCentral()
        }
        return stream
    }

    func refresh() {
        connectToSavedAccessory()
    }

    func stop() {
        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        continuation?.finish()
        continuation = nil
    }

    // MARK: Pairing

    func startScan() {
        ensureCentral()
        discovered = []
        isScanning = true
        if central?.state == .poweredOn {
            central?.scanForPeripherals(withServices: nil)
        }
    }

    func stopScan() {
        isScanning = false
        central?.stopScan()
    }

    func pair(_ accessory: DiscoveredAccessory) {
        stopScan()
        forgetAccessory()
        devices.setBLEAccessory(accessory.id)
        connectToSavedAccessory()
    }

    func forgetAccessory() {
        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        if isConnected, let id = devices.bleAccessoryID {
            continuation?.yield(.carDisconnected(.bleAccessory(id)))
        }
        peripheral = nil
        isConnected = false
        devices.setBLEAccessory(nil)
    }

    // MARK: Private

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: false,
        ])
    }

    private func connectToSavedAccessory() {
        guard let central, central.state == .poweredOn, let id = devices.bleAccessoryID else { return }
        if peripheral?.identifier != id {
            peripheral = central.retrievePeripherals(withIdentifiers: [id]).first
        }
        guard let peripheral, peripheral.state == .disconnected else { return }
        Log.ble.info("Waiting for accessory \(id)")
        central.connect(peripheral)
    }
}

extension BLEAccessoryMonitor: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        if isScanning {
            central.scanForPeripherals(withServices: nil)
        }
        connectToSavedAccessory()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let match = restored.first(where: { $0.identifier == devices.bleAccessoryID }) else { return }
        Log.ble.info("Restored accessory \(match.identifier), state \(match.state.rawValue)")
        peripheral = match
        if match.state == .connected {
            isConnected = true
            continuation?.yield(.carConnected(.bleAccessory(match.identifier)))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name, !discovered.contains(where: { $0.id == peripheral.identifier }) else { return }
        discovered.append(DiscoveredAccessory(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == devices.bleAccessoryID else { return }
        Log.ble.info("Accessory connected")
        isConnected = true
        continuation?.yield(.carConnected(.bleAccessory(peripheral.identifier)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard peripheral.identifier == devices.bleAccessoryID else { return }
        Log.ble.info("Accessory disconnected")
        isConnected = false
        continuation?.yield(.carDisconnected(.bleAccessory(peripheral.identifier)))
        connectToSavedAccessory()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Log.ble.error("Accessory connect failed: \(String(describing: error))")
        connectToSavedAccessory()
    }
}
