import SwiftUI

/// A decimal-pad field that updates its value on every keystroke (a formatted
/// `TextField` only commits when editing ends, which the number pad can't trigger).
struct DecimalField: View {
    let placeholder: String
    @Binding var value: Decimal?
    var isCurrency = false

    @State private var text = ""

    init(_ placeholder: String, value: Binding<Decimal?>, isCurrency: Bool = false) {
        self.placeholder = placeholder
        _value = value
        self.isCurrency = isCurrency
    }

    var body: some View {
        HStack(spacing: 1) {
            Spacer(minLength: 0)
            if isCurrency {
                Text(Locale.current.currencySymbol ?? "$")
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
            }
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize()
        }
        .onAppear {
            text = value.map { $0.formatted(.number.grouping(.never)) } ?? ""
        }
        .onChange(of: text) { _, newText in
            value = newText.isEmpty ? nil : Decimal(string: newText, locale: .current)
        }
    }
}
