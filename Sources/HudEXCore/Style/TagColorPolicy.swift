import Foundation

/// The colour family a tag uses. The background colour *is* the status, so no
/// separate indicator is drawn.
public enum TagColorRole: String, Sendable, CaseIterable, Hashable {
    /// Recently updated and active.
    case active
    /// Starting to get old.
    case attention
    /// Getting old.
    case aging
    /// Long untouched.
    case stale
    /// Explicitly paused in the Markdown file.
    case paused
    /// Archived or finished in the Markdown file.
    case archived

    public var displayName: String { L10n.t(displayNameKey) }

    public var displayNameKey: String {
        switch self {
        case .active: return "role.active"
        case .attention: return "role.attention"
        case .aging: return "role.aging"
        case .stale: return "role.stale"
        case .paused: return "role.paused"
        case .archived: return "role.archived"
        }
    }
}

/// Age thresholds, in days, for the automatic colour.
///
/// Concentrated here so views never hard-code a threshold.
public struct TagColorThresholds: Sendable, Equatable {
    /// ≤ this many days: active.
    public var activeThroughDays: Int
    /// ≤ this many days: attention.
    public var attentionThroughDays: Int
    /// ≤ this many days: aging. Older: stale.
    public var agingThroughDays: Int

    public init(activeThroughDays: Int = 2, attentionThroughDays: Int = 6, agingThroughDays: Int = 13) {
        self.activeThroughDays = max(0, activeThroughDays)
        self.attentionThroughDays = max(self.activeThroughDays, attentionThroughDays)
        self.agingThroughDays = max(self.attentionThroughDays, agingThroughDays)
    }

    public static let `default` = TagColorThresholds()
}

/// Decides a tag's colour role from status + age.
public enum TagColorPolicy {
    public static func role(
        status: ProjectStatus,
        updatedAt: Date?,
        now: Date = Date(),
        thresholds: TagColorThresholds = .default,
        calendar: Calendar = .current
    ) -> TagColorRole {
        switch status {
        case .paused: return .paused
        case .archived, .done: return .archived
        case .active, .unknown: break
        }

        guard let updatedAt else { return .stale }
        let days = wholeDays(from: updatedAt, to: now, calendar: calendar)
        if days <= thresholds.activeThroughDays { return .active }
        if days <= thresholds.attentionThroughDays { return .attention }
        if days <= thresholds.agingThroughDays { return .aging }
        return .stale
    }

    /// Elapsed whole days ignoring the time of day, so "yesterday evening"
    /// counts as one day even if fewer than 24 hours have passed.
    public static func wholeDays(from date: Date, to now: Date, calendar: Calendar = .current) -> Int {
        if date >= now { return 0 }
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }
}

/// Human-readable age text ("2 小时前"), used only inside the hover preview.
public enum RelativeAgeFormatter {
    public static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return L10n.t("time.justNow") }
        if seconds < 3600 {
            return L10n.t("time.minutes", Int(seconds / 60))
        }
        if seconds < 86_400 {
            return L10n.t("time.hours", Int(seconds / 3600))
        }
        let days = TagColorPolicy.wholeDays(from: date, to: now, calendar: calendar)
        if days < 30 { return L10n.t("time.days", max(1, days)) }
        if days < 365 { return L10n.t("time.months", days / 30) }
        return L10n.t("time.years", days / 365)
    }
}

/// Absolute timestamp formatting, shared by the preview and detail windows.
public enum TimestampFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
