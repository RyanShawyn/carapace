import Foundation
import SQLite3
import CarapaceCore

var checks = 0
var failures: [String] = []
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    checks += 1
    do { if try !condition() { failures.append(name) } }
    catch { failures.append("\(name): \(error.localizedDescription)") }
}
func expectError(_ name: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures.append(name) } catch { }
}
func fixture() throws -> (Store, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    return (try Store(path: directory.appendingPathComponent("store.sqlite3").path), directory)
}

do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let p = try store.addPosition(code: "600000", name: "测试", quantity: 100, cost: 10)
    let buy = PlanLevel(id: "buy", price: 9, kind: .buy, quantity: 20, condition: "")
    let sell = PlanLevel(id: "sell", price: 15, kind: .sell, quantity: 30, condition: "")
    _ = try store.updatePlan(positionId: p.id, levels: [buy, sell], nextReview: "2026-12-01")
    expectError("反向关联必须拒绝") {
        _ = try store.recordTrade(positionId: p.id, side: .buy, quantity: 1, price: 15, levelId: "sell")
    }
    let trade = try store.recordTrade(positionId: p.id, side: .sell, quantity: 30, price: 16, levelId: "sell")
    check(trade.matchedLevel?.id == "sell", "使用稳定档位 ID")
    check(trade.change.planVersion == 1, "记录计划版本")
    check(try store.executedLevelPrices(positionId: p.id) == ["sell"], "执行状态按 ID")
    expectError("不能重复执行同一档") {
        _ = try store.recordTrade(positionId: p.id, side: .sell, quantity: 1, price: 16, levelId: "sell")
    }
    check(try store.changes(positionId: p.id, type: .open, limit: 1).count == 1, "历史过滤先于 limit")
    check(try store.changes(positionId: p.id, type: .plan, limit: 0).isEmpty, "非法 limit 不返回错误数据")
    expectError("复盘日期校验") {
        _ = try store.updatePlan(positionId: p.id, levels: [buy], nextReview: "bad")
    }
    expectError("计划版本冲突") {
        _ = try store.updatePlan(positionId: p.id, levels: [], ifVersion: 2)
    }
    let bought = try store.recordTrade(positionId: p.id, side: .buy, quantity: 100, price: 20, fee: 2)
    check(abs(bought.position.avgCost - ((70 * 10 + 100 * 20 + 2) / 170)) < 0.0001, "买入费用计入成本")
    check(try store.verifyAll() == 0, "投影与流水一致")

    let quoteless = PortfolioBuilder.build(positions: [bought.position], plans: [:], quotes: [:], executed: [:])
    check(quoteless.views[0].value == nil && quoteless.totalPnl == nil, "无报价不估值")
    check(quoteless.views[0].nextLevel == nil, "无报价不推荐下一档")

    let signal = AlertSignal(id: "review:1:2026-01-01", kind: .review, title: "到期",
                             detail: "测试", category: .review)
    try store.syncAlerts([signal])
    try store.acknowledgeAlert(id: signal.id)
    try store.syncAlerts([signal])
    check(try store.alerts().first?.isAcknowledged == true, "确认状态跨刷新保留")
    try store.syncAlerts([])
    check(try store.alerts().isEmpty, "恢复后移除活动提醒")
    check(try store.alerts(includeResolved: true).first?.resolvedAt != nil, "恢复状态归档")

    let changed = PlanLevel(id: "buy", price: 12, kind: .buy, quantity: 20, condition: "")
    let diff = Store.diff(old: [buy, sell], new: [changed])
    check(diff.added.isEmpty && diff.changed.count == 1 && diff.removed == [sell], "diff 使用稳定 ID")
} catch { failures.append("fixture: \(error)") }

let level = PlanLevel(id: "level", price: 10, kind: .buy, quantity: 10, condition: "")
let old = Quote(code: "A", name: "A", price: 11, prevClose: 10, time: "", source: .eastmoney)
let same = Quote(code: "A", name: "A", price: 10, prevClose: 10, time: "", source: .eastmoney)
check(AlertEngine.crossed(previous: old, current: same, level: level), "向下穿越触发")
check(!AlertEngine.crossed(previous: same, current: same, level: level), "持续触及不重复触发")


