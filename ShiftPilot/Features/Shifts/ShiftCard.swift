import SwiftUI

/// Dashboard hero: live True EPH for the active shift, or a Start shift button.
struct ShiftCard: View {
    @Environment(ShiftManager.self) private var shifts

    var body: some View {
        if let shift = shifts.activeShift {
            ActiveShiftCard(shift: shift)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not on shift").font(.headline)
                    Text("Start a shift to track your true earnings per hour across every app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    shifts.startShift()
                } label: {
                    Label("Start shift", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct ActiveShiftCard: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(GarageStore.self) private var garage
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isAddingPayout = false
    @State private var isConfirmingEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = shift.snapshot(now: context.date, costPerMeter: garage.costPerMeter)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("On shift", systemImage: "clock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(Format.duration(snapshot.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.rate(snapshot.hourlyRate, per: "hr"))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("True earnings per hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top) {
                    ShiftMetric(title: "Earned", value: Format.money(snapshot.gross))
                    ShiftMetric(title: "Net", value: snapshot.netProfit.map(Format.money) ?? "—")
                    ShiftMetric(title: "Distance", value: unit.format(meters: snapshot.distanceMeters))
                }

                HStack {
                    Button {
                        isAddingPayout = true
                    } label: {
                        Label("Payout", systemImage: "plus")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        isConfirmingEnd = true
                    } label: {
                        Label("End shift", systemImage: "stop.fill")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $isAddingPayout) {
            AddPayoutView(shift: shift)
        }
        .endShiftDialog(shift: shift, isPresented: $isConfirmingEnd, isAddingPayout: $isAddingPayout)
    }
}

extension View {
    /// Confirms ending a shift. A shift with no payouts can't end: the dialog offers
    /// to add one (platform and amount are required there) or discard the shift.
    func endShiftDialog(shift: Shift, isPresented: Binding<Bool>, isAddingPayout: Binding<Bool>) -> some View {
        modifier(EndShiftDialog(shift: shift, isPresented: isPresented, isAddingPayout: isAddingPayout))
    }
}

private struct EndShiftDialog: ViewModifier {
    let shift: Shift
    @Binding var isPresented: Bool
    @Binding var isAddingPayout: Bool

    @Environment(ShiftManager.self) private var shifts

    func body(content: Content) -> some View {
        let canEnd = ShiftManager.canEnd(shift)
        content.confirmationDialog(
            canEnd ? "End this shift?" : "Add a payout first",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            if canEnd {
                Button("End shift", role: .destructive) { shifts.endShift() }
            } else {
                Button("Add payout") { isAddingPayout = true }
                Button("Discard shift", role: .destructive) { shifts.deleteShift(shift) }
            }
        } message: {
            Text(canEnd
                ? "You can still add payouts to it afterwards."
                : "A shift needs at least one payout, with the app that paid you, before it can end. Discard it if you didn't work.")
        }
    }
}

struct ShiftMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
