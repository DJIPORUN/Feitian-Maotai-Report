import SwiftUI
import Charts
import AppKit

private let sourceURL = URL(string:
    "https://vika.cn/nest/v1/shares/shrwqEwPuTFYc2u3VufJ5/datasheets/dstaKeQyPWNZCycDN1/dataPack"
)!
private let targetProduct = "飞天53%vol 500ml贵州茅台酒（带杯）"
private let targetQuantities = ["2瓶", "4瓶", "6瓶"]
private let leakageStartMinute = 20 * 60 + 45

struct PurchaseRecord: Identifiable, Hashable, Sendable {
    let id: String
    let date: String
    let secondOfDay: Int
    let quantity: String
    let deviceModel: String
    let brand: String
    let ipAddress: String
    let ipLocation: String
    var minuteOfDay: Int { secondOfDay / 60 }
}

struct TimeBin: Identifiable {
    let startSecond: Int
    let count: Int
    var id: Int { startSecond }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case bars = "柱状图"
    case donuts = "圆形图"
    case summary = "文字总结"
    case leakage = "捡漏分析"
    case deviceIP = "设备/IP"
    var id: String { rawValue }
}

struct DonutSlice: Identifiable {
    let label: String
    let value: Int
    var id: String { label }
}

struct PurchaseWindow {
    let startMinute: Int
    let endMinute: Int
    let covered: Int
    let total: Int
}

struct CategoryCount: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct CrossDayBin: Identifiable {
    let id: Int
    let x: Double
    let date: String
    let startSecond: Int
    let twoCount: Int
    let fourCount: Int
    let sixCount: Int
    let isDayStart: Bool
    var total: Int { twoCount + fourCount + sixCount }
}

struct CrossDayLinePoint: Identifiable {
    let id: String
    let x: Double
    let quantity: String
    let count: Int
}

struct DailyTotalRow: Identifiable {
    let date: String
    let twoCount: Int
    let fourCount: Int
    let sixCount: Int
    var id: String { date }
    var total: Int { twoCount + fourCount + sixCount }
    var bottles: Int { twoCount * 2 + fourCount * 4 + sixCount * 6 }
}

@MainActor
final class SyncStatus: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSync: Date?
    @Published var nextSyncAt: Date?
    @Published var lastAddedCount = 0
    @Published var errorMessage: String?
}

@MainActor
final class ReportStore: ObservableObject {
    @Published var records: [PurchaseRecord] = []
    @Published var dates: [String] = []
    @Published var selectedDate = ""
    let syncStatus = SyncStatus()
    @Published var syncSeconds: Int {
        didSet {
            if syncSeconds < 10 {
                syncSeconds = 10
                return
            }
            if syncSeconds > 86_400 {
                syncSeconds = 86_400
                return
            }
            UserDefaults.standard.set(syncSeconds, forKey: "syncSeconds")
            scheduleTimer()
        }
    }
    @Published var binSeconds: Int {
        didSet {
            if binSeconds < 30 {
                binSeconds = 30
                return
            }
            if binSeconds > 3_600 {
                binSeconds = 3_600
                return
            }
            UserDefaults.standard.set(binSeconds, forKey: "binSeconds")
        }
    }

    private var timer: Timer?

    init() {
        let savedSync = UserDefaults.standard.integer(forKey: "syncSeconds")
        let savedBinSeconds = UserDefaults.standard.integer(forKey: "binSeconds")
        let legacyBinMinutes = UserDefaults.standard.integer(forKey: "binMinutes")
        syncSeconds = savedSync > 0 ? savedSync : 30
        binSeconds = savedBinSeconds > 0
            ? savedBinSeconds
            : (legacyBinMinutes > 0 ? legacyBinMinutes * 60 : 300)
    }

    func start() {
        scheduleTimer()
        sync()
    }

    func scheduleTimer() {
        timer?.invalidate()
        syncStatus.nextSyncAt = Date().addingTimeInterval(TimeInterval(syncSeconds))
        let newTimer = Timer(timeInterval: TimeInterval(syncSeconds), repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func sync() {
        guard !syncStatus.isSyncing else { return }
        syncStatus.isSyncing = true
        syncStatus.errorMessage = nil

        Task {
            do {
                var request = URLRequest(url: sourceURL)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = 45
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Safari/537.36",
                    forHTTPHeaderField: "User-Agent"
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(
                        domain: "FeitianReport",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "数据源返回状态码 \(http.statusCode)"]
                    )
                }
                // 7MB+ 的表格解析放到后台线程，避免定时同步时阻塞滚动和悬停。
                let parsed = try await Task.detached(priority: .utility) {
                    try Self.parse(data)
                }.value
                let oldCount = records.count
                let oldLatestDate = dates.last
                let wasFollowingLatest = selectedDate.isEmpty || selectedDate == oldLatestDate
                let dataChanged = parsed.records != records
                syncStatus.lastAddedCount =
                    oldCount == 0 || !dataChanged ? 0 : parsed.records.count - oldCount
                if dataChanged {
                    records = parsed.records
                    dates = parsed.dates
                    if wasFollowingLatest || selectedDate.isEmpty || !parsed.dates.contains(selectedDate) {
                        selectedDate = parsed.dates.last ?? "全部"
                    }
                }
                syncStatus.lastSync = Date()
                syncStatus.nextSyncAt = Date().addingTimeInterval(TimeInterval(syncSeconds))
            } catch {
                syncStatus.errorMessage = error.localizedDescription
                syncStatus.nextSyncAt = Date().addingTimeInterval(TimeInterval(syncSeconds))
            }
            syncStatus.isSyncing = false
        }
    }

    private nonisolated static func cellText(_ data: [String: Any], fieldID: String) -> String {
        guard let items = data[fieldID] as? [[String: Any]] else { return "" }
        return items.compactMap { $0["text"] as? String }.joined()
    }

    private nonisolated static func dateKey(_ value: String) -> (Int, Int) {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        return (parts.first ?? 0, parts.dropFirst().first ?? 0)
    }

