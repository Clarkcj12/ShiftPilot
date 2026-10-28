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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(trip.miles, format: .number.precision(.fractionLength(1))) mi")
                .monospacedDigit()
        }
    }

    private var detail: String {
        let source = switch trip.trigger {
        case .carPlay: "CarPlay"
        case .bluetoothAudio: "Car Bluetooth"
        case .bleAccessory: "Accessory"
        case .motion: "Motion"
        case nil: "Unknown"
        }
        guard let endedAt = trip.endedAt else { return "\(source) · In progress" }
        let duration = Duration.seconds(endedAt.timeIntervalSince(trip.startedAt))
        return "\(source) · \(duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))"
    }
}