// MARK: - v5 import

do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let account = try store.defaultAccount()!
    let csv = """
    成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额,佣金,印花税,过户费,成交编号
    2026-01-02,600000,浦发银行,买入,100,10.00,1000.00,1.00,0,0,T001
    2026-01-03,600000,浦发银行,卖出,40,12.00,480.00,1.00,0.48,0,T002
    """
    let preview = try ImportService.preview(data: Data(csv.utf8), accountId: account.id, store: store)
    check(preview.summary.ready == 2, "交割单预览识别两行")
    check(preview.mapping["code"] == "证券代码", "自动映射证券代码")
    let result = try ImportService.commit(preview: preview, accountId: account.id,
                                          broker: "测试券商", fileName: "test.csv", store: store)
    check(result.imported == 2, "交割单导入两笔")
    let positions = try store.positions()
    check(positions.count == 1 && abs(positions[0].quantity - 60) < 0.0001,
          "导入后持仓为 60")
    check(try store.executions(batchId: result.batch.id).count == 2, "成交事实保留两行")
    let duplicate = try ImportService.preview(data: Data(csv.utf8), accountId: account.id, store: store)
    check(duplicate.summary.duplicate == 2, "重复导入识别为重复")
    _ = try ImportService.rollback(batchId: result.batch.id, store: store)
    let after = try store.positions(includeClosed: true).first
    check(after == nil || after?.quantity == 0, "回滚后持仓归零")
    check(try store.importBatches().first?.status == .voided, "回滚批次标记")
    let parsed = CSVParser.parse("a,b\n\"x,1\",2\n")
    check(parsed.headers == ["a", "b"] && parsed.rows.first?.first == "x,1", "CSV 引号解析")
} catch { failures.append("import: \(error)") }

// MARK: - watch

