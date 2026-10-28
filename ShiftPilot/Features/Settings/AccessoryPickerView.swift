import SwiftUI

struct AccessoryPickerView: View {
    @Environment(BLEAccessoryMonitor.self) private var bleMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(bleMonitor.discovered.sorted { $0.rssi > $1.rssi }) { accessory in
            Button {
                bleMonitor.pair(accessory)
                dismiss()
            } label: {
                HStack {
                    Text(accessory.name)
                    Spacer()
                    Text("\(accessory.rssi) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if bleMonitor.discovered.isEmpty {
                ContentUnavailableView("Searching…", systemImage: "antenna.radiowaves.left.and.right", description: Text("Turn on your car so the accessory powers up."))
            }
        }
        .navigationTitle("Pair accessory")
        .onAppear { bleMonitor.startScan() }
        .onDisappear { bleMonitor.stopScan() }
    }
}
