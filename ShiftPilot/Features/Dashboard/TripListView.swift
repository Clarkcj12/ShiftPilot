import SwiftData
import SwiftUI

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]

    var body: some View {
        List {
            ForEach(trips) { trip in
                TripRow(trip: trip)
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(trips[index])
                }
            }
        }
        .overlay {
            if trips.isEmpty {
                ContentUnavailableView("No trips yet", systemImage: "car", description: Text("Drives you take will show up here."))
            }
        }
        .navigationTitle("Trips")
    }
}

struct TripRow: View {
    let trip: Trip

    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(unit.format(meters: trip.distanceMeters))
                .monospacedDigit()
        }
    }

    private var detail: String {
        let source = switch trip.trigger {
        case .carPlay: "CarPlay"
        case .bluetoothAudio: "Car Bluetooth"
        case .bleAccessory: "Accessory"
        case .motion: "Motion"
        case .manual: "Manual"
        case nil: "Unknown"
        }
        guard let endedAt = trip.endedAt else { return "\(source) · In progress" }
        return "\(source) · \(Format.duration(endedAt.timeIntervalSince(trip.startedAt)))"
    }
}
