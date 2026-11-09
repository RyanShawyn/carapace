import Foundation
import CarapaceCore

private struct Harness {
    var failures: [String] = []
    var checks = 0

    mutating func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures.append(message) }
    }

    mutating func expectClose(_ a: Double, _ b: Double, _ message: String,
                              tolerance: Double = 0.001) {
        expect(abs(a - b) <= tolerance, "\(message)（\(a) vs \(b)）")
    }

    mutating func expectThrows(_ message: String, _ body: () throws -> Void) {
        checks += 1
        do {
            try body()
            failures.append(message)
        } catch {
            // expected
        }
    }
}

@discardableResult
func runSelfTest() -> Int32 {
    let path = NSTemporaryDirectory() + "carapace-selftest-\(UUID().uuidString).sqlite3"
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    var h = Harness()

    do {
        let store = try Store(path: path)

        // 建仓 + 加权成本
        let p = try store.addPosition(code: "600000", name: "测试股份",
                                      quantity: 1000, cost: 10)
        h.expectClose(p.quantity, 1000, "建仓数量")
        h.expectClose(p.avgCost, 10, "建仓成本")

        let buy = try store.recordTrade(positionId: p.id, side: .buy,
                                        quantity: 1000, price: 20)
        h.expectClose(buy.position.quantity, 2000, "加仓后数量")
        h.expectClose(buy.position.avgCost, 15, "加仓后加权成本")

        let sell = try store.recordTrade(positionId: p.id, side: .sell,
                                         quantity: 500, price: 30)
        h.expectClose(sell.position.quantity, 1500, "减仓后数量")
        h.expectClose(sell.position.avgCost, 15, "减仓后成本不变")

        // 手动成本覆盖
        let override = try store.recordTrade(positionId: p.id, side: .buy,
                                             quantity: 100, price: 20, costAfter: 16.5)
        h.expectClose(override.position.avgCost, 16.5, "手动成本覆盖")
        let latest = try store.changes(positionId: p.id).first
        h.expectClose(latest?.costBefore ?? 0, 15, "日志记录变更前成本")
        h.expectClose(latest?.costAfter ?? 0, 16.5, "日志记录变更后成本")

        // 卖出不能超过持仓
        h.expectThrows("卖出超过持仓应报错") {
            _ = try store.recordTrade(positionId: p.id, side: .sell,
                                      quantity: 99999, price: 30)
        }

        // 计划版本与冲突
        let v1: [PlanLevel] = [
            .init(price: 9, kind: .buy, quantity: 100, condition: "一"),
            .init(price: 12, kind: .sell, quantity: 100, condition: "二")
        ]
        let first = try store.updatePlan(positionId: p.id, levels: v1, note: "初始")
        h.expect(first.plan.version == 1, "首版计划版本为 1")

        let v2: [PlanLevel] = [
            .init(id: v1[0].id, price: 9.5, kind: .buy, quantity: 100, condition: "一"),
            .init(id: v1[1].id, price: 12, kind: .sell, quantity: 100, condition: "二")
        ]
        let second = try store.updatePlan(positionId: p.id, levels: v2,
                                          note: "改一档", ifVersion: 1)
        h.expect(second.plan.version == 2, "第二版计划版本为 2")
        h.expect(second.diff.changed.count == 1, "diff 识别出 1 档修改")
        h.expect(second.diff.added.isEmpty, "diff 无新增")
        h.expectThrows("旧版本号保存应冲突") {
            _ = try store.updatePlan(positionId: p.id, levels: v2,
                                     note: "旧版本", ifVersion: 1)
        }

        // 计划变更也进日志
        let planRows = try store.changes(positionId: p.id).filter { $0.type == .plan }
        h.expect(planRows.count == 2, "计划日志应有 2 条（两版）")

        // 清仓与再次建仓
        let cleared = try store.clearPosition(positionId: p.id, price: 25)
        h.expectClose(cleared.position.quantity, 0, "清仓后数量为 0")
        h.expect(cleared.position.status == .closed, "清仓后状态关闭")

        let reopened = try store.addPosition(code: "600000", name: "测试股份",
                                             quantity: 300, cost: 18)
        h.expect(reopened.id != p.id, "再次买入生成新的持仓周期")

        // 重建校验
        let fixed = try store.verifyAll()
        h.expect(fixed == 0, "重建校验无偏差")

        // diff
        let old: [PlanLevel] = [
            .init(id: "a", price: 10, kind: .buy, quantity: 100, condition: "a"),
            .init(id: "b", price: 20, kind: .sell, quantity: 100, condition: "b")
        ]
        let new: [PlanLevel] = [
            .init(id: "a", price: 11, kind: .buy, quantity: 100, condition: "a"),
            .init(id: "c", price: 15, kind: .buy, quantity: 100, condition: "c")
        ]
        let diff = Store.diff(old: old, new: new)
        h.expect(diff.changed.count == 1, "diff 修改计数")
        h.expect(diff.added.count == 1, "diff 新增计数")
        h.expect(diff.removed.count == 1, "diff 删除计数")
    } catch {
        print("SELFTEST FAIL: \(error)")
        return 1
    }

    if h.failures.isEmpty {
        print("SELFTEST PASS \(h.checks) checks")
        return 0
    }
    print("SELFTEST FAIL \(h.failures.count)/\(h.checks)")
    for failure in h.failures { print("  - \(failure)") }
    return 1
}