    private nonisolated static func parse(_ data: Data) throws -> (records: [PurchaseRecord], dates: [String]) {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any],
            let snapshot = payload["snapshot"] as? [String: Any],
            let meta = snapshot["meta"] as? [String: Any],
            let fieldMap = meta["fieldMap"] as? [String: [String: Any]],
            let recordMap = snapshot["recordMap"] as? [String: [String: Any]]
        else {
            throw NSError(
                domain: "FeitianReport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "数据格式与预期不一致"]
            )
        }

        var fields: [String: String] = [:]
        for (fieldID, info) in fieldMap {
            if let name = info["name"] as? String { fields[name] = fieldID }
        }
        guard
            let productField = fields["商品名称"],
            let quantityField = fields["数量"],
            let timeField = fields["抢购时间"]
        else {
            throw NSError(
                domain: "FeitianReport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "表格字段不完整"]
            )
        }

        let expression = try NSRegularExpression(
            pattern: #"^(\d{2}\.\d{2})\s+(\d{2}):(\d{2}):(\d{2})$"#
        )
        var result: [PurchaseRecord] = []
        result.reserveCapacity(recordMap.count)

        for (recordID, record) in recordMap {
            guard let row = record["data"] as? [String: Any] else { continue }
            let product = cellText(row, fieldID: productField)
            let quantity = cellText(row, fieldID: quantityField)
            let time = cellText(row, fieldID: timeField)
            guard product == targetProduct, targetQuantities.contains(quantity) else { continue }

            let range = NSRange(time.startIndex..<time.endIndex, in: time)
            guard
                let match = expression.firstMatch(in: time, range: range),
                match.numberOfRanges == 5,
                let dateRange = Range(match.range(at: 1), in: time),
                let hourRange = Range(match.range(at: 2), in: time),
                let minuteRange = Range(match.range(at: 3), in: time),
                let secondRange = Range(match.range(at: 4), in: time),
                let hour = Int(time[hourRange]),
                let minute = Int(time[minuteRange]),
                let second = Int(time[secondRange])
            else { continue }

            result.append(PurchaseRecord(
                id: recordID,
                date: String(time[dateRange]),
                secondOfDay: hour * 3600 + minute * 60 + second,
                quantity: quantity,
                deviceModel: fields["型号"].map {
                    cellText(row, fieldID: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? "未知",
                brand: fields["品牌"].map {
                    cellText(row, fieldID: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? "未知",
                ipAddress: fields["IP地址"].map {
                    cellText(row, fieldID: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? "未知",
                ipLocation: fields["IP属地"].map {
                    cellText(row, fieldID: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? "未知"
            ))
        }

        // recordMap 是字典，遍历顺序并不稳定。固定排序后才能可靠识别“数据未变化”，
        // 避免每次轮询都让所有图表重新布局。
        result.sort {
            if $0.date != $1.date {
                let lhs = dateKey($0.date), rhs = dateKey($1.date)
                return lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
            if $0.secondOfDay != $1.secondOfDay {
                return $0.secondOfDay < $1.secondOfDay
            }
            return $0.id < $1.id
        }

        let dates = Array(Set(result.map(\.date))).sorted {
            let lhs = dateKey($0), rhs = dateKey($1)
            return lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        return (result, dates)
    }

    var selectedRecords: [PurchaseRecord] {
        if selectedDate == "全部" { return records }
        return records.filter { $0.date == selectedDate }
    }

    func series(for quantity: String, startingAt minimumMinute: Int? = nil) -> [TimeBin] {
        let chosen = selectedRecords.filter {
            minimumMinute == nil || $0.minuteOfDay >= minimumMinute!
        }
        guard let minSecond = chosen.map(\.secondOfDay).min(),
              let maxSecond = chosen.map(\.secondOfDay).max()
        else { return [] }

        let start = max(0, (minSecond / binSeconds) * binSeconds - binSeconds)
        let end = min(86_399, (maxSecond / binSeconds) * binSeconds + binSeconds)
        var counts: [Int: Int] = [:]
        for record in chosen where record.quantity == quantity {
            let bucket = (record.secondOfDay / binSeconds) * binSeconds
            counts[bucket, default: 0] += 1
        }
        return stride(from: start, through: end, by: binSeconds).map {
            TimeBin(startSecond: $0, count: counts[$0, default: 0])
        }
    }

    func total(for quantity: String, startingAt minimumMinute: Int? = nil) -> Int {
        selectedRecords.lazy.filter {
            $0.quantity == quantity &&
            (minimumMinute == nil || $0.minuteOfDay >= minimumMinute!)
        }.count
    }

    func peak(for quantity: String, startingAt minimumMinute: Int? = nil) -> TimeBin? {
        series(for: quantity, startingAt: minimumMinute).max {
            $0.count == $1.count ? $0.startSecond > $1.startSecond : $0.count < $1.count
        }
    }

    func formatTime(_ minute: Int) -> String {
        let normalized = max(0, minute)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    func formatSecond(_ second: Int, includeSeconds: Bool? = nil) -> String {
        let normalized = max(0, second)
        let showSeconds = includeSeconds ?? (binSeconds < 60 || normalized % 60 != 0)
        if showSeconds {
            return String(
                format: "%02d:%02d:%02d",
                normalized / 3600,
                (normalized % 3600) / 60,
                normalized % 60
            )
        }
        return String(format: "%02d:%02d", normalized / 3600, (normalized % 3600) / 60)
    }

    func rangeLabel(_ bin: TimeBin) -> String {
        "\(formatSecond(bin.startSecond))–\(formatSecond(bin.startSecond + binSeconds))"
    }

    func records(on date: String) -> [PurchaseRecord] {
        records.filter { $0.date == date }
    }

    func previousDate(for date: String) -> String? {
        guard let index = dates.firstIndex(of: date), index > dates.startIndex else { return nil }
        return dates[dates.index(before: index)]
    }

    func combinedSeries(startingAt minimumMinute: Int? = nil) -> [TimeBin] {
        let chosen = selectedRecords.filter {
            minimumMinute == nil || $0.minuteOfDay >= minimumMinute!
        }
        guard let minSecond = chosen.map(\.secondOfDay).min(),
              let maxSecond = chosen.map(\.secondOfDay).max()
        else { return [] }
        let start = max(0, (minSecond / binSeconds) * binSeconds - binSeconds)
        let end = min(86_399, (maxSecond / binSeconds) * binSeconds + binSeconds)
        var counts: [Int: Int] = [:]
        for record in chosen {
            let bucket = (record.secondOfDay / binSeconds) * binSeconds
            counts[bucket, default: 0] += 1
        }
        return stride(from: start, through: end, by: binSeconds).map {
            TimeBin(startSecond: $0, count: counts[$0, default: 0])
        }
    }

    func combinedPeak(startingAt minimumMinute: Int? = nil) -> TimeBin? {
        combinedSeries(startingAt: minimumMinute).max {
            $0.count == $1.count ? $0.startSecond > $1.startSecond : $0.count < $1.count
        }
    }

    func purchaseWindow(for quantity: String? = nil, coverage: Double = 0.8) -> PurchaseWindow? {
        let minutes = selectedRecords
            .filter { quantity == nil || $0.quantity == quantity }
            .map(\.minuteOfDay)
            .sorted()
        guard !minutes.isEmpty else { return nil }
        let needed = max(1, Int(ceil(Double(minutes.count) * coverage)))
        var bestStart = minutes[0]
        var bestEnd = minutes[min(needed - 1, minutes.count - 1)]
        var bestSpan = bestEnd - bestStart
        if minutes.count >= needed {
            for index in 0...(minutes.count - needed) {
                let start = minutes[index]
                let end = minutes[index + needed - 1]
                if end - start < bestSpan {
                    bestStart = start
                    bestEnd = end
                    bestSpan = end - start
                }
            }
        }
        return PurchaseWindow(
            startMinute: bestStart,
            endMinute: min(1440, bestEnd + 1),
            covered: needed,
            total: minutes.count
        )
    }

    func windowLabel(_ window: PurchaseWindow) -> String {
        "\(formatTime(window.startMinute))–\(formatTime(window.endMinute))"
    }

    func categoryCounts(
        _ keyPath: KeyPath<PurchaseRecord, String>,
        limit: Int = 12
    ) -> [CategoryCount] {
        var counts: [String: Int] = [:]
        for record in selectedRecords {
            let raw = record[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, raw != "未知" else { continue }
            counts[raw, default: 0] += 1
        }
        let values: [CategoryCount] = counts.map {
            CategoryCount(name: $0.key, count: $0.value)
        }
        let sorted: [CategoryCount] = values.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }
        return Array(sorted.prefix(limit))
    }

    func dailyTotalRows() -> [DailyTotalRow] {
        dates.map { date in
            let dayRecords = records.filter { $0.date == date }
            return DailyTotalRow(
                date: date,
                twoCount: dayRecords.lazy.filter { $0.quantity == "2瓶" }.count,
                fourCount: dayRecords.lazy.filter { $0.quantity == "4瓶" }.count,
                sixCount: dayRecords.lazy.filter { $0.quantity == "6瓶" }.count
            )
        }
    }

    func summaryLines() -> [String] {
        guard !selectedRecords.isEmpty else { return ["当前选择范围暂无抢购记录。"] }
        var lines: [String] = []
        let scope = selectedDate == "全部" ? "所选全部日期" : selectedDate
        let total = selectedRecords.count

        if selectedDate != "全部", let previous = previousDate(for: selectedDate) {
            let previousRecords = records(on: previous)
            let difference = total - previousRecords.count
            let percent = previousRecords.isEmpty
                ? 0
                : abs(Double(difference) / Double(previousRecords.count) * 100)
            if difference > 0 {
                lines.append("\(scope)总量为\(total.formatted())条，比\(previous)增加\(difference.formatted())条（\(percent.formatted(.number.precision(.fractionLength(1))))%），整体量明显增多。")
            } else if difference < 0 {
                lines.append("\(scope)总量为\(total.formatted())条，比\(previous)减少\(abs(difference).formatted())条（\(percent.formatted(.number.precision(.fractionLength(1))))%），整体量有所回落。")
            } else {
                lines.append("\(scope)总量为\(total.formatted())条，与\(previous)持平。")
            }

            for quantity in targetQuantities {
                let currentCount = selectedRecords.lazy.filter { $0.quantity == quantity }.count
                let previousCount = previousRecords.lazy.filter { $0.quantity == quantity }.count
                let change = currentCount - previousCount
                let direction = change > 0 ? "增加" : change < 0 ? "减少" : "持平"
                let detail = change == 0 ? "" : "\(abs(change).formatted())条"
                lines.append("\(quantity)：\(currentCount.formatted())条，较上一日\(direction)\(detail)。")
            }
        } else {
            lines.append("\(scope)共有\(total.formatted())条2瓶、4瓶或6瓶抢购记录。")
        }

        if let peak = combinedPeak() {
            lines.append("整体抢购最高峰为\(rangeLabel(peak))，该时段共有\(peak.count.formatted())条记录。")
        }
        if let window = purchaseWindow() {
            lines.append("核心抢购窗口期为\(windowLabel(window))，这是覆盖80%记录的最短连续时间段。")
        }
        let leakageTotal = selectedRecords.lazy.filter { $0.minuteOfDay >= leakageStartMinute }.count
        if let leakagePeak = combinedPeak(startingAt: leakageStartMinute), leakageTotal > 0 {
            lines.append("20:45后的捡漏记录共\(leakageTotal.formatted())条，最佳捡漏时段为\(rangeLabel(leakagePeak))，该段有\(leakagePeak.count.formatted())单。")
        }

        let leading = targetQuantities
            .map { ($0, self.total(for: $0)) }
            .max { $0.1 < $1.1 }
        if let leading {
            let share = Double(leading.1) / Double(total) * 100
            lines.append("\(leading.0)记录最多，共\(leading.1.formatted())条，占\(share.formatted(.number.precision(.fractionLength(1))))%。")
        }
        return lines
    }
}

struct MetricCard: View {
    @EnvironmentObject var store: ReportStore
    let quantity: String
    let comparisonMode: ComparisonMode
    let comparisonIndex: YesterdayComparisonIndex

    var body: some View {
        let total = store.total(for: quantity)
        let peak = store.peak(for: quantity)
        let comparison = peak.flatMap {
            store.selectedDate == "全部" ? nil : comparisonIndex.result(
                date: store.selectedDate,
                quantity: quantity,
                bucketStart: $0.startSecond,
                mode: comparisonMode
            )
        }
        VStack(alignment: .leading, spacing: 7) {
            Text("\(quantity)抢购记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(total.formatted()) 条")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            if let peak {
                let percentage = total == 0 ? 0 : Double(peak.count) / Double(total) * 100
                Text("最高峰 \(store.rangeLabel(peak)) · \(peak.count)条 · 占当日 \(percentage, specifier: "%.1f")%")
                    .font(.caption)
            } else {
                Text("暂无记录").font(.caption).foregroundStyle(.secondary)
            }
            if let comparison {
                Text("\(comparisonMode.rawValue)：\(comparison.summary)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(
                        comparison.difference > 0
                            ? Color.green
                            : (comparison.difference < 0 ? Color.red : Color.secondary)
                    )
            } else {
                Text("\(comparisonMode.rawValue)：暂无昨日数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct StockHoverOverlay: View {
    let proxy: ChartProxy
    let plotFrame: CGRect
    let domainStart: Double
    let domainEnd: Double
    let bins: [TimeBin]
    let binSeconds: Int
    let selectedDate: String
    let quantity: String
    let comparisonMode: ComparisonMode
    let comparisonIndex: YesterdayComparisonIndex

    private struct HoverSample {
        let x: CGFloat
        let second: Double
    }

    @State private var hover: HoverSample?

    private func preciseTime(_ second: Double) -> String {
        let seconds = max(0, Int(second.rounded()))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3600,
            (seconds % 3600) / 60,
            seconds % 60
        )
    }

    private func rangeLabel(for second: Double) -> String {
        let start = (Int(second) / binSeconds) * binSeconds
        let end = start + binSeconds
        return String(
            format: "%02d:%02d:%02d–%02d:%02d:%02d",
            start / 3600, (start % 3600) / 60, start % 60,
            end / 3600, (end % 3600) / 60, end % 60
        )
    }

    private func orderCount(for second: Double) -> Int {
        let start = (Int(second) / binSeconds) * binSeconds
        guard let first = bins.first?.startSecond else { return 0 }
        let index = (start - first) / binSeconds
        guard bins.indices.contains(index), bins[index].startSecond == start else { return 0 }
        return bins[index].count
    }

    private func comparisonText(for second: Double) -> String {
        guard selectedDate != "全部",
              let result = comparisonIndex.result(
                date: selectedDate,
                quantity: quantity,
                bucketStart: Int(second),
                mode: comparisonMode
              )
        else { return "暂无昨日数据" }
        return result.summary
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let relativeX = location.x - plotFrame.minX
                        guard relativeX >= 0, relativeX <= plotFrame.width,
                              let value: Double = proxy.value(atX: relativeX)
                        else {
                            hover = nil
                            return
                        }
                        let sample = HoverSample(
                            x: location.x,
                            second: min(domainEnd, max(domainStart, value))
                        )
                        // 亚像素鼠标事件无需触发重绘；合并状态更新也可避免光标线抽动。
                        if hover == nil || abs((hover?.x ?? 0) - sample.x) >= 0.5 {
                            hover = sample
                        }
                    case .ended:
                        hover = nil
                    }
                }

            if let hover {
                Path { path in
                    path.move(to: CGPoint(x: hover.x, y: plotFrame.minY))
                    path.addLine(to: CGPoint(x: hover.x, y: plotFrame.maxY))
                }
                .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)

                Text("\(preciseTime(hover.second)) · \(rangeLabel(for: hover.second)) · \(orderCount(for: hover.second))单 · \(comparisonText(for: hover.second))")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .position(
                        x: min(plotFrame.maxX - 190, max(plotFrame.minX + 190, hover.x)),
                        y: plotFrame.minY + 12
                    )
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct SmoothHorizontalMagnify: ViewModifier {
    let baseZoom: Double
    let maximumZoom: Double
    let commit: (Double) -> Void
    @GestureState private var preview = 1.0

    func body(content: Content) -> some View {
        let scale = min(maximumZoom / baseZoom, max(1 / baseZoom, preview))
        content
            .scaleEffect(x: scale, y: 1, anchor: .center)
            .simultaneousGesture(
                MagnificationGesture(minimumScaleDelta: 0.01)
                    .updating($preview) { value, state, _ in
                        state = value
                    }
                    .onEnded { commit(Double($0)) }
            )
            .transaction { $0.animation = nil }
    }
}

struct QuantityChart: View {
    @EnvironmentObject var store: ReportStore
    let quantity: String
    let color: Color
    let comparisonMode: ComparisonMode
    let comparisonIndex: YesterdayComparisonIndex
    var startingAt: Int? = nil
    @State private var zoomLevel = 1.0

    private func setZoom(_ value: Double) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            zoomLevel = min(12, max(1, value))
        }
    }

    var body: some View {
        let series = store.series(for: quantity, startingAt: startingAt)
        let peak = store.peak(for: quantity, startingAt: startingAt)
        let domainStart = Double(series.first?.startSecond ?? 0)
        let domainEnd = Double((series.last?.startSecond ?? 0) + store.binSeconds)
        let chartWidth = max(930, 930 * zoomLevel)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(quantity)\(startingAt == nil ? "" : "捡漏") · 共 \(store.total(for: quantity, startingAt: startingAt).formatted()) 条")
                    .font(.headline)
                Spacer()
                if let peak {
                    Text("最高峰：\(store.rangeLabel(peak))，\(peak.count)条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 18)
                HStack(spacing: 5) {
                    Button {
                        setZoom(zoomLevel / 1.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("缩小")

                    Text("\(zoomLevel, specifier: "%.1f")×")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38)

                    Button {
                        setZoom(zoomLevel * 1.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("放大")

                    Button("重置") {
                        zoomLevel = 1
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            ScrollView(.horizontal) {
                Chart {
                    ForEach(series) { item in
                        RectangleMark(
                            xStart: .value("开始", Double(item.startSecond)),
                            xEnd: .value("结束", Double(item.startSecond + store.binSeconds) - 0.08),
                            yStart: .value("基线", 0),
                            yEnd: .value("记录数", item.count)
                        )
                        .foregroundStyle(item.startSecond == peak?.startSecond ? Color.orange : color)
                        .cornerRadius(2)
                        .annotation(position: .top) {
                            if item.startSecond == peak?.startSecond && zoomLevel <= 3 {
                                Text("\(item.count)")
                                    .font(.caption2.bold())
                            }
                        }
                    }

                }
                .chartXScale(domain: domainStart...domainEnd)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 10)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let second = value.as(Double.self) {
                                Text(store.formatSecond(Int(second), includeSeconds: store.binSeconds < 60))
                                    .font(.caption2)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .chartYAxisLabel("记录数")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let frame = geometry[proxy.plotAreaFrame]
                        StockHoverOverlay(
                            proxy: proxy,
                            plotFrame: frame,
                            domainStart: domainStart,
                            domainEnd: domainEnd,
                            bins: series,
                            binSeconds: store.binSeconds,
                            selectedDate: store.selectedDate,
                            quantity: quantity,
                            comparisonMode: comparisonMode,
                            comparisonIndex: comparisonIndex
                        )
                    }
                }
                .frame(width: chartWidth, height: 245)
                .padding(.top, 6)
                // 手势进行时由合成层预览，松手后才重排柱形和坐标轴。
                .modifier(SmoothHorizontalMagnify(
                    baseZoom: zoomLevel,
                    maximumZoom: 12
                ) { scale in
                    setZoom(zoomLevel * scale)
                })
            }
            .frame(height: 255)

            HStack {
                Label("鼠标悬停查看精确时间、时间段和单数", systemImage: "cursorarrow.rays")
                Spacer()
                Text("双指横向滑动 · 捏合缩放")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
        .onChange(of: store.selectedDate) {
            zoomLevel = 1
        }
        .onChange(of: store.binSeconds) {
            zoomLevel = 1
        }
    }
}

struct TimeDonutCard: View {
    @EnvironmentObject var store: ReportStore
    let quantity: String

    private var slices: [DonutSlice] {
        let ranked = store.series(for: quantity)
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        let leading = Array(ranked.prefix(5)).map {
            DonutSlice(label: store.rangeLabel($0), value: $0.count)
        }
        let other = ranked.dropFirst(5).reduce(0) { $0 + $1.count }
        return other > 0 ? leading + [DonutSlice(label: "其他时段", value: other)] : leading
    }

    var body: some View {
        let total = store.total(for: quantity)
        let peak = store.peak(for: quantity)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(quantity)时间分布")
                .font(.headline)
            ZStack {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("记录数", slice.value),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.4
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("时间段", slice.label))
                }
                .chartLegend(position: .bottom, spacing: 7)
                VStack(spacing: 2) {
                    Text("\(total.formatted())")
                        .font(.title2.bold())
                    Text("条记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .offset(y: -20)
            }
            .frame(height: 315)
            if let peak {
                Text("最大扇区：\(store.rangeLabel(peak))，\(peak.count)条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(17)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct DonutDashboard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            TimeDonutCard(quantity: "2瓶")
            TimeDonutCard(quantity: "4瓶")
            TimeDonutCard(quantity: "6瓶")
        }
    }
}

struct TextSummaryView: View {
    @EnvironmentObject var store: ReportStore
    let comparisonMode: ComparisonMode
    let comparisonIndex: YesterdayComparisonIndex
    @State private var copied = false

    private var comparisonLines: [String] {
        guard store.selectedDate != "全部" else {
            return ["\(comparisonMode.rawValue)：全部日期模式下暂无昨日数据。"]
        }
        return targetQuantities.map { quantity in
            let records = store.selectedRecords.filter { $0.quantity == quantity }
            guard let lastSecond = records.map(\.secondOfDay).max(),
                  let result = comparisonIndex.result(
                    date: store.selectedDate,
                    quantity: quantity,
                    bucketStart: lastSecond,
                    mode: comparisonMode
                  )
            else {
                return "\(quantity)\(comparisonMode.rawValue)：暂无昨日数据。"
            }
            let time = store.formatSecond(
                (lastSecond / store.binSeconds) * store.binSeconds
            )
            let prefix = comparisonMode == .interval ? "最新时段\(time)" : "截至\(time)"
            return "\(quantity)\(prefix)：\(result.summary)。"
        }
    }

    private var allSummaryLines: [String] {
        store.summaryLines() + comparisonLines
    }

    private func copySummary() {
        let scope = store.selectedDate == "全部" ? "全部日期" : store.selectedDate
        let lines = allSummaryLines.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }
        let text = ([
            "飞天53%vol 500ml 抢购分析（\(scope)）",
            ""
        ] + lines).joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { copied = false }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("自动分析结论", systemImage: "text.quote")
                        .font(.headline)
                    Spacer()
                    Text("随日期、分段设置和同步数据自动更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        copySummary()
                    } label: {
                        Label(copied ? "已复制" : "一键复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                ForEach(Array(allSummaryLines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 23, height: 23)
                            .background(Color.accentColor, in: Circle())
                        Text(line)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))

            HStack(alignment: .top, spacing: 13) {
                ForEach(targetQuantities, id: \.self) { quantity in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(quantity)核心窗口")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let window = store.purchaseWindow(for: quantity) {
                            Text(store.windowLabel(window))
                                .font(.title3.bold())
                            Text("覆盖该规格80%记录的最短连续时段")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("暂无数据")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
                }
            }
        }
    }
}

struct LeakageMetricCard: View {
    @EnvironmentObject var store: ReportStore
    let quantity: String

    var body: some View {
        let total = store.total(for: quantity, startingAt: leakageStartMinute)
        let peak = store.peak(for: quantity, startingAt: leakageStartMinute)
        VStack(alignment: .leading, spacing: 7) {
            Text("\(quantity) · 20:45后")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(total.formatted()) 单")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            if let peak {
                Text("最佳 \(store.rangeLabel(peak)) · \(peak.count)单")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("暂无捡漏记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct LeakageDashboard: View {
    @EnvironmentObject var store: ReportStore
    let comparisonMode: ComparisonMode
    let comparisonIndex: YesterdayComparisonIndex

    var body: some View {
        let total = store.selectedRecords.lazy.filter {
            $0.minuteOfDay >= leakageStartMinute
        }.count
        let peak = store.combinedPeak(startingAt: leakageStartMinute)

        VStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("20:45后捡漏观察", systemImage: "clock.arrow.2.circlepath")
                        .font(.headline)
                    Spacer()
                    Text("仅统计20:45及之后的抢购记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let peak {
                    Text("最佳捡漏窗口：\(store.rangeLabel(peak))")
                        .font(.title2.bold())
                    Text("20:45后共\(total.formatted())单，其中该时间段有\(peak.count.formatted())单。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("20:45后暂无捡漏记录")
                        .font(.title3.bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

            HStack(spacing: 13) {
                LeakageMetricCard(quantity: "2瓶")
                LeakageMetricCard(quantity: "4瓶")
                LeakageMetricCard(quantity: "6瓶")
            }

            QuantityChart(
                quantity: "2瓶",
                color: .green,
                comparisonMode: comparisonMode,
                comparisonIndex: comparisonIndex,
                startingAt: leakageStartMinute
            )
            QuantityChart(
                quantity: "4瓶",
                color: .mint,
                comparisonMode: comparisonMode,
                comparisonIndex: comparisonIndex,
                startingAt: leakageStartMinute
            )
            QuantityChart(
                quantity: "6瓶",
                color: .teal,
                comparisonMode: comparisonMode,
                comparisonIndex: comparisonIndex,
                startingAt: leakageStartMinute
            )
        }
    }
}

struct CategoryChartCard: View {
    let title: String
    let subtitle: String
    let items: [CategoryCount]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(items) { item in
                BarMark(
                    x: .value("记录数", item.count),
                    y: .value("类别", item.name)
                )
                .foregroundStyle(color.gradient)
                .cornerRadius(3)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .chartXScale(domain: 0...max(1, Int(Double(items.first?.count ?? 1) * 1.18)))
            .chartYScale(domain: items.map(\.name).reversed())
            .chartXAxisLabel("记录数")
            .frame(height: max(260, CGFloat(items.count) * 27))
        }
        .padding(17)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct DeviceIPDashboard: View {
    @EnvironmentObject var store: ReportStore

    var body: some View {
        let models = store.categoryCounts(\.deviceModel)
        let brands = store.categoryCounts(\.brand)
        let ipLocations = store.categoryCounts(\.ipLocation)
        let ipAddresses = store.categoryCounts(\.ipAddress)
        let uniqueModels = Set(store.selectedRecords.map(\.deviceModel).filter {
            !$0.isEmpty && $0 != "未知"
        }).count
        let uniqueIPs = Set(store.selectedRecords.map(\.ipAddress).filter {
            !$0.isEmpty && $0 != "未知"
        }).count

        VStack(spacing: 15) {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("设备型号")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(uniqueModels.formatted()) 种")
                        .font(.title2.bold())
                    if let top = models.first {
                        Text("最多：\(top.name) · \(top.count)条")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    Text("IP地址")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(uniqueIPs.formatted()) 个")
                        .font(.title2.bold())
                    if let top = ipAddresses.first {
                        Text("重复最多：\(top.name) · \(top.count)条")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 13),
                GridItem(.flexible(), spacing: 13)
            ], alignment: .leading, spacing: 13) {
                CategoryChartCard(
                    title: "设备型号 Top 12",
                    subtitle: "按抢购记录数",
                    items: models,
                    color: .blue
                )
                CategoryChartCard(
                    title: "IP地址 Top 12",
                    subtitle: "相同地址重复次数",
                    items: ipAddresses,
                    color: .orange
                )
                CategoryChartCard(
                    title: "手机品牌 Top 12",
                    subtitle: "按抢购记录数",
                    items: brands,
                    color: .purple
                )
                CategoryChartCard(
                    title: "IP属地 Top 12",
                    subtitle: "地区及运营商",
                    items: ipLocations,
                    color: .green
                )
            }
        }
    }
}

struct CrossDayHoverOverlay: View {
    let proxy: ChartProxy
    let plotFrame: CGRect
    let bins: [CrossDayBin]
    let binSeconds: Int

    private struct HoverSample {
        let x: CGFloat
        let bin: CrossDayBin
    }

    @State private var hover: HoverSample?

    private func nearestBin(to value: Double) -> CrossDayBin? {
        guard !bins.isEmpty else { return nil }
        var low = 0
        var high = bins.count
        while low < high {
            let mid = (low + high) / 2
            if bins[mid].x < value { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return bins[0] }
        if low == bins.count { return bins[bins.count - 1] }
        return abs(bins[low].x - value) < abs(bins[low - 1].x - value)
            ? bins[low] : bins[low - 1]
    }

    private func time(_ second: Int) -> String {
        if binSeconds < 60 || second % 60 != 0 {
            return String(
                format: "%02d:%02d:%02d",
                second / 3600,
                (second % 3600) / 60,
                second % 60
            )
        }
        return String(format: "%02d:%02d", second / 3600, (second % 3600) / 60)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let relativeX = location.x - plotFrame.minX
                        guard relativeX >= 0, relativeX <= plotFrame.width,
                              let value: Double = proxy.value(atX: relativeX),
                              let nearest = nearestBin(to: value)
                        else {
                            hover = nil
                            return
                        }
                        if hover == nil || abs((hover?.x ?? 0) - location.x) >= 0.5 {
                            hover = HoverSample(x: location.x, bin: nearest)
                        }
                    case .ended:
                        hover = nil
                    }
                }

            if let hover {
                Path { path in
                    path.move(to: CGPoint(x: hover.x, y: plotFrame.minY))
                    path.addLine(to: CGPoint(x: hover.x, y: plotFrame.maxY))
                }
                .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)

                Text("\(hover.bin.date) \(time(hover.bin.startSecond))–\(time(hover.bin.startSecond + binSeconds)) · \(hover.bin.total)单")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .position(
                        x: min(plotFrame.maxX - 92, max(plotFrame.minX + 92, hover.x)),
                        y: plotFrame.minY + 12
                    )
            }
        }
        .transaction { $0.animation = nil }
    }
}

struct SyncButton: View {
    @ObservedObject var status: SyncStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(status.isSyncing ? "同步中…" : "立即同步", systemImage: "arrow.clockwise")
        }
        .disabled(status.isSyncing)
        .keyboardShortcut("r", modifiers: .command)
    }
}

struct SyncErrorBanner: View {
    @ObservedObject var status: SyncStatus

    var body: some View {
        if let error = status.errorMessage {
            Label("同步提示：\(error)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

struct SyncFooter: View {
    @ObservedObject var status: SyncStatus
    let recordCount: Int

    var body: some View {
        HStack {
            if let last = status.lastSync {
                Text("上次同步：\(last.formatted(date: .numeric, time: .standard))")
            } else {
                Text("尚未同步")
            }
            if status.lastAddedCount != 0 {
                Text(status.lastAddedCount > 0
                     ? "新增 \(status.lastAddedCount) 条"
                     : "减少 \(abs(status.lastAddedCount)) 条")
                    .foregroundStyle(status.lastAddedCount > 0 ? .green : .orange)
            } else {
                Text("已检查，无新增")
            }
            Spacer()
            if let next = status.nextSyncAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(next.timeIntervalSince(context.date)))
                    Text("下次同步：\(seconds)秒")
                }
            }
            Text("目标记录：\(recordCount.formatted()) 条")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

struct DailyTotalsTable: View {
    let rows: [DailyTotalRow]

    private var totalRow: DailyTotalRow {
        DailyTotalRow(
            date: "全部日期",
            twoCount: rows.reduce(0) { $0 + $1.twoCount },
            fourCount: rows.reduce(0) { $0 + $1.fourCount },
            sixCount: rows.reduce(0) { $0 + $1.sixCount }
        )
    }

    private func row(_ item: DailyTotalRow, bold: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(item.date).frame(width: 110, alignment: .leading)
            Text(item.twoCount.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
            Text(item.fourCount.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
            Text(item.sixCount.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
            Text(item.total.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
            Text(item.bottles.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(bold ? .body.bold() : .body)
        .padding(.vertical, 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2 / 4 / 6瓶飞天总单数")
                .font(.headline)
            HStack(spacing: 12) {
                Text("日期").frame(width: 110, alignment: .leading)
                Text("2瓶单数").frame(maxWidth: .infinity, alignment: .trailing)
                Text("4瓶单数").frame(maxWidth: .infinity, alignment: .trailing)
                Text("6瓶单数").frame(maxWidth: .infinity, alignment: .trailing)
                Text("总单数").frame(maxWidth: .infinity, alignment: .trailing)
                Text("折合瓶数").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { item in
                row(item)
                Divider()
            }
            row(totalRow, bold: true)
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct CrossDayDashboard: View {
    @EnvironmentObject var store: ReportStore
    @State private var zoomLevel = 1.0

    private var bins: [CrossDayBin] {
        var output: [CrossDayBin] = []
        var id = 0
        var x = 0.0

        for date in store.dates {
            let records = store.records.filter { $0.date == date }
            var grouped: [Int: [String: Int]] = [:]
            for record in records {
                let bucket = (record.secondOfDay / store.binSeconds) * store.binSeconds
                grouped[bucket, default: [:]][record.quantity, default: 0] += 1
            }
            let activeMinutes = grouped.keys.sorted()
            var previousMinute: Int?
            for (index, minute) in activeMinutes.enumerated() {
                if output.isEmpty {
                    x = 0
                } else if index == 0 {
                    x += 3
                } else if let previousMinute,
                          minute - previousMinute > store.binSeconds {
                    x += 2
                } else {
                    x += 1
                }
                let counts = grouped[minute] ?? [:]
                output.append(CrossDayBin(
                    id: id,
                    x: x,
                    date: date,
                    startSecond: minute,
                    twoCount: counts["2瓶", default: 0],
                    fourCount: counts["4瓶", default: 0],
                    sixCount: counts["6瓶", default: 0],
                    isDayStart: index == 0
                ))
                id += 1
                previousMinute = minute
            }
        }
        return output
    }

    private var points: [CrossDayLinePoint] {
        bins.flatMap { bin in
            [
                CrossDayLinePoint(id: "\(bin.id)-2", x: bin.x, quantity: "2瓶", count: bin.twoCount),
                CrossDayLinePoint(id: "\(bin.id)-4", x: bin.x, quantity: "4瓶", count: bin.fourCount),
                CrossDayLinePoint(id: "\(bin.id)-6", x: bin.x, quantity: "6瓶", count: bin.sixCount)
            ]
        }
    }

    var body: some View {
        let dayStarts = bins.filter(\.isDayStart)
        let tickStep = max(1, bins.count / 14)
        let tickValues = bins.enumerated().compactMap {
            $0.offset % tickStep == 0 ? $0.element.x : nil
        }
        let domainStart = (bins.first?.x ?? 0) - 1
        let domainEnd = (bins.last?.x ?? 1) + 1
        let chartWidth = max(980, CGFloat(bins.count) * 11 * CGFloat(zoomLevel))

        VStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text("跨日连续抢购时间线")
                    .font(.headline)
                Text("每天按日期顺序横向连接；没有抢购记录的空档被压缩为一个短间隔。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button { zoomLevel = max(1, zoomLevel / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text("\(zoomLevel, specifier: "%.1f")×")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
                Button { zoomLevel = min(12, zoomLevel * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button("重置") { zoomLevel = 1 }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            ScrollView(.horizontal) {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("连续位置", point.x),
                            y: .value("单数", point.count),
                            series: .value("数量", point.quantity)
                        )
                        .foregroundStyle(by: .value("数量", point.quantity))
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    ForEach(dayStarts) { day in
                        RuleMark(x: .value("日期开始", day.x))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .annotation(position: .top, alignment: .leading) {
                                Text(day.date)
                                    .font(.caption.bold())
                            }
                    }
                }
                .chartForegroundStyleScale([
                    "2瓶": Color.blue,
                    "4瓶": Color.purple,
                    "6瓶": Color.orange
                ])
                .chartXScale(domain: domainStart...domainEnd)
                .chartXAxis {
                    AxisMarks(values: tickValues) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let x = value.as(Double.self),
                               let nearest = bins.min(by: {
                                   abs($0.x - x) < abs($1.x - x)
                               }) {
                                Text(String(
                                    format: "%02d:%02d",
                                    nearest.startSecond / 3600,
                                    (nearest.startSecond % 3600) / 60
                                ))
                                .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxisLabel("单数")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let frame = geometry[proxy.plotAreaFrame]
                        CrossDayHoverOverlay(
                            proxy: proxy,
                            plotFrame: frame,
                            bins: bins,
                            binSeconds: store.binSeconds
                        )
                    }
                }
                .frame(width: chartWidth, height: 330)
                .modifier(SmoothHorizontalMagnify(
                    baseZoom: zoomLevel,
                    maximumZoom: 12
                ) { scale in
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        zoomLevel = min(12, max(1, zoomLevel * scale))
                    }
                })
            }
            .frame(height: 340)

            HStack {
                Label("双指横向滑动查看连续日期", systemImage: "arrow.left.and.right")
                Spacer()
                Text("空白时间已压缩")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ReportStore
    @State private var displayMode: DisplayMode = .bars
    @State private var comparisonMode: ComparisonMode = .interval

    var body: some View {
        let comparisonIndex = YesterdayComparisonIndex(
            samples: store.records.map {
                ComparisonSample(
                    date: $0.date,
                    secondOfDay: $0.secondOfDay,
                    quantity: $0.quantity
                )
            },
            orderedDates: store.dates,
            binSeconds: store.binSeconds
        )
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("飞天53%vol 500ml 抢购实时报表")
                            .font(.title2.bold())
                        Text("应用打开时同步，关闭窗口后进程完全退出")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("实时监控 · \(store.syncSeconds)秒",
                          systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                    SyncButton(status: store.syncStatus) {
                        store.sync()
                    }
                }

                HStack(spacing: 18) {
                    Picker("日期", selection: $store.selectedDate) {
                        Text("全部日期").tag("全部")
                        ForEach(store.dates.reversed(), id: \.self) { date in
                            Text(date == store.dates.last ? "\(date)（最新）" : date).tag(date)
                        }
                    }
                    .frame(width: 190)

                    Stepper(value: $store.syncSeconds, in: 10...86_400, step: 10) {
                        HStack(spacing: 5) {
                            Text("同步间隔")
                            TextField("", value: $store.syncSeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 66)
                            Text("秒")
                        }
                    }

                    Stepper(value: $store.binSeconds, in: 30...3_600, step: 30) {
                        HStack(spacing: 5) {
                            Text("时间分段")
                            TextField("", value: $store.binSeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 62)
                            Text("秒")
                        }
                    }
                    Button("30秒") {
                        store.binSeconds = 30
                    }
                    .buttonStyle(.borderless)
                    .help("快速切换到30秒分段")
                    Spacer()
                }

                HStack(spacing: 12) {
                    Text("显示模式")
                        .font(.subheadline)
                    Picker("显示模式", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 480)
                    Button {
                        comparisonMode.toggle()
                    } label: {
                        Label(
                            comparisonMode.rawValue,
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline.weight(.semibold))
                    .help("点击切换时段同比和累计同比")
                    Spacer()
                    if let leakagePeak = store.combinedPeak(startingAt: leakageStartMinute) {
                        Label("捡漏 \(store.rangeLabel(leakagePeak)) · \(leakagePeak.count)单",
                              systemImage: "clock.arrow.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    if let window = store.purchaseWindow() {
                        Label("核心窗口 \(store.windowLabel(window))",
                              systemImage: "clock.badge.checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                SyncErrorBanner(status: store.syncStatus)
            }
            .padding(20)

            Divider()

            if store.records.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在同步维格表数据…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        HStack(spacing: 13) {
                            MetricCard(
                                quantity: "2瓶",
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                            MetricCard(
                                quantity: "4瓶",
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                            MetricCard(
                                quantity: "6瓶",
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                        }
                        switch displayMode {
                        case .bars:
                            QuantityChart(
                                quantity: "2瓶",
                                color: .blue,
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                            QuantityChart(
                                quantity: "4瓶",
                                color: .purple,
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                            QuantityChart(
                                quantity: "6瓶",
                                color: .indigo,
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                            CrossDayDashboard()
                            DailyTotalsTable(rows: store.dailyTotalRows())
                        case .donuts:
                            DonutDashboard()
                            DailyTotalsTable(rows: store.dailyTotalRows())
                        case .summary:
                            TextSummaryView(
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                        case .leakage:
                            LeakageDashboard(
                                comparisonMode: comparisonMode,
                                comparisonIndex: comparisonIndex
                            )
                        case .deviceIP:
                            DeviceIPDashboard()
                        }

                        SyncFooter(
                            status: store.syncStatus,
                            recordCount: store.records.count
                        )
                    }
                    .padding(18)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .onAppear { store.start() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            store.sync()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct FeitianReportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ReportStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