do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }

    let watch = try store.addWatch(code: "601318", name: "中国平安", source: .eastmoney,
                                   unit: .share, watchPrice: 50, note: "等季报")
    check(watch.kind == .watch && watch.quantity == 0 && watch.avgCost == 0, "观察项数量/成本为 0")
    check(try store.watches().count == 1, "观察列表可查")
    check(try store.positions().isEmpty, "持仓查询不含观察")
    check(try store.trackedPositions().count == 1, "行情列表包含观察")
    expectError("观察不能重复") {
        _ = try store.addWatch(code: "601318", name: "中国平安")
    }

    let buy = PlanLevel(price: 48, kind: .buy, quantity: nil, condition: "跌破首档")
    _ = try store.updatePlan(positionId: watch.id, levels: [buy])
    check(try store.plan(positionId: watch.id)?.levels.count == 1, "观察计划允许数量为空")
    expectError("观察计划拒绝卖出档") {
        _ = try store.updatePlan(positionId: watch.id,
                                 levels: [PlanLevel(price: 55, kind: .sell, quantity: 100, condition: "")])
    }

    let holding = try store.convertWatchToHolding(id: watch.id, quantity: 1000, cost: 49)
    check(holding.kind == .holding && abs(holding.quantity - 1000) < 0.0001, "观察转持仓")
    check(try store.watches().isEmpty, "转换后观察行删除")
    check(try store.plan(positionId: holding.id)?.levels.first?.kind == .buy, "转换继承买入档")
    check(try store.changes(positionId: holding.id).contains { $0.type == .open }, "转换写入建仓流水")
    check(try store.verifyAll() == 0, "观察转持仓后投影一致")
    expectError("已有持仓不能再观察") {
        _ = try store.addWatch(code: "601318", name: "中国平安")
    }

    let tracked = try store.addWatch(code: "600000", name: "浦发银行", watchPrice: 9)
    let bought = try store.addPosition(code: "600000", name: "浦发银行", quantity: 100, cost: 10)
    check(try store.watches().allSatisfy { $0.id != tracked.id }, "买入时消化观察项")
    check(try store.positions().contains { $0.id == bought.id }, "买入生成持仓")
    check(try store.positions().count == 2, "持仓只含真实买入")

    let old = try store.addPosition(code: "000001", name: "平安银行", quantity: 100, cost: 10,
                                    plan: [PlanLevel(id: "b", price: 9, kind: .buy, quantity: 20, condition: ""),
                                           PlanLevel(id: "s", price: 15, kind: .sell, quantity: 30, condition: "")])
    _ = try store.clearPosition(positionId: old.id, price: 12)
    let carried = try store.carryClosedToWatch(positionId: old.id, watchPrice: 12, note: "清仓保留")
    let carriedPlan = try store.plan(positionId: carried.id)
    check(carried.kind == .watch && carried.watchPrice == 12, "清仓后保留观察")
    check(carriedPlan?.levels.count == 1 && carriedPlan?.levels.first?.kind == .buy
          && carriedPlan?.levels.first?.quantity == nil, "只带走未执行买入档")
    check(try store.position(id: old.id)?.status == .closed, "原清仓行保留")

    try store.syncAlerts([AlertSignal(id: "watch:test", kind: .watch,
                                      title: "观察提醒", detail: "测试", category: .watch)])
    check(try store.alerts().first?.kind == .watch, "观察提醒可落库")

    let hk = try store.addWatch(code: "00700", name: "腾讯控股",
                                market: .hk, quoteKey: "116.00700")
    check(hk.market == .hk && hk.quoteCode == "116.00700" && hk.currency == "HKD",
          "港股观察与行情键")
    let hkHolding = try store.convertWatchToHolding(id: hk.id, quantity: 100, cost: 400)
    check(hkHolding.market == .hk && hkHolding.quoteCode == "116.00700"
          && hkHolding.currency == "HKD", "港股观察转持仓")
    check(try store.verifyAll() == 0, "港股建仓后投影一致")

    let index = try store.addWatch(code: "000001", name: "上证指数",
                                   market: .index, quoteKey: "1.000001")
    check(index.market == .index && index.quoteCode == "1.000001", "指数观察")
    let us = try store.addWatch(code: "AAPL", name: "苹果",
                                market: .us, quoteKey: "105.AAPL")
    expectError("美股不能转持仓") {
        _ = try store.convertWatchToHolding(id: us.id, quantity: 10, cost: 300)
    }
    check(try store.watches().count == 3, "指数与美股在观察列表")
} catch { failures.append("watch: \(error)") }

// MARK: - symbol search

do {
    let sample = """
    var suggestvalue="中国平安,11,601318,sh601318,中国平安,,中国平安,99,1;\
    上证指数,11,000001,sh000001,上证指数,,上证指数,99,1;\
    平安银行,11,000001,sz000001,平安银行,,平安银行,99,1;\
    沪深300ETF华泰柏瑞,203,510300,sh510300,沪深300ETF华泰柏瑞,,沪深300ETF华泰柏瑞,99,1;\
    西部利得量化成长混合A,201,000006,of000006,西部利得量化成长混合A,,西部利得量化成长混合A,99,1;\
    腾讯控股,31,00700,00700,腾讯控股,,腾讯控股,99,1;\
    苹果,41,aapl,aapl,苹果,,苹果,99,1;";
    """
    let results = try QuoteService.parseSymbolSearch(Data(sample.utf8))
    check(results.contains { $0.code == "601318" && $0.name == "中国平安" }, "搜索到中国平安")
    check(results.contains {
        $0.name == "上证指数" && $0.instrumentMarket == .index && $0.quoteKey == "1.000001"
    }, "搜索识别上证指数")
    check(results.contains { $0.code == "000001" && $0.name == "平安银行" }, "区分沪指与深股")
    check(results.contains {
        $0.code == "510300" && $0.source == .eastmoney && $0.unit == .share
    }, "搜索识别场内 ETF")
    check(results.contains {
        $0.code == "000006" && $0.source == .fund && $0.unit == .fund
    }, "搜索识别场外基金")
    check(results.contains {
        $0.code == "00700" && $0.instrumentMarket == .hk && $0.quoteKey == "116.00700"
    }, "搜索识别港股")
    check(results.contains {
        $0.code.lowercased() == "aapl" && $0.instrumentMarket == .us && !$0.canHold
    }, "搜索识别美股且不可建仓")
} catch { failures.append("search: \(error)") }

