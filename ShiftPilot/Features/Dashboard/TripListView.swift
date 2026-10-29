import SwiftData
import SwiftUI

struct TripListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case review = "Review"
        case business = "Business"
        case personal = "Personal"

        var id: Self { self }

        func includes(_ trip: Trip) -> Bool {
            switch self {
            case .all: true
            case .review: trip.purpose == nil
            case .business: trip.purpose == .business
            case .personal: trip.purpose == .personal
            }
        }
    }

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @State private var filter: Filter

    init(filter: Filter = .all) {
        _filter = State(initialValue: filter)
    }

    var body: some View {
        let shown = trips.filter(filter.includes)
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if shown.isEmpty {
                Section {
                    ContentUnavailableView(emptyTitle, systemImage: "car", description: Text(emptyDescription))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(shown) { trip in
                        TripLink(trip: trip)
                    }
                } footer: {
                    Text("Swipe right to mark a trip business or personal, left to delete it.")
                }
            }
        }
        .navigationTitle("Trips")
    }

    private var emptyTitle: String {
        filter == .review ? "All trips reviewed" : "No trips"
    }

    private var emptyDescription: String {
        switch filter {
        case .all: "Drives you take will show up here."
        case .review: "Trips logged outside a shift show up here so you can mark them business or personal."
        case .business, .personal: "No \(filter.rawValue.lowercased()) trips yet."
        }
    }
}

/// A trip row that opens the trip and has classify/delete swipe actions.
struct TripLink: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripRow(trip: trip)
        }
        .swipeActions(edge: .leading) {
            ForEach(TripPurpose.allCases.reversed()) { purpose in
                if trip.purpose != purpose {
                    Button(purpose.name, systemImage: purpose.symbol) {
                        TripEditor.setPurpose(purpose, for: trip, in: context)
                    }
                    .tint(purpose.color)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if TripEditor.canDelete(trip) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .confirmationDialog("Delete this trip?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete trip", role: .destructive) {
                TripEditor.delete(trip, in: context)
            }
        } message: {
            Text("Its miles and route will be removed.")
        }
    }
}

struct TripRow: View {
    let trip: Trip

    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                Text(trip.sourceDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(unit.format(meters: trip.distanceMeters))
                    .monospacedDigit()
                PurposeBadge(purpose: trip.purpose)
            }
        }
    }
}

struct PurposeBadge: View {
    let purpose: TripPurpose?

    var body: some View {
        Text(purpose?.name ?? "Review")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var color: Color {
        purpose?.color ?? .orange
    }
}

extension TripPurpose {
    var color: Color {
        switch self {
        case .business: .green
        case .personal: .gray
        }
    }

    var symbol: String {
        switch self {
        case .business: "briefcase.fill"
        case .personal: "house.fill"
        }
    }
}

extension Trip {
    var sourceName: String {
        switch trigger {
        case .carPlay: "CarPlay"
        case .bluetoothAudio: "Car Bluetooth"
        case .bleAccessory: "Accessory"
        case .motion: "Motion"
        case .manual: "Manual"
        case nil: "Unknown"
        }
    }

    var sourceDetail: String {
        guard let endedAt else { return "\(sourceName) · In progress" }
        return "\(sourceName) · \(Format.duration(endedAt.timeIntervalSince(startedAt)))"
    }
}
