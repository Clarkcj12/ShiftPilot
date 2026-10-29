import SwiftData
import SwiftUI

/// Adds or edits an expense. Amount first, then a category.
struct ExpenseEditorView: View {
    let expense: Expense?

    @Environment(GarageStore.self) private var garage
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var amount: Decimal?
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var vehicle: Vehicle?
    @State private var isForWork: Bool
    /// Once the driver flips the toggle, stop re-deriving its default.
    @State private var hasChosenForWork: Bool
    @State private var businessPercent: Decimal?
    @State private var note: String
    @State private var isConfirmingDelete = false
    @State private var deleteOnDisappear = false

    /// - Parameters:
    ///   - shift: pre-links a new expense to this shift (and its date).
    init(expense: Expense? = nil, category: ExpenseCategory = .tolls, shift: Shift? = nil) {
        self.expense = expense
        let category = expense?.category ?? category
        _amount = State(initialValue: expense?.amount)
        _category = State(initialValue: category)
        _date = State(initialValue: expense?.date ?? shift.map { $0.endedAt ?? .now } ?? .now)
        _vehicle = State(initialValue: expense?.vehicle)
        _isForWork = State(initialValue: (expense?.businessUse ?? 1) > 0)
        _hasChosenForWork = State(initialValue: expense != nil)
        _businessPercent = State(initialValue: expense?.businessUse.map { $0 * 100 })
        _note = State(initialValue: expense?.note ?? "")
    }