// MARK: - HK valuation

    let hk = Position(id: 99, code: "00700", name: "腾讯控股", source: .eastmoney,
                      unit: .share, quantity: 100, avgCost: 400, status: .open,
                      openedAt: "2026-11-01", kind: .holding, market: .hk,
                      quoteKey: "116.00700")
    let quote = Quote(code: "00700", name: "腾讯控股", price: 420, prevClose: 410,
                      time: "2026-11-06 14:00:00", source: .eastmoney)
    let portfolio = PortfolioBuilder.build(positions: [hk], plans: [:],
                                           quotes: ["116.00700": quote], executed: [:],
                                           hkdRate: 0.85)
    check(abs((portfolio.views[0].value ?? 0) - 42_000) < 0.01, "港股原币市值")
    check(abs(portfolio.totalValue - 35_700) < 0.01, "港股按汇率折算市值")
    check(abs((portfolio.todayPnl ?? 0) - 850) < 0.01, "港股今日盈亏折算")
    check(abs((portfolio.totalPnl ?? 0) - 1_700) < 0.01, "港股未实现盈亏折算")
    check(abs((portfolio.views[0].weight ?? 0) - 1) < 0.0001, "港股仓位按折算市值")

// MARK: - v8 migration and agent writes

do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }

    check(try store.schemaVersion() == 8, "schema v8")
    for table in ["ai_providers", "ai_models", "task_routes", "threads", "messages"] {
        check(try !store.tableExists(table), "v8 不创建 AI 表：\(table)")
    }
    check(try store.tableExists("cli_requests"), "v8 创建幂等表")

    let first = try store.writeIdempotentJSON(requestId: "r1", command: "test") { "{\"n\":1}" }
    let second = try store.writeIdempotentJSON(requestId: "r1", command: "test") { "{\"n\":2}" }
    check(first == second && first == "{\"n\":1}", "request_id 返回首次结果")

    let p = try store.addPosition(code: "600000", name: "测试", quantity: 100, cost: 10)
    let payload = """
    {"levels":[{"kind":"buy","price":9,"quantity":100,"condition":"回落"}],"description":"草稿","nextReview":"2026-12-01"}
    """
    let draft = try store.addDraft(kind: "plan", positionId: p.id, skill: "test",
                                   payload: payload, baseVersion: nil,
                                   baseQuantity: nil, profileId: nil, note: nil)
    let result = try DraftService.applyPlanDraft(draft, store: store)
    check(result.plan.levels.count == 1 && result.plan.levels[0].price == 9, "草稿应用为计划")
    check(try store.drafts(status: nil, limit: 10).first?.status == "applied", "草稿标记已应用")
} catch { failures.append("v8: \(error)") }

// MARK: - update version

do {
    check(UpdateVersion.compare("0.8.0", "0.7.1") > 0, "版本比较：主版本升级")
    check(UpdateVersion.compare("v0.8.0", "0.8") == 0, "版本比较：忽略 v 前缀和缺省段")
    check(UpdateVersion.compare("0.8.0-beta.1", "0.8.0") == 0, "版本比较：忽略预发布后缀")
    check(UpdateVersion.compare("0.7.10", "0.7.9") > 0, "版本比较：数字而非字典序")
    check(!UpdateVersion.isNewer("0.7.1", than: "0.7.1"), "同版本不算更新")
}

// MARK: - 0.8.3 fixes

