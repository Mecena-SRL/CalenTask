import Foundation

/// Date in linguaggio naturale nella cattura (D23/D28): "domani devo montare",
/// "oggi alle 15", "venerdì alle 9:30", "tra 3 giorni", "12/09 15:00".
/// Un pre-parser italiano gestisce le parole relative che NSDataDetector
/// spesso ignora ("domani", "dopodomani", i giorni della settimana);
/// il detector di sistema resta come fallback per i formati espliciti.
enum NaturalDateParser {
    struct Match {
        let date: Date
        let hasTime: Bool
        let cleanedText: String
    }

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Match? {
        if let italian = parseItalian(text, now: now, calendar: calendar) {
            return italian
        }
        return parseWithDetector(text, calendar: calendar)
    }

    // MARK: - Pre-parser italiano (D28)

    private struct DayHit {
        let dayOffsetResolver: (Date, Calendar) -> Date   // base day (startOfDay)
        let impliedHour: Int?                             // "stasera" ⇒ 21
        let range: Range<String.Index>
    }

    /// (pattern, resolver, implied hour). Order matters: longest first.
    private static let dayPatterns: [(String, (Date, Calendar) -> Date, Int?)] = [
        (#"dopodomani"#, { now, cal in cal.date(byAdding: .day, value: 2, to: now.startOfDay)! }, nil),
        (#"domani\s+(mattina|sera)"#, { now, cal in cal.date(byAdding: .day, value: 1, to: now.startOfDay)! }, nil),
        (#"domani"#, { now, cal in cal.date(byAdding: .day, value: 1, to: now.startOfDay)! }, nil),
        (#"stasera"#, { now, _ in now.startOfDay }, 21),
        (#"stamattina"#, { now, _ in now.startOfDay }, 9),
        (#"oggi"#, { now, _ in now.startOfDay }, nil),
        (#"tra\s+(\d{1,2})\s+giorn[oi]"#, { now, cal in now.startOfDay }, nil),  // offset patched below
        (#"tra\s+una\s+settimana"#, { now, cal in cal.date(byAdding: .day, value: 7, to: now.startOfDay)! }, nil),
        (#"luned[ìi]"#, { now, cal in next(weekday: 2, after: now, cal) }, nil),
        (#"marted[ìi]"#, { now, cal in next(weekday: 3, after: now, cal) }, nil),
        (#"mercoled[ìi]"#, { now, cal in next(weekday: 4, after: now, cal) }, nil),
        (#"gioved[ìi]"#, { now, cal in next(weekday: 5, after: now, cal) }, nil),
        (#"venerd[ìi]"#, { now, cal in next(weekday: 6, after: now, cal) }, nil),
        (#"sabato"#, { now, cal in next(weekday: 7, after: now, cal) }, nil),
        (#"domenica"#, { now, cal in next(weekday: 1, after: now, cal) }, nil),
    ]

    /// "alle 15", "alle 9:30", "alle ore 14.45", "ore 18"
    private static let timePattern =
        #"(?:alle\s+ore|alle|ore)\s*(\d{1,2})(?:[:.](\d{2}))?"#

    private static func parseItalian(
        _ text: String, now: Date, calendar: Calendar
    ) -> Match? {
        var baseDay: Date?
        var impliedHour: Int?
        var dayRange: Range<String.Index>?

        for (pattern, resolver, hour) in dayPatterns {
            guard let match = firstMatch(of: #"(?i)\b"# + pattern + #"\b"#, in: text) else { continue }
            var day = resolver(now, calendar)
            // "tra N giorni": read the captured count.
            if pattern.hasPrefix(#"tra\s+(\d"#),
               let countRange = match.captures.first ?? nil,
               let count = Int(text[countRange]) {
                day = calendar.date(byAdding: .day, value: count, to: now.startOfDay) ?? day
            }
            baseDay = day
            impliedHour = hour
            dayRange = match.range
            break
        }

        let timeMatch = firstMatch(of: #"(?i)\b"# + timePattern + #"\b"#, in: text)
        var explicitHour: Int?
        var explicitMinute = 0
        if let timeMatch,
           let hourRange = timeMatch.captures.first ?? nil,
           let hour = Int(text[hourRange]), (0...23).contains(hour) {
            explicitHour = hour
            if timeMatch.captures.count > 1, let minuteRange = timeMatch.captures[1],
               let minute = Int(text[minuteRange]), (0...59).contains(minute) {
                explicitMinute = minute
            }
        }

        // Nothing Italian found → let the detector try.
        guard baseDay != nil || explicitHour != nil else { return nil }

        let day = baseDay ?? now.startOfDay   // "alle 15" alone ⇒ today
        let hour = explicitHour ?? impliedHour
        let hasTime = hour != nil
        let date: Date
        if let hour {
            date = calendar.date(
                bySettingHour: hour, minute: explicitHour != nil ? explicitMinute : 0,
                second: 0, of: day
            ) ?? day
        } else {
            date = day
        }

        var ranges: [Range<String.Index>] = []
        if let dayRange { ranges.append(dayRange) }
        if explicitHour != nil, let timeMatch { ranges.append(timeMatch.range) }
        return Match(date: date, hasTime: hasTime, cleanedText: cleaned(text, removing: ranges))
    }

    private static func next(weekday: Int, after now: Date, _ calendar: Calendar) -> Date {
        // "venerdì" detto di venerdì ⇒ oggi; altrimenti la prossima occorrenza.
        if calendar.component(.weekday, from: now) == weekday { return now.startOfDay }
        let date = calendar.nextDate(
            after: now, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime
        ) ?? now
        return date.startOfDay
    }

    // MARK: - Fallback: NSDataDetector

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    private static func parseWithDetector(_ text: String, calendar: Calendar) -> Match? {
        guard let detector,
              let result = detector.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)
              ),
              let date = result.date,
              let range = Range(result.range, in: text)
        else { return nil }

        let matched = String(text[range]).lowercased()
        return Match(
            date: date,
            hasTime: hasExplicitTime(in: matched, parsed: date, calendar: calendar),
            cleanedText: cleaned(text, removing: [range])
        )
    }

    /// NSDataDetector defaults to 12:00 when no time is written; an explicit
    /// time shows up either in the matched text or as a non-noon component.
    private static func hasExplicitTime(
        in matched: String, parsed: Date, calendar: Calendar
    ) -> Bool {
        if matched.contains("alle") || matched.contains("ore ") { return true }
        if matched.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil {
            return true
        }
        let components = calendar.dateComponents([.hour, .minute], from: parsed)
        return !(components.hour == 12 && components.minute == 0)
    }

    // MARK: - Cleaning

    /// Removes the matched ranges plus dangling connectors ("il", "alle", …).
    private static func cleaned(_ text: String, removing ranges: [Range<String.Index>]) -> String {
        var result = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        result = result.replacingOccurrences(
            of: #"\s+(il|per|entro( il)?|alle( ore)?|a|ore)\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"^\s*(il|alle( ore)?|a|ore|,|-)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s{2,}"#, with: " ", options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regex plumbing

    private struct RegexHit {
        let range: Range<String.Index>
        let captures: [Range<String.Index>?]
    }

    private static func firstMatch(of pattern: String, in text: String) -> RegexHit? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)
              ),
              let full = Range(match.range, in: text)
        else { return nil }
        let captures = (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text) }
        return RegexHit(range: full, captures: captures)
    }

    // MARK: - Shared capture behavior

    /// Timed phrases become calendar events, date-only phrases become
    /// deadlines (D23). The date words STAY in the title (D38) — we only
    /// read them, we don't rewrite what the user typed.
    @MainActor
    static func apply(to task: TodoTask, from text: String) -> Bool {
        guard let match = parse(text) else { return false }
        if match.hasTime {
            task.kind = .event
            task.startAt = match.date
            task.endAt = match.date.addingTimeInterval(3600)
        } else {
            task.dueAt = match.date
        }
        return true
    }
}
