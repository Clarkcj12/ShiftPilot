import MapKit
import SwiftData
import SwiftUI

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isConfirmingDelete = false
    /// Deleted once the view is gone, so it never renders a deleted model.
    @State private var deleteOnDisappear = false

    var body: some View {
        let route = trip.points
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        List {
            if route.count > 1 {
                Section {
                    Map(interactionModes: [.pan, .zoom]) {
                        MapPolyline(coordinates: route)
                            .stroke(.blue, lineWidth: 4)
                        if let start = route.first {
                            Marker("Start", systemImage: "flag.fill", coordinate: start).tint(.green)
                        }
                        if let end = route.last {
                            Marker("End", systemImage: "flag.checkered", coordinate: end).tint(.red)
                        }
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Picker("Purpose", selection: purpose) {
                    ForEach(TripPurpose.allCases) { Text($0.name).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Purpose")
            } footer: {
                Text(purposeFooter)
            }

            Section("Trip") {
                LabeledContent("Distance", value: unit.format(meters: trip.distanceMeters))
                LabeledContent("Started", value: trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let endedAt = trip.endedAt {
                    LabeledContent("Ended", value: endedAt.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Duration", value: Format.duration(endedAt.timeIntervalSince(trip.startedAt)))
                } else {
                    LabeledContent("Status", value: "In progress")
                }
                LabeledContent("Detected by", value: trip.sourceName)
            }

            Section {
                Button("Delete trip", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .foregroundStyle(.red)
                .confirmationDialog("Delete this trip?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete trip", role: .destructive) {
                        deleteOnDisappear = true
                        dismiss()
                    }
                } message: {
                    Text("Its miles and route will be removed.")
                }
                .disabled(!TripEditor.canDelete(trip))
            } footer: {
                if !TripEditor.canDelete(trip) {
                    Text("End the trip before deleting it.")
                }
            }
        }
        .navigationTitle(trip.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if deleteOnDisappear {
                TripEditor.delete(trip, in: context)
            }
        }
    }

    private var purpose: Binding<TripPurpose?> {
        Binding {
            trip.purpose
        } set: { newValue in
            if let newValue {
                TripEditor.setPurpose(newValue, for: trip, in: context)
            }
        }
    }

    private var purposeFooter: String {
        switch trip.purpose {
        case nil: "Logged outside a shift. Mark it business if you were working, such as driving to your first pickup."
        case .business where trip.shift != nil: "Logged during a shift, so it was marked business automatically."
        case .business: "Counts toward your business miles."
        case .personal: "Not counted toward business miles or shift distance."
        }
    }
}
