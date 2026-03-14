import Foundation
import Observation

@Observable
@MainActor
final class UsageDataManager {
    private(set) var fiveHourUtil: Double = 0
    private(set) var sevenDayUtil: Double = 0
    private(set) var fiveHourReset: Double = 0
    private(set) var sevenDayReset: Double = 0
    private(set) var lastUpdateTimestamp: Double = 0
    private(set) var historyPoints: [UsageDataPoint] = []
    private(set) var totalCost: Double = 0
    private(set) var subscriptionDaysLeft: Int? = nil

    private var pollTimer: Timer?
    private var saveTimer: Timer?

    private var claudeDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
    }

    private var cacheFilePath: String {
        claudeDir + "/ratelimit_cache.json"
    }

    private var totalCostFilePath: String {
        claudeDir + "/total_cost.json"
    }

    private var subscriptionFilePath: String {
        claudeDir + "/subscription.json"
    }

    private var historyFilePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/klaudetool_history.json"
    }

    private var legacyHistoryFilePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/claufication_history.json"
    }

    // MARK: - Computed Properties

    var fiveHourPercent: Int {
        Int((fiveHourUtil * 100).rounded())
    }

    var sevenDayPercent: Int {
        Int((sevenDayUtil * 100).rounded())
    }

    var fiveHourResetText: String {
        formatReset(fiveHourReset)
    }

    var sevenDayResetText: String {
        formatReset(sevenDayReset)
    }

    var lastUpdateText: String {
        guard lastUpdateTimestamp > 0 else { return "Never" }
        let elapsed = Date().timeIntervalSince1970 - lastUpdateTimestamp
        if elapsed < 5 { return "Just now" }
        return formatDuration(elapsed) + " ago"
    }

    var totalCostText: String {
        String(format: "$%.2f", totalCost)
    }

    var subscriptionDaysText: String? {
        guard let days = subscriptionDaysLeft else { return nil }
        return "\(days)d"
    }

    // MARK: - Lifecycle

    func start() {
        loadHistory()
        refresh()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        readCache()
        readTotalCost()
        readSubscription()
        appendHistoryPoint()
        pruneOldHistory()
        saveHistory()
    }

    // MARK: - Cache Reading

    private func readCache() {
        guard let data = FileManager.default.contents(atPath: cacheFilePath) else { return }
        guard let cache = try? JSONDecoder().decode(RateLimitCache.self, from: data) else { return }

        fiveHourUtil = cache.fiveHourUtil
        sevenDayUtil = cache.sevenDayUtil
        fiveHourReset = cache.fiveHourReset
        sevenDayReset = cache.sevenDayReset
        lastUpdateTimestamp = cache.timestamp
    }

    // MARK: - Total Cost

    private func readTotalCost() {
        guard let data = FileManager.default.contents(atPath: totalCostFilePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let totalPrevious = json["total_previous"] as? Double ?? 0
        let currentSessionCost = json["current_session_cost"] as? Double ?? 0
        totalCost = totalPrevious + currentSessionCost
    }

    // MARK: - Subscription

    private func readSubscription() {
        guard let data = FileManager.default.contents(atPath: subscriptionFilePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let renewalDay = json["renewal_day"] as? Int, renewalDay > 0 else {
            subscriptionDaysLeft = nil
            return
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let comps = calendar.dateComponents([.year, .month], from: todayStart)
        guard let year = comps.year, let month = comps.month else { return }

        // Try this month's renewal date
        var nextComps = DateComponents(year: year, month: month, day: renewalDay)
        var nextDate = calendar.date(from: nextComps)
        // Clamp to last day of month if needed
        if nextDate == nil {
            let range = calendar.range(of: .day, in: .month, for: todayStart)!
            nextComps.day = min(renewalDay, range.upperBound - 1)
            nextDate = calendar.date(from: nextComps)
        }

        if let next = nextDate, next > todayStart {
            subscriptionDaysLeft = calendar.dateComponents([.day], from: todayStart, to: next).day
        } else {
            // Next month
            var futureComps = DateComponents(year: year, month: month + 1, day: renewalDay)
            if month + 1 > 12 {
                futureComps.year = year + 1
                futureComps.month = 1
            }
            var futureDate = calendar.date(from: futureComps)
            if futureDate == nil {
                let futureMonth = futureComps.month!
                let futureYear = futureComps.year!
                let tempDate = calendar.date(from: DateComponents(year: futureYear, month: futureMonth))!
                let range = calendar.range(of: .day, in: .month, for: tempDate)!
                futureComps.day = min(renewalDay, range.upperBound - 1)
                futureDate = calendar.date(from: futureComps)
            }
            if let future = futureDate {
                subscriptionDaysLeft = calendar.dateComponents([.day], from: todayStart, to: future).day
            }
        }
    }

    // MARK: - History Management

    private func appendHistoryPoint() {
        guard lastUpdateTimestamp > 0 else { return }

        // Don't add if values haven't changed
        if let last = historyPoints.last,
           last.fiveHourUtil == fiveHourUtil,
           last.sevenDayUtil == sevenDayUtil {
            return
        }

        let point = UsageDataPoint(
            timestamp: Date().timeIntervalSince1970,
            fiveHourUtil: fiveHourUtil,
            sevenDayUtil: sevenDayUtil
        )
        historyPoints.append(point)
    }

    private func pruneOldHistory() {
        let cutoff = Date().timeIntervalSince1970 - TimeRange.thirtyDays.seconds
        historyPoints.removeAll { $0.timestamp < cutoff }
    }

    private func loadHistory() {
        let fm = FileManager.default
        // Migrate from legacy claufication_history.json if needed
        if !fm.fileExists(atPath: historyFilePath), fm.fileExists(atPath: legacyHistoryFilePath) {
            try? fm.moveItem(atPath: legacyHistoryFilePath, toPath: historyFilePath)
        }
        guard let data = fm.contents(atPath: historyFilePath) else { return }
        guard let points = try? JSONDecoder().decode([UsageDataPoint].self, from: data) else { return }
        historyPoints = points
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(historyPoints) else { return }
        FileManager.default.createFile(atPath: historyFilePath, contents: data)
    }

    // MARK: - Formatting

    private func formatReset(_ resetTimestamp: Double) -> String {
        let remaining = resetTimestamp - Date().timeIntervalSince1970
        if remaining <= 0 { return "Now" }
        return formatDuration(remaining)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days) day\(days == 1 ? "" : "s")") }
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if parts.isEmpty { parts.append("\(secs) sec") }

        return parts.prefix(2).joined(separator: ", ")
    }
}