    var body: some View {
        let activeVehicles = vehicles.filter { !$0.isRetired || $0 == vehicle }
        let linkedShift = category.linksToShift ? garage.shift(containing: date) : nil
        let suggestion = (vehicle ?? garage.current)?.suggestedBusinessUse(in: Calendar.current.component(.year, from: date))

        NavigationStack {
            Form {
                Section {
                    DecimalField("0.00", value: $amount, isCurrency: true, autoFocus: expense == nil)
                        .font(.title.monospacedDigit())
                } footer: {
                    if let hint = category.hint {
                        Text(hint)
                    }
                }

                Section("Category") {
                    CategoryPicker(selection: $category)
                }

                Section {
                    switch category.businessUseKind {
                    case .toggle:
                        Toggle("For gig work", isOn: Binding {
                            isForWork
                        } set: {
                            isForWork = $0
                            hasChosenForWork = true
                        })
                    case .percentage:
                        LabeledContent("Business use") {
                            HStack(spacing: 2) {
                                DecimalField("e.g. 60", value: $businessPercent)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                        if let suggestion, businessPercent == nil {
                            Button("Use \((suggestion * 100).formatted(.number.precision(.fractionLength(0))))% from your mileage") {
                                businessPercent = TaxCalculator.round(suggestion * 100)
                            }
                        }
                    }
                } footer: {
                    Text(businessUseFooter(linkedShift: linkedShift, suggestion: suggestion))
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now)
                    if activeVehicles.count > 1 {
                        Picker("Vehicle", selection: $vehicle) {
                            Text("None").tag(Vehicle?.none)
                            ForEach(activeVehicles) { Text($0.displayName).tag(Optional($0)) }
                        }
                    }
                    TextField("Note (optional)", text: $note)
                }

                Section {
                    TreatmentBadges(category: category)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                if expense != nil {
                    Section {
                        Button("Delete expense", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .foregroundStyle(.red)
                        .confirmationDialog("Delete this expense?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete expense", role: .destructive) {
                                deleteOnDisappear = true
                                dismiss()
                            }
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(expense == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(linkedShift: linkedShift) }
                        .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                if expense == nil, vehicle == nil {
                    vehicle = garage.current
                }
                updateForWorkDefault()
            }
            .onChange(of: category) { updateForWorkDefault() }
            .onChange(of: date) { updateForWorkDefault() }
            .onDisappear {
                if deleteOnDisappear, let expense {
                    garage.delete(expense)
                }
            }
        }
    }

    private func updateForWorkDefault() {
        guard !hasChosenForWork else { return }
        isForWork = category.defaultsToWork(duringShift: garage.shift(containing: date) != nil)
    }

    private var businessUse: Decimal? {
        switch category.businessUseKind {
        case .toggle: isForWork ? 1 : 0
        case .percentage: businessPercent.map { min(100, max(0, $0)) / 100 }
        }
    }

    private func businessUseFooter(linkedShift: Shift?, suggestion: Decimal?) -> String {
        switch category.businessUseKind {
        case .toggle:
            if let linkedShift {
                return "Added to your shift on \(linkedShift.startedAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return category.linksToShift
                ? "No shift was running at this time. Turn this on only if you were working."
                : "Turn off if this was for personal use."
        case .percentage:
            let base = "The share used for gig work. Only that share is deducted or counted against profit."
            return suggestion == nil ? base + " Log odometer readings or fill-ups to get a suggestion from your mileage." : base
        }
    }

    private func save(linkedShift: Shift?) {
        guard let amount, amount > 0 else { return }
        let target = expense ?? Expense(date: date, amount: amount, category: category, businessUse: businessUse)
        target.date = date
        target.amount = amount
        target.category = category
        target.businessUse = businessUse
        target.note = note
        target.vehicle = vehicle
        target.shift = linkedShift
        if expense == nil {
            garage.add(target)
        } else {
            garage.save()
        }
        dismiss()
    }
}

/// Plain-language tax and profit treatment for a category.
struct TreatmentBadges: View {
    let category: ExpenseCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(taxText, systemImage: taxSymbol)
                .foregroundStyle(taxColor)
            Label(category.isInPerMileCost ? "Already in your cost per mile, so it doesn't lower net profit again" : "Lowers your net profit", systemImage: "chart.line.downtrend.xyaxis")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    private var taxText: String {
        switch category.taxTreatment {
        case .addedDeduction: "Added to your tax deductions"
        case .coveredByMileageRate: "Already counted in your mileage deduction"
        case .neverDeductible: "Not tax deductible"
        case .notCounted: "Not counted for taxes; ask a tax professional"
        }
    }

    private var taxSymbol: String {
        switch category.taxTreatment {
        case .addedDeduction: "plus.circle.fill"
        case .coveredByMileageRate: "checkmark.circle"
        case .neverDeductible: "xmark.circle"
        case .notCounted: "questionmark.circle"
        }
    }

    private var taxColor: Color {
        category.taxTreatment == .addedDeduction ? .green : .secondary
    }
}

/// Wrapping grid of category chips.
struct CategoryPicker: View {
    @Binding var selection: ExpenseCategory

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(ExpenseCategory.allCases) { category in
                Button {
                    selection = category
                } label: {
                    Label(category.name, systemImage: category.symbol)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .foregroundStyle(selection == category ? .white : .primary)
                        .background(selection == category ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == category ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        let snapshot = expense.snapshot
        HStack {
            Image(systemName: expense.category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category.name)
                Text(detail(snapshot))
                    .font(.caption)
                    .foregroundStyle(snapshot.needsBusinessUse ? .orange : .secondary)
            }
            Spacer()
            Text(Format.money(expense.amount)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ snapshot: ExpenseSnapshot) -> String {
        let date = expense.date.formatted(.dateTime.month(.abbreviated).day())
        if snapshot.needsBusinessUse { return "\(date) · Needs business share" }
        if snapshot.deductibleAmount > 0 { return "\(date) · Deductible \(Format.money(TaxCalculator.round(snapshot.deductibleAmount)))" }
        if expense.category.businessUseKind == .toggle, (expense.businessUse ?? 0) == 0 { return "\(date) · Personal" }
        return expense.note.isEmpty ? date : "\(date) · \(expense.note)"
    }
}

/// All expenses grouped by month.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(GarageStore.self) private var garage
    @State private var isAdding = false
    @State private var editing: Expense?

    var body: some View {
        let months = Dictionary(grouping: expenses) { Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            .sorted { $0.key > $1.key }

        List {
            if expenses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No expenses yet", systemImage: "receipt")
                    } description: {
                        Text("Tolls and parking while you work are deductible on top of your mileage. Log them as you go.")
                    } actions: {
                        Button("Add tolls or parking") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(months, id: \.key) { month, items in
                Section {
                    ForEach(items) { expense in
                        Button {
                            editing = expense
                        } label: {
                            ExpenseRow(expense: expense).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            garage.delete(items[index])
                        }
                    }
                } header: {
                    HStack {
                        Text(month, format: .dateTime.month(.wide).year())
                        Spacer()
                        Text(Format.money(items.reduce(0) { $0 + $1.amount }))
                    }
                } footer: {
                    let deductible = items.reduce(Decimal(0)) { $0 + $1.snapshot.deductibleAmount }
                    if deductible > 0 {
                        Text("\(Format.money(TaxCalculator.round(deductible))) added to deductions")
                    }
                }
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            Button("Add expense", systemImage: "plus") { isAdding = true }
        }
        .sheet(isPresented: $isAdding) {
            ExpenseEditorView()
        }
        .sheet(item: $editing) { expense in
            ExpenseEditorView(expense: expense)
        }
    }
}
