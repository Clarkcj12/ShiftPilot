import SwiftData
import SwiftUI

/// Splits a trip at the stops where the car was parked, for a trip that ran on through
/// a long break or the drive home.
struct SplitTripView: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var shifts: [Shift]
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var stops: [TripEditor.Stop]?
    @State private var selected: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                if let stops {
                    if stops.isEmpty {
                        ContentUnavailableView(
                            "No stops to split at",
                            systemImage: "parkingsign",
                            description: Text("This trip has no stops of 5 minutes or longer.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(stops) { stop in
                                Toggle(isOn: binding(for: stop)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(stop.start.formatted(date: .omitted, time: .shortened)) – \(stop.end.formatted(date: .omitted, time: .shortened))")
                                        Text("Parked \(Format.duration(stop.duration)) · after \(unit.format(meters: stop.metersBefore))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text("Split at these stops")
                        } footer: {
                            Text("Each new trip joins the shift it overlaps and counts as business. Trips outside a shift go to Review so you can mark them. GPS drift while parked isn't counted.")
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Split trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(splitTitle) {
                        let chosen = (stops ?? []).filter { selected.contains($0.id) }
                        TripEditor.split(trip, at: chosen, shifts: shifts, in: context)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                let samples = trip.points
                    .sorted { $0.timestamp < $1.timestamp }
                    .map { TripEditor.Sample(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude) }
                let found = TripEditor.stops(in: samples)
                selected = Set(found.filter { $0.duration >= TripEditor.suggestedStop }.map(\.id))
                stops = found
            }
        }
    }

    private var splitTitle: String {
        selected.isEmpty ? "Split" : "Split into \(selected.count + 1)"
    }

    private func binding(for stop: TripEditor.Stop) -> Binding<Bool> {
        Binding {
            selected.contains(stop.id)
        } set: { isOn in
            if isOn { selected.insert(stop.id) } else { selected.remove(stop.id) }
        }
    }
}
