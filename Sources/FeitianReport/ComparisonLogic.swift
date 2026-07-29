import Foundation

enum ComparisonMode: String, CaseIterable {
    case interval = "时段同比"
    case cumulative = "累计同比"

    mutating func toggle() {
        self = self == .interval ? .cumulative : .interval
    }
}

struct ComparisonSample {
    let date: String
    let secondOfDay: Int
    let quantity: String
}

struct YesterdayComparisonResult {
    let today: Int
    let yesterday: Int

    var difference: Int { today - yesterday }

    var percentChange: Double? {
        guard yesterday > 0 else { return nil }
        return Double(difference) / Double(yesterday) * 100
    }

    var summary: String {
        if yesterday == 0 {
            return today == 0
                ? "较昨日持平（0单）"
                : "昨日同期为0，今日新增\(today)单"
        }
        let sign = difference > 0 ? "+" : ""
        let percent = percentChange ?? 0
        if difference == 0 {
            return "较昨日持平（0单）"
        }
        return String(
            format: "较昨日 %@%.1f%%（%@%d单）",
            sign, percent, sign, difference
        )
    }
}

struct YesterdayComparisonIndex {
    private struct Key: Hashable {
        let date: String
        let quantity: String
        let bucket: Int
    }

    private let binSeconds: Int
    private let previousDate: [String: String]
    private let intervalCounts: [Key: Int]
    private let cumulativeCounts: [Key: Int]

    init(samples: [ComparisonSample], orderedDates: [String], binSeconds: Int) {
        self.binSeconds = max(1, binSeconds)

        var previous: [String: String] = [:]
        for index in orderedDates.indices where index > orderedDates.startIndex {
            previous[orderedDates[index]] = orderedDates[index - 1]
        }
        previousDate = previous

        var intervals: [Key: Int] = [:]
        var quantitiesByDate: [String: Set<String>] = [:]
        for sample in samples {
            let bucket = (sample.secondOfDay / self.binSeconds) * self.binSeconds
            intervals[
                Key(date: sample.date, quantity: sample.quantity, bucket: bucket),
                default: 0
            ] += 1
            quantitiesByDate[sample.date, default: []].insert(sample.quantity)
        }
        intervalCounts = intervals

        var cumulative: [Key: Int] = [:]
        for date in orderedDates {
            for quantity in quantitiesByDate[date, default: []] {
                var running = 0
                for bucket in stride(from: 0, through: 86_400, by: self.binSeconds) {
                    let key = Key(date: date, quantity: quantity, bucket: bucket)
                    running += intervals[key, default: 0]
                    cumulative[key] = running
                }
            }
        }
        cumulativeCounts = cumulative
    }

    func result(
        date: String,
        quantity: String,
        bucketStart: Int,
        mode: ComparisonMode
    ) -> YesterdayComparisonResult? {
        guard let yesterdayDate = previousDate[date] else { return nil }
        let bucket = (bucketStart / binSeconds) * binSeconds
        let todayKey = Key(date: date, quantity: quantity, bucket: bucket)
        let yesterdayKey = Key(date: yesterdayDate, quantity: quantity, bucket: bucket)
        let source = mode == .interval ? intervalCounts : cumulativeCounts
        return YesterdayComparisonResult(
            today: source[todayKey, default: 0],
            yesterday: source[yesterdayKey, default: 0]
        )
    }
}
