import SwiftUI

/// Pick any day and time (on your clock) and every city follows.
struct DateJumpView: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Date and time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)
                Text("Times round to the nearest quarter-hour.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .background(Theme.bg)
            .navigationTitle("Go to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        store.jump(to: date.addingTimeInterval(450))  // nearest quarter-hour
                        dismiss()
                    }
                }
            }
            .onAppear { date = store.moment }
        }
        .tint(Theme.cream)
        .preferredColorScheme(.dark)
    }
}
