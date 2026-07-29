import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ComparisonLogicTests {
static func main() {
let records = [
        ComparisonSample(date: "07.28", secondOfDay: 72_000, quantity: "2瓶"),
        ComparisonSample(date: "07.28", secondOfDay: 72_010, quantity: "2瓶"),
        ComparisonSample(date: "07.28", secondOfDay: 72_040, quantity: "2瓶"),
        ComparisonSample(date: "07.29", secondOfDay: 72_000, quantity: "2瓶"),
        ComparisonSample(date: "07.29", secondOfDay: 72_005, quantity: "2瓶"),
        ComparisonSample(date: "07.29", secondOfDay: 72_010, quantity: "2瓶"),
        ComparisonSample(date: "07.29", secondOfDay: 72_020, quantity: "2瓶"),
    ]

let index = YesterdayComparisonIndex(
    samples: records,
    orderedDates: ["07.28", "07.29"],
    binSeconds: 30
)

let interval = index.result(
    date: "07.29", quantity: "2瓶", bucketStart: 72_000, mode: .interval
)
expect(interval?.today == 4, "时段同比今日应为4")
expect(interval?.yesterday == 2, "时段同比昨日应为2")
expect(interval?.percentChange == 100, "时段同比应增长100%")

let cumulative = index.result(
    date: "07.29", quantity: "2瓶", bucketStart: 72_030, mode: .cumulative
)
expect(cumulative?.today == 4, "累计同比今日应为4")
expect(cumulative?.yesterday == 3, "累计同比昨日应为3")

let noPrevious = index.result(
    date: "07.28", quantity: "2瓶", bucketStart: 72_000, mode: .interval
)
expect(noPrevious == nil, "首个日期应没有昨日数据")

let zeroBase = YesterdayComparisonResult(today: 3, yesterday: 0)
expect(zeroBase.summary == "昨日同期为0，今日新增3单", "昨日为0的文案")
expect(YesterdayComparisonResult(today: 0, yesterday: 0).summary == "较昨日持平（0单）", "持平文案")
expect(YesterdayComparisonResult(today: 8, yesterday: 10).summary.contains("-20.0%"), "下降百分比文案")

print("PASS: ComparisonLogicTests")
}
}
