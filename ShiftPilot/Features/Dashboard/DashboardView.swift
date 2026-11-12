import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AutoDriveDetectionManager.self) private var autoDrive
    @Environment(MileageTracker.self) private var tracker
    @Environment(PermissionsManager.self) private var permissions
    @Environment(GarageStore.self) private var garage
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Shift.startedAt, order: .reverse) private var shifts: [Shift]
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isLoggingFillUp = false
    @State private var isAddingExpense = false

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
                    ShiftCard(today: todayTotals)
                }

                Section {
                    DriveStatusRow(
                        phase: autoDrive.state.phase,
                        liveDistance: tracker.isTracking ? unit.format(meters: tracker.distanceMeters) : nil,
                        todaySummary: todayTrips.isEmpty ? nil : "\(unit.format(meters: todayMeters)) today · \(unit.format(meters: todayBusinessMeters)) business",
                        start: { autoDrive.startTripManually() },
                        end: { autoDrive.endTripManually() }
                    )
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

                let toReview = trips.filter { $0.purpose == nil && !$0.isActive }
                if !toReview.isEmpty {
                    Section {
                        ForEach(toReview.prefix(3)) { trip in
                            ReviewTripRow(trip: trip)
                        }
                        if toReview.count > 3 {
                            NavigationLink("Review \(toReview.count - 3) more") { TripListView(filter: .review) }
                        }
                    } header: {
                        Text("Work or personal?")
                    } footer: {
                        Text("Only business trips count toward your mileage deduction.")
                    }
                }

                Section {
                    ForEach(trips.prefix(3)) { trip in
                        TripLink(trip: trip)
                    }
                } header: {
                    SectionHeader(title: "Recent trips") { TripListView() }
                }
            }
            .navigationTitle("Today")
            .sheet(isPresented: $isLoggingFillUp) {
                if let vehicle = garage.current {
                    FillUpEditorView(vehicle: vehicle)
                }
            }
            .sheet(isPresented: $isAddingExpense) {
                ExpenseEditorView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if autoDrive.state.phase == .idle || autoDrive.state.phase == .candidate {
                            Button("Start trip now", systemImage: "car.fill") { autoDrive.startTripManually() }
                        }
                        if garage.current != nil {
                            Button("Log fill-up", systemImage: "fuelpump") { isLoggingFillUp = true }
                        }
                        Button("Add expense", systemImage: "receipt") { isAddingExpense = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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

    private var todayBusinessTrips: [Trip] {
        todayTrips.filter { $0.purpose == .business }
    }

    private var todayBusinessMeters: Double {
        todayBusinessTrips.reduce(0) { $0 + $1.distanceMeters }
    }

    private var todayTotals: TodayTotals {
        let today = todayShifts.filter { !$0.isActive }.map { $0.snapshot(costPerMeter: garage.costPerMeter) }
        return TodayTotals(
            gross: today.reduce(0) { $0 + $1.gross },
            seconds: today.reduce(0) { $0 + $1.duration },
            net: NetProfit.total(today),
            deduction: todayDeduction,
            hasHistory: !shifts.isEmpty
        )
    }

    private var todayDeduction: Decimal {
        let business = todayBusinessTrips
            .map { TaxMileage(meters: $0.distanceMeters, date: $0.startedAt) }
        return TaxCalculator.round(business.reduce(0) { $0 + TaxCalculator.deduction(for: $1) })
    }
}

/// A trip waiting for a purpose, with one-tap Business and Personal buttons.
private struct ReviewTripRow: View {
    let trip: Trip

    @Environment(\.modelContext) private var context
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(trip.startedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                Spacer()
                Text(unit.format(meters: trip.distanceMeters)).monospacedDigit()
            }
            HStack {
                ForEach(TripPurpose.allCases) { purpose in
                    Button(purpose.name, systemImage: purpose.symbol) {
                        withAnimation { TripEditor.setPurpose(purpose, for: trip, in: context) }
                    }
                    .buttonStyle(.bordered)
                    .tint(purpose.color)
                    .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.selection, trigger: trip.purposeRawValue)
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

/// One line: what auto-detection is doing, today's miles, and a manual start or end.
private struct DriveStatusRow: View {
    let phase: DetectorState.Phase
    /// Formatted live trip distance, or nil when not tracking.
    let liveDistance: String?
    let todaySummary: String?
    let start: () -> Void
    let end: () -> Void

    @State private var isConfirmingEnd = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: phase == .driving)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let liveDistance {
                Text(liveDistance)
                    .font(Theme.metric)
            }
            switch phase {
            case .idle, .candidate:
                Button("Start", action: start)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Start trip")
            case .driving, .ending:
                Button("End", role: .destructive) { isConfirmingEnd = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("End trip")
                    .confirmationDialog("End this trip?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
                        Button("End trip", role: .destructive, action: end)
                    } message: {
                        Text("The miles logged so far will be saved.")
                    }
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch phase {
        case .idle: "Ready to log drives"
        case .candidate: "Checking for a drive…"
        case .driving: "Driving"
        case .ending: "Wrapping up trip"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle: todaySummary ?? "Starts automatically when you drive"
        case .candidate: "Confirming with GPS speed"
        case .driving: "Logging this trip"
        case .ending: "Ends after a few minutes parked"
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
