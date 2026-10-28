import SwiftData
import SwiftUI

struct ShiftListView: View {
    @Environment(ShiftManager.self) private var shifts
    @Query(sort: \Shift.startedAt, order: .reverse) private var allShifts: [Shift]

    var body: some View {
        List {
            ForEach(allShifts) { shift in
                NavigationLink {
                    ShiftDetailView(shift: shift)
                } label: {
                    ShiftRow(shift: shift)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    shifts.deleteShift(allShifts[index])
                }
            }
        }
        .overlay {
            if allShifts.isEmpty {
                ContentUnavailableView("No shifts yet", systemImage: "clock", description: Text("Start a shift from the dashboard to track your earnings."))
            }
        }
        .navigationTitle("Shifts")
    }
}

struct ShiftRow: View {
    let shift: Shift

    var body: some View {
        let snapshot = shift.snapshot()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shift.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                if shift.isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Spacer()
                Text(Format.money(snapshot.gross))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            HStack {
                Text("\(Format.duration(snapshot.duration)) · \(Format.rate(snapshot.hourlyRate, per: "hr"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PlatformPills(platforms: Set(snapshot.payouts.map(\.platform)))
            }
        }
    }
}
