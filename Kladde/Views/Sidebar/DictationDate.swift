//
//  DictationDate.swift
//  Kladde
//
//  How the sidebar talks about time. Both ladders — the group a dictation
//  sorts under and the date printed on its row — are the ones Notes, Mail and
//  Voice Memos use, and they live together because they have to stay in step:
//  the row inside a "Yesterday" group must not repeat the word.
//

import Foundation

enum DictationDate {
    /// The date-bucket header a dictation sorts under: Today, Yesterday, the
    /// previous 7 and 30 days, then months of the current year, then bare years.
    static func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
           date >= sevenDaysAgo {
            return "Previous 7 Days"
        }
        if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
           date >= thirtyDaysAgo {
            return "Previous 30 Days"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.year())
    }

    /// The compact date on a row: the time today, "Yesterday", the weekday
    /// within the last week, and a short date beyond that.
    static func rowLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)),
           date >= weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
