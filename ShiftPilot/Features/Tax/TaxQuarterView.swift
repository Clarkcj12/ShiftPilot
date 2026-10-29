import SwiftData
import SwiftUI

struct TaxQuarterView: View {
    let estimate: QuarterEstimate

    @Environment(\.modelContext) private var context
    @Query(sort: \TaxPayment.paidAt) private var allPayments: [TaxPayment]
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isRecording = false

    var body: some View {
        let quarter = estimate.quarter
        let payments = allPayments.filter { $0.year == quarter.year && $0.quarterNumber == quarter.number }
        let paid = payments.reduce(Decimal(0)) { $0 + $1.amount }

        List {
            Section {
                LabeledContent("Period", value: "\(quarter.months) \(String(quarter.year))")
                LabeledContent("Due", value: quarter.dueDate().formatted(date: .long, time: .omitted))
                LabeledContent("Set aside", value: Format.money(estimate.setAside))
                LabeledContent("Paid", value: Format.money(paid))
                LabeledContent("Remaining", value: Format.money(max(0, estimate.setAside - paid)))
            }

            Section("This period") {
                LabeledContent("Earnings", value: Format.money(estimate.gross))
                LabeledContent("Business distance", value: unit.format(meters: estimate.businessMeters))
                LabeledContent("Mileage deduction", value: Format.money(estimate.mileageDeduction))
                LabeledContent("Net profit", value: Format.money(estimate.netProfit))
                LabeledContent("Self-employment tax", value: Format.money(estimate.selfEmploymentTax))
                LabeledContent("Income tax", value: Format.money(estimate.incomeTax))
            }

            Section {
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(payment.paidAt, format: .dateTime.month().day().year())
                            if !payment.note.isEmpty {
                                Text(payment.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Format.money(payment.amount)).monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(payments[index])
                    }
                    try? context.save()
                }

                Button("Record payment", systemImage: "plus") {
                    isRecording = true
                }
            } header: {
                Text("Payments")
            } footer: {
                Text("Record what you paid the IRS, or what you moved into a tax savings account, for this period.")
            }
        }
        .navigationTitle("\(quarter.title) \(String(quarter.year))")
        .sheet(isPresented: $isRecording) {
            RecordTaxPaymentView(quarter: quarter, suggested: max(0, estimate.setAside - paid))
        }
    }
}

private struct RecordTaxPaymentView: View {
    let quarter: TaxQuarter

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal?
    @State private var paidAt = Date.now
    @State private var note = ""

    init(quarter: TaxQuarter, suggested: Decimal) {
        self.quarter = quarter
        _amount = State(initialValue: suggested > 0 ? suggested : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("Amount", value: $amount, format: .currency(code: Format.currencyCode))
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                }
                Section {
                    DatePicker("Paid on", selection: $paidAt, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount, amount > 0 else { return }
                        context.insert(TaxPayment(amount: amount, paidAt: paidAt, quarter: quarter, note: note))
                        try? context.save()
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}
