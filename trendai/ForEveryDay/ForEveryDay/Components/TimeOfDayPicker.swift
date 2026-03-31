import SwiftUI

struct TimeOfDayPicker: View {
    let label: String
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker(
            label,
            selection: dateBinding,
            displayedComponents: .hourAndMinute
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.year = 2000
                c.month = 1
                c.day = 1
                c.hour = time.hour
                c.minute = time.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                time = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }
}