do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let account = try store.defaultAccount()!

    // 手工建仓 + 导入同代码：合并到同一持仓周期
    _ = try store.addPosition(code: "600001", name: "测试一", quantity: 100, cost: 10)
    let csv = """
    成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额,佣金,印花税,过户费,成交编号
    2026-11-06,600001,测试一,买入,100,11.00,1100.00,0,0,0,I001
    """
    let preview = try ImportService.preview(data: Data(csv.utf8), accountId: account.id, store: store)
    let result = try ImportService.commit(preview: preview, accountId: account.id,
                                          broker: "测试", fileName: "merge.csv", store: store)
    check(result.imported == 1, "导入手工持仓成功")
    let merged = try store.positions()
    check(merged.count == 1 && abs(merged[0].quantity - 200) < 0.0001,
          "手工持仓与导入合并且只剩一条开放持仓")

    // 回滚后可以重新导入
    _ = try ImportService.rollback(batchId: result.batch.id, store: store)
    let again = try ImportService.preview(data: Data(csv.utf8), accountId: account.id, store: store)
    check(again.summary.ready == 1 && again.summary.duplicate == 0,
          "回滚后同一文件可重新预览")
    let recommit = try ImportService.commit(preview: again, accountId: account.id,
                                            broker: "测试", fileName: "merge.csv", store: store)
    check(recommit.imported == 1, "回滚后可重新导入")

    // 非 CNY 行直接标错误
    let usd = """
    成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额,币种
    2026-11-06,600002,测试二,买入,100,10.00,1000.00,USD
    """
    let usdPreview = try ImportService.preview(data: Data(usd.utf8), accountId: account.id, store: store)
    check(usdPreview.summary.errors == 1 && usdPreview.summary.needsReview == 0,
          "非 CNY 行标记为错误而不是待确认")

    // 金额不一致行：确认后按数量×价格导入
    let mismatch = """
    成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额
    2026-11-06,600003,测试三,买入,100,10.00,900.00
    """
    let mismatchPreview = try ImportService.preview(data: Data(mismatch.utf8), accountId: account.id, store: store)
    check(mismatchPreview.summary.needsReview == 1, "金额不一致标记待确认")
    let fixed = try ImportService.commit(preview: mismatchPreview, accountId: account.id,
                                         broker: "测试", fileName: "mismatch.csv",
                                         store: store, includeNeedsReview: true)
    check(fixed.imported == 1, "待确认行可按数量×价格修正导入")

    // 只有说明、没有档位也保留计划
    let metaOnly = try store.addPosition(code: "600004", name: "测试四",
                                         quantity: 100, cost: 10,
                                         description: "逻辑说明")
    let metaPlan = try store.plan(positionId: metaOnly.id)
    check(metaPlan?.description == "逻辑说明" && metaPlan?.levels.isEmpty == true,
          "无档位时也保留计划说明")

    // 通知去重与已读后重建
    try store.addNotificationIfNeeded(alertId: "n1", kind: "hit", title: "提醒")
    try store.addNotificationIfNeeded(alertId: "n1", kind: "hit", title: "提醒")
    check(try store.notifications().count == 1, "同一未读通知不重复写入")
    let notification = try store.notifications().first!
    try store.markNotificationRead(id: notification.id)
    check(try store.hasNotification(alertId: "n1"), "已读通知仍可查询")
    check(!(try store.hasNotification(alertId: "n-missing")), "未产生的提醒查不到通知")
    try store.addNotificationIfNeeded(alertId: "n1", kind: "hit", title: "提醒")
    check(try store.notifications().count == 2, "已读后可以再生成提醒")
} catch { failures.append("0.8.3 fixes: \(error)") }

do {
    let stop = PlanLevel(id: "stop", price: 20, kind: .stop, quantity: nil, condition: "暂停")
    let below = Quote(code: "A", name: "A", price: 19, prevClose: 19, time: "", source: .eastmoney)
    let above = Quote(code: "A", name: "A", price: 21, prevClose: 20, time: "", source: .eastmoney)
    check(AlertEngine.crossed(previous: below, current: above, level: stop),
          "停止买入档向上穿越触发")
    check(!AlertEngine.crossed(previous: above, current: above, level: stop),
          "持续高于停止档不重复触发")
}

// MARK: - P2 coverage

func shanghai(_ text: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = MarketHours.zone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: text)!
}

