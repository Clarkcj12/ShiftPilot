import CoreLocation
import CoreMotion
import SwiftUI

struct SettingsView: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(KnownDevicesStore.self) private var devices
    @Environment(BLEAccessoryMonitor.self) private var bleMonitor
    @Environment(AutoDriveDetectionManager.self) private var autoDrive

    var body: some View {
        List {
            Section {
                PermissionRow(title: "Location", status: locationText, isGranted: permissions.hasAlwaysLocation) {
                    permissions.requestLocation()
                }
                PermissionRow(title: "Motion & Fitness", status: motionText, isGranted: permissions.motionStatus == .authorized) {
                    permissions.requestMotion()
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("\"Always\" location lets ShiftPilot start logging when you get in the car, even if the app is closed.")
            }

            Section {
                ForEach(devices.carAudioDevices) { device in
                    Label(device.name, systemImage: "car.fill")
                }
                .onDelete { offsets in
                    for index in offsets {
                        devices.removeCar(uid: devices.carAudioDevices[index].uid)
                    }
                }

                if let connected = devices.connectedBluetoothAudio, !devices.isCar(uid: connected.uid) {
                    Button("Mark \"\(connected.name)\" as my car", systemImage: "plus.circle") {
                        devices.addCar(connected)
                        autoDrive.refresh()
                    }
                }
            } header: {
                Text("Car Bluetooth")
            } footer: {
                Text("CarPlay is detected automatically. For Bluetooth, connect to your car and mark it here so headphones don't start trips.")
            }

            Section {
                if let id = devices.bleAccessoryID {
                    LabeledContent("Paired", value: bleMonitor.isConnected ? "Connected" : "Not connected")
                    Button("Forget accessory", role: .destructive) {
                        bleMonitor.forgetAccessory()
                    }
                    .id(id)
                } else {
                    NavigationLink("Pair an accessory") { AccessoryPickerView() }
                }
            } header: {
                Text("BLE accessory (optional)")
            } footer: {
                Text("An OBD-II or other Bluetooth LE dongle that powers on with your car.")
            }
        }
        .navigationTitle("Settings")
    }

    private var locationText: String {
        switch permissions.locationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using — tap to allow Always"
        case .denied, .restricted: "Denied — enable in Settings"
        default: "Not set"
        }
    }

    private var motionText: String {
        switch permissions.motionStatus {
        case .authorized: "Allowed"
        case .denied, .restricted: "Denied — enable in Settings"
        default: "Not set"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        Button(action: request) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isGranted ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isGranted ? .green : .secondary)
            }
        }
        .disabled(isGranted)
    }
}
