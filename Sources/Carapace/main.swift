import Foundation
import AppKit
import Darwin
import CarapaceCore

let args = CommandLine.arguments

if args.contains("--selftest") {
    exit(runSelfTest())
}

if let index = args.firstIndex(of: "--search"), index + 1 < args.count {
    let keyword = args[index + 1]
    let results = (try? await QuoteService.shared.searchSymbols(keyword)) ?? []
    for r in results {
        print("\(r.code)\t\(r.name)\t\(r.market)\t\(r.instrumentMarket.rawValue)\t\(r.quoteKey ?? "-")")
    }
    exit(0)
}

if args.contains("--once") {
    let store = try Store()
    let tracked = try store.trackedPositions()
    let quotes = try await QuoteService.shared.fetch(positions: tracked)
    for p in tracked where p.kind == .holding {
        guard let q = quotes[p.quoteCode] else {
            print("\(p.name) \(p.code)  行情不可用 · 不估值")
            continue
        }
        let pnl = (q.valuationPrice - p.avgCost) * p.quantity
        let today = p.source == .fund && !MarketHours.isToday(q.time)
            ? 0 : (q.valuationPrice - q.prevValuationPrice) * p.quantity
        let sell = q.sellPrice.map { "  卖出 \(Fmt.price($0))" } ?? ""
        print("\(p.name) \(p.code)  \(Fmt.qty(p.quantity, unit: p.unit))  成本 \(Fmt.price(p.avgCost))  现价 \(Fmt.price(q.price))\(sell) [\(q.source.displayName)]  盈亏 \(Fmt.signed(pnl))  今日 \(Fmt.signed(today))")
    }
    let watches = tracked.filter(\.isWatch)
    if !watches.isEmpty {
        print("观察")
        for p in watches {
            let px = quotes[p.quoteCode].map { Fmt.price($0.price) } ?? "行情不可用"
            print("\(p.name) \(p.code)  关注价 \(p.watchPrice.map { Fmt.price($0) } ?? "—")  现价 \(px)")
        }
    }
    exit(0)
}

// 测试/冒烟脚本可以用 CARAPACE_LOCK 指定独立锁，避免和正在运行的真实 App 抢单实例锁。
let lockPath = ProcessInfo.processInfo.environment["CARAPACE_LOCK"]
    ?? (NSTemporaryDirectory() + "com.ryan.carapace.lock")
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
