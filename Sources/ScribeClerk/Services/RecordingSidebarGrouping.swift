import Foundation

struct RecordingSidebarSection: Identifiable {
    let id: String
    let title: String
    let recordings: [RecordingRecord]
}

enum RecordingSidebarGrouping {
    static func sections(
        for recordings: [RecordingRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [RecordingSidebarSection] {
        let sorted = recordings.sorted {
            if $0.displayDate != $1.displayDate {
                return $0.displayDate > $1.displayDate
            }
            return $0.importedAt > $1.importedAt
        }

        guard !sorted.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return [RecordingSidebarSection(id: "all", title: "All", recordings: sorted)]
        }

        var todayItems: [RecordingRecord] = []
        var thisWeekItems: [RecordingRecord] = []
        var olderByWeek: [Date: [RecordingRecord]] = [:]

        for recording in sorted {
            let displayDay = calendar.startOfDay(for: recording.displayDate)

            if displayDay == today {
                todayItems.append(recording)
            } else if recording.displayDate >= currentWeek.start && recording.displayDate < today {
                thisWeekItems.append(recording)
            } else if let weekStart = calendar.dateInterval(of: .weekOfYear, for: recording.displayDate)?.start {
                olderByWeek[weekStart, default: []].append(recording)
            }
        }

        var sections: [RecordingSidebarSection] = []

        if !todayItems.isEmpty {
            sections.append(RecordingSidebarSection(id: "today", title: "Today", recordings: todayItems))
        }

        if !thisWeekItems.isEmpty {
            sections.append(RecordingSidebarSection(id: "this-week", title: "This Week", recordings: thisWeekItems))
        }

        for weekStart in olderByWeek.keys.sorted(by: >) {
            guard let items = olderByWeek[weekStart], !items.isEmpty else { continue }
            sections.append(
                RecordingSidebarSection(
                    id: "week-\(Int(weekStart.timeIntervalSince1970))",
                    title: weekLabel(for: weekStart, calendar: calendar, now: now),
                    recordings: items
                )
            )
        }

        return sections
    }

    private static func weekLabel(for weekStart: Date, calendar: Calendar, now: Date) -> String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let currentYear = calendar.component(.year, from: now)
        let weekYear = calendar.component(.year, from: weekStart)
        let endYear = calendar.component(.year, from: weekEnd)

        let startMonth = calendar.component(.month, from: weekStart)
        let endMonth = calendar.component(.month, from: weekEnd)

        let startPart = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endPart = weekEnd.formatted(.dateTime.month(.abbreviated).day())

        if startMonth == endMonth {
            let dayRange = "\(calendar.component(.day, from: weekStart)) – \(calendar.component(.day, from: weekEnd))"
            let month = weekStart.formatted(.dateTime.month(.abbreviated))
            if weekYear != currentYear || endYear != currentYear {
                return "\(month) \(dayRange), \(weekYear)"
            }
            return "\(month) \(dayRange)"
        }

        if weekYear != currentYear || endYear != currentYear {
            return "\(startPart) – \(endPart), \(weekYear)"
        }

        return "\(startPart) – \(endPart)"
    }
}