// 交易时段
check(MarketHours.isTrading(.share, at: shanghai("2026-11-09 10:00")), "A股上午交易")
check(!MarketHours.isTrading(.share, at: shanghai("2026-11-09 12:00")), "A股午休")
check(MarketHours.isTrading(.share, at: shanghai("2026-11-09 14:00")), "A股下午交易")
check(!MarketHours.isTrading(.share, at: shanghai("2026-11-07 10:00")), "周末不交易")
check(MarketHours.isTrading(.fund, at: shanghai("2026-11-09 21:00")), "基金工作日可查询")
check(!MarketHours.isTrading(.fund, at: shanghai("2026-11-07 12:00")), "基金周末不查询")
check(MarketHours.isTrading(.gram, at: shanghai("2026-11-09 21:00")), "黄金夜盘")
check(MarketHours.isTrading(.gram, at: shanghai("2026-11-10 02:00")), "黄金夜盘跨日")
check(!MarketHours.isTrading(.gram, at: shanghai("2026-11-10 04:00")), "黄金夜盘结束")
check(MarketHours.isTrading(.hk, at: shanghai("2026-11-09 10:00")), "港股上午")
check(!MarketHours.isTrading(.hk, at: shanghai("2026-11-09 12:30")), "港股午休")
check(MarketHours.isTrading(.hk, at: shanghai("2026-11-09 14:00")), "港股下午")

// 停止档生效后不再推荐买入档
let plan = Plan(id: 1, positionId: 1, version: 1, author: "user",
                description: nil, nextReview: nil, levels: [
                    PlanLevel(id: "b", price: 9, kind: .buy, quantity: 10, condition: ""),
                    PlanLevel(id: "s", price: 15, kind: .sell, quantity: 10, condition: "")
                ], updatedAt: "")
check(PortfolioBuilder.nextLevel(plan: plan, price: 10, done: [])?.kind == .buy,
      "无停止档时推荐买入档")
check(PortfolioBuilder.nextLevel(plan: plan, price: 10, done: [], buyBlocked: true)?.kind == .sell,
      "停止档生效后推荐卖出档")

// 记忆范围过滤与最近使用
do {
    let (store, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try store.addMemory(scope: .global, scopeId: nil, kind: .principle,
                            title: "全局", content: "g", evidence: "", confidence: 0.8)
    let scoped = try store.addMemory(scope: .instrument, scopeId: "600000", kind: .fact,
                                     title: "标的", content: "i", evidence: "", confidence: 0.8)
    check(try store.memories(scope: .instrument).count == 1, "记忆按范围过滤")
    try store.touchMemories(ids: [scoped.id])
    check(try store.memories(scope: .instrument).first?.lastUsedAt != nil, "记忆记录最近使用")
} catch { failures.append("memory scope: \(error)") }

// v7 -> v8 迁移生成备份并删除旧 AI 表
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("store.sqlite3").path
    var db: OpaquePointer?
    check(sqlite3_open(path, &db) == SQLITE_OK, "创建 v7 测试库")
    let sql = """
    PRAGMA user_version = 7;
    CREATE TABLE ai_providers (id INTEGER PRIMARY KEY);
    CREATE TABLE ai_models (id INTEGER PRIMARY KEY);
    CREATE TABLE task_routes (id INTEGER PRIMARY KEY);
    CREATE TABLE threads (id INTEGER PRIMARY KEY);
    CREATE TABLE messages (id INTEGER PRIMARY KEY);
    """
    check(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "写入 v7 结构")
    sqlite3_close(db)
    let store = try Store(path: path)
    check(try store.schemaVersion() == 8, "v7 迁移到 v8")
    check(try !store.tableExists("ai_providers"), "迁移删除旧 AI 表")
    check(FileManager.default.fileExists(atPath: path + ".7-backup"), "迁移前生成备份")
} catch { failures.append("migration: \(error)") }

if failures.isEmpty { print("CORE TESTS PASS \(checks) checks") }
else {
    print("CORE TESTS FAIL \(failures.count)/\(checks)")
    failures.forEach { print(" - \($0)") }
}
exit(failures.isEmpty ? 0 : 1)
