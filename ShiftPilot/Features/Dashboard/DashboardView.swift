import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AutoDriveDetectionManager.self) private var autoDrive
    @Environment(MileageTracker.self) private var tracker
    @Environment(PermissionsManager.self) private var permissions
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Shift.startedAt, order: .reverse) private var shifts: [Shift]
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault

    var body: some View {
        NavigationStack {
            List {
                if !permissions.isFullyAuthorized {
                    Section {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Finish setup so ShiftPilot can log drives automatically", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    ShiftCard()
                }

                Section("Drive") {
                    StatusRow(
                        phase: autoDrive.state.phase,
                        distance: tracker.isTracking ? unit.format(meters: tracker.distanceMeters) : nil
                    )
                    TripControlButton(phase: autoDrive.state.phase) {
                        autoDrive.startTripManually()
                    } end: {
                        autoDrive.endTripManually()
                    }
                }

                Section("Today") {
                    let today = todayShifts.map { $0.snapshot() }
                    let gross = today.reduce(Decimal(0)) { $0 + $1.gross }
                    let seconds = today.reduce(0) { $0 + $1.duration }
                    LabeledContent("Earnings", value: Format.money(gross))
                    LabeledContent("True EPH", value: Format.rate(EarningsCalculator.hourlyRate(gross, over: seconds), per: "hr"))
                    LabeledContent("Distance", value: unit.format(meters: todayMeters))
                    LabeledContent("Trips", value: "\(todayTrips.count)")
                }

                if !shifts.isEmpty {
                    Section {
                        ForEach(shifts.prefix(3)) { shift in
                            NavigationLink {
                                ShiftDetailView(shift: shift)
                            } label: {
                                ShiftRow(shift: shift)
                            }
                        }
                    } header: {
                        SectionHeader(title: "Recent shifts") { ShiftListView() }
                    }
                }

                Section {
                    ForEach(trips.prefix(3)) { trip in
                        TripRow(trip: trip)
                    }
                } header: {
                    SectionHeader(title: "Recent trips") { TripListView() }
                }
            }
            .navigationTitle("ShiftPilot")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        EarningsInsightsView()
                    } label: {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    private var todayShifts: [Shift] {
        shifts.filter { $0.startedAt >= startOfToday || $0.isActive }
    }

    private var todayTrips: [Trip] {
        trips.filter { $0.startedAt >= startOfToday }
    }

    private var todayMeters: Double {
        todayTrips.reduce(0) { $0 + $1.distanceMeters }
    }
}

private struct SectionHeader<Destination: View>: View {
    let title: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            NavigationLink("See all", destination: destination)
                .font(.footnote)
        }
    }
}

private struct TripControlButton: View {
    let phase: DetectorState.Phase
    let start: () -> Void
    let end: () -> Void

    @State private var isConfirmingEnd = false

    var body: some View {
        switch phase {
        case .idle, .candidate:
            Button(action: start) {
                Label(phase == .idle ? "Start trip" : "Start trip now", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        case .driving, .ending:
            Button(role: .destructive) {
                isConfirmingEnd = true
            } label: {
                Label("End trip", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .confirmationDialog("End this trip?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
                Button("End trip", role: .destructive, action: end)
            } message: {
                Text("The miles logged so far will be saved.")
            }
        }
    }
}

private struct StatusRow: View {
    let phase: DetectorState.Phase
    /// Formatted live trip distance, or nil when not tracking.
    let distance: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let distance {
                Text(distance)
                    .font(.title3.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch phase {
        case .idle: "Waiting for a drive"
        case .candidate: "Checking for a drive…"
        case .driving: "Driving"
        case .ending: "Wrapping up trip"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle: "Trips start automatically when you connect to your car or start driving."
        case .candidate: "Motion suggests you're in a car. Confirming with GPS speed."
        case .driving: "Logging your trip"
        case .ending: "Trip ends after you've been parked a few minutes."
        }
    }

    private var symbol: String {
        switch phase {
        case .idle: "car"
        case .candidate: "questionmark.circle"
        case .driving: "car.fill"
        case .ending: "parkingsign.circle"
        }
    }

    private var tint: Color {
        switch phase {
        case .idle: .secondary
        case .candidate: .orange
        case .driving: .green
        case .ending: .blue
        }
    }
}
