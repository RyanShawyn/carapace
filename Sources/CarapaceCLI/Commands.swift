import Foundation
import Security
import CarapaceCore

enum Router {
    static func run(args: CLIArgs, store: Store) async throws -> Any {
        switch args.group {
        case "doctor": return try doctor(store: store)
        case "schema": return schema()
        case "version": return version()
        case "portfolio": return try await portfolio(args: args, store: store)
        case "positions": return try await positions(args: args, store: store)
        case "trades": return try trades(args: args, store: store)
        case "plans": return try plans(args: args, store: store)
        case "drafts": return try drafts(args: args, store: store)
        case "watch": return try watch(args: args, store: store)
        case "import": return try imports(args: args, store: store)
        case "accounts": return try accounts(args: args, store: store)
        case "reviews": return try reviews(args: args, store: store)
        case "memories": return try memories(args: args, store: store)
        case "metrics": return try metrics(args: args, store: store)
        case "style": return try style(args: args, store: store)
        case "alerts": return try alerts(args: args, store: store)
        case "notifications": return try notifications(args: args, store: store)
        case "quotes": return try await quotes(args: args, store: store)
        case "search": return try await search(args: args)
        case "settings": return try settings(args: args)
        case "backup": return try backup(args: args, store: store)
        case "verify": return ["fixed": try store.verifyAll()]
        case "export-csv": return try exportCSV(args: args, store: store)
        case "maintenance": return try maintenance(args: args)
        default: throw CLIError.usage("未知命令：\(args.group)")
        }
    }
}

// MARK: - Meta

private func doctor(store: Store) throws -> [String: Any] {
    let schema = try store.schemaVersion()
    let path = store.path
    let exists = FileManager.default.fileExists(atPath: path)
    let permissions = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
    let appRunning = processRunning("carapace")
    let keys = aiKeyCount()

    var checks: [[String: Any]] = [
        ["name": "database", "ok": exists, "detail": path],
        ["name": "schema", "ok": schema == 8, "detail": "v\(schema)"],
        ["name": "permissions", "ok": permissions == 0o600 || permissions == nil, "detail": permissions.map { String($0, radix: 8) } ?? "unknown"],
        ["name": "ai_keys", "ok": keys == 0, "detail": "\(keys) 个遗留密钥"]
    ]
    if appRunning {
        checks.append(["name": "app_running", "ok": true, "detail": "App 正在运行；首次升级请先退出 App"])
    }

    let healthy = exists && schema == 8
        && (permissions == 0o600 || permissions == nil)
    return [
        "healthy": healthy,
        "checks": checks,
        "api_version": CarapaceBuild.apiVersion,
        "app_version": CarapaceBuild.version,
        "schema_version": schema,
        "db": path,
        "app_running": appRunning
    ]
}

func schema() -> [String: Any] {
    [
        "api_version": CarapaceBuild.apiVersion,
        "app_version": CarapaceBuild.version,
        "schema_version": 8,
        "envelope": [
            "success": ["ok": true, "data": "object|array", "meta": "object"],
            "failure": ["ok": false, "error": ["code": "string", "message": "string", "hint": "string?"]]
        ],
        "exit_codes": ["0": "ok", "2": "usage", "3": "validation", "4": "not_found", "5": "conflict", "6": "db", "7": "quote", "9": "internal"],
        "groups": ["doctor", "schema", "version", "portfolio", "positions", "trades", "plans",
                   "drafts", "watch", "import", "accounts", "reviews", "memories",
                   "metrics", "style", "alerts", "notifications", "quotes", "search", "settings",
                   "backup", "verify", "export-csv", "maintenance"]
    ]
}

func version() -> [String: Any] {
    [
        "app_version": CarapaceBuild.version,
        "api_version": CarapaceBuild.apiVersion,
        "schema_version": 8
    ]
}

// MARK: - Portfolio and positions

private func portfolio(args: CLIArgs, store: Store) async throws -> [String: Any] {
    let positions = try store.positions()
    let plans = try plansFor(positions, store: store)
    let executed = try executedFor(positions, store: store)
    var quotes: [String: Quote] = [:]
    if !args.bool("no-quotes") {
        QuoteService.shared.cmbSpread = CarapaceDefaults.cmbSpread
        quotes = (try? await QuoteService.shared.fetch(positions: positions, force: args.bool("refresh"))) ?? [:]
    }
    let built = PortfolioBuilder.build(positions: positions, plans: plans, quotes: quotes,
                                       executed: executed, hkdRate: CarapaceDefaults.hkdRate)
    var rows: [[String: Any]] = []
    for view in built.views {
        var row = positionDict(view.position)
        row["quote"] = view.quote.map(quoteDict) ?? NSNull()
        row["value"] = optional(view.value)
        row["valueCNY"] = optional(view.valueCNY)
        row["todayPnl"] = optional(view.todayPnl)
        row["totalPnl"] = optional(view.totalPnl)
        row["weight"] = optional(view.weight)
        row["fxRate"] = view.fxRate
        row["nextLevel"] = view.nextLevel.map(levelDict) ?? NSNull()
        rows.append(row)
    }
    var data: [String: Any] = [
        "currency": "CNY",
        "totalValue": built.totalValue,
        "totalCost": built.totalCost,
        "hasCompleteValuation": built.hasCompleteValuation,
        "positions": rows
    ]
    data["totalPnl"] = optional(built.totalPnl)
    data["todayPnl"] = optional(built.todayPnl)
    return data
}

private func positions(args: CLIArgs, store: Store) async throws -> Any {
    switch args.verb {
    case "list":
        let includeClosed = args.bool("closed") || args.bool("include-closed")
        let rows = try store.positions(includeClosed: includeClosed)
        return rows.map { position -> [String: Any] in
            var row = positionDict(position)
            if let plan = try? store.plan(positionId: position.id) {
                row["planVersion"] = plan.version
                row["nextReview"] = optional(plan.nextReview)
            }
            return row
        }
    case "get":
        let position = try resolvePosition(args: args, store: store)
        var row = positionDict(position)
        if let plan = try? store.plan(positionId: position.id) {
            row["plan"] = planDict(plan)
            row["executedLevels"] = Array(try store.executedLevelPrices(positionId: position.id)).sorted()
        }
        row["changes"] = try store.changes(positionId: position.id, limit: 50).map(changeDict)
        let quote = QuoteService.shared.lastQuote(for: position.quoteCode)
        row["cachedQuote"] = quote.map(quoteDict) ?? NSNull()
        return row
    case "add":
        let code = try args.require("code")
        let name = try args.require("name")
        let quantity = try args.double("quantity") ?? 0
        let cost = try args.double("cost") ?? 0
        let market = InstrumentMarket(rawValue: args.value("market") ?? "cn") ?? .cn
        let source = args.value("source").flatMap(QuoteSource.init(rawValue:))
        let unit = args.value("unit").flatMap(UnitKind.init(rawValue:))
        let planLevels = try args.value("plan-file").map(loadLevels) ?? []
        let description = args.value("description")
        let nextReview = args.value("next-review")
        let openedAt = args.value("opened-at") ?? Dates.today()
        let quoteKey = args.value("quote-key")

        return try performWrite(args: args, store: store, command: "positions.add", preview: {
            ["code": code, "name": name, "quantity": quantity, "cost": cost,
             "market": market.rawValue, "planLevels": planLevels.map(levelDict)]
        }, body: {
            let position = try store.addPosition(code: code, name: name, source: source, unit: unit,
                                                 quantity: quantity, cost: cost,
                                                 openedAt: openedAt, plan: planLevels,
                                                 description: description, nextReview: nextReview,
                                                 market: market, quoteKey: quoteKey)
            return positionDict(position)
        })
    case "correct":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        guard let current = try store.position(id: id) else {
            throw CLIError.notFound("持仓不存在")
        }
        let reason = try args.require("reason")
        let quantity = try args.double("quantity")
        let cost = try args.double("cost")
        guard quantity != nil || cost != nil else {
            throw CLIError.usage("至少提供 --quantity 或 --cost")
        }
        return try performWrite(args: args, store: store, command: "positions.correct", preview: {
            ["id": id, "fromQuantity": current.quantity, "toQuantity": optional(quantity),
             "fromCost": current.avgCost, "toCost": optional(cost), "reason": reason]
        }, body: {
            if let quantity, abs(quantity - current.quantity) > 1e-9 {
                _ = try store.adjustPosition(positionId: id, delta: quantity - current.quantity,
                                             costAfter: cost, note: reason)
            } else if let cost, abs(cost - current.avgCost) > 1e-9 {
                _ = try store.setCost(positionId: id, cost: cost, note: reason)
            }
            return try positionDict(store.position(id: id)!)
        })
    case "clear":
        try args.requireYes("清仓")
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let price = try args.double("price") ?? 0
        let fee = try args.double("fee") ?? 0
        let note = args.value("note")
        return try performWrite(args: args, store: store, command: "positions.clear", preview: {
            ["id": id, "price": price, "fee": fee]
        }, body: {
            let result = try store.clearPosition(positionId: id, price: price, fee: fee, note: note)
            return ["position": positionDict(result.position), "change": changeDict(result.change)]
        })
    case "changes":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let type = try parseChangeType(args.value("type"))
        let limit = Int(try args.int64("limit") ?? 200)
        return try store.changes(positionId: id, type: type, limit: limit).map(changeDict)
    default:
        throw CLIError.usage("positions 需要 list|get|add|correct|clear|changes")
    }
}

private func resolvePosition(args: CLIArgs, store: Store) throws -> Position {
    if let id = try args.int64("id") {
        guard let position = try store.position(id: id) else {
            throw CLIError.notFound("持仓不存在：\(id)")
        }
        return position
    }
    if let code = args.value("code") {
        return try positionByCode(code, store: store)
    }
    throw CLIError.usage("需要 --id 或 --code")
}

// MARK: - Trades

private func trades(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "record":
        let id = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
        guard let position = try store.position(id: id) else {
            throw CLIError.notFound("持仓不存在")
        }
        guard let rawSide = args.value("side"), let side = TradeSide(rawValue: rawSide) else {
            throw CLIError.usage("--side 必须是 buy 或 sell")
        }
        let quantity = try args.double("quantity") ?? 0
        let price = try args.double("price") ?? 0
        let fee = try args.double("fee") ?? 0
        let occurredAt = args.value("occurred-at") ?? Dates.today()
        let levelId = args.value("level-id")
        let note = args.value("note")

        return try performWrite(args: args, store: store, command: "trades.record", preview: {
            let qtyAfter = side == .buy ? position.quantity + quantity : position.quantity - quantity
            let cost = side == .buy && qtyAfter > 0
                ? (position.quantity * position.avgCost + quantity * price + fee) / qtyAfter
                : position.avgCost
            return ["positionId": id, "side": side.rawValue, "quantity": quantity, "price": price,
                    "fee": fee, "quantityAfter": qtyAfter, "avgCostAfter": cost,
                    "occurredAt": occurredAt]
        }, body: {
            let result = try store.recordTrade(positionId: id, side: side, quantity: quantity,
                                               price: price, fee: fee, levelId: levelId,
                                               note: note, occurredAt: occurredAt)
            return ["position": positionDict(result.position), "change": changeDict(result.change)]
        })
    case "list":
        let type = try parseChangeType(args.value("type"))
        let limit = Int(try args.int64("limit") ?? 200)
        if let id = try args.int64("position") {
            return try store.changes(positionId: id, type: type, limit: limit).map(changeDict)
        }
        return try store.allChanges(type: type, limit: limit).map(changeDict)
    default:
        throw CLIError.usage("trades 需要 record|list")
    }
}

// MARK: - Plans and drafts

private func plans(args: CLIArgs, store: Store) throws -> Any {
    let positionId = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
    switch args.verb {
    case "get":
        guard let plan = try store.plan(positionId: positionId) else {
            throw CLIError.notFound("该持仓还没有计划")
        }
        var result = planDict(plan)
        result["executedLevels"] = Array(try store.executedLevelPrices(positionId: positionId)).sorted()
        return result
    case "update":
        let levels = try loadLevels(path: try args.require("levels-file"))
        let description = args.value("description")
        let nextReview = args.value("next-review")
        let note = args.value("note")
        let ifVersion = try args.int64("if-version").map(Int.init)
        let current = try store.plan(positionId: positionId)
        if current != nil, ifVersion == nil {
            throw CLIError.validation("修改已有计划必须提供 --if-version，避免覆盖他人修改")
        }
        return try performWrite(args: args, store: store, command: "plans.update", preview: {
            let diff = Store.diff(old: current?.levels ?? [], new: levels)
            return ["positionId": positionId, "diff": jsonable(diff)]
        }, body: {
            let result = try store.updatePlan(positionId: positionId, levels: levels,
                                              description: description, nextReview: nextReview,
                                              note: note, author: "agent", ifVersion: ifVersion)
            return ["plan": planDict(result.plan), "diff": jsonable(result.diff)]
        })
    case "remove":
        try args.requireYes("移除计划")
        return try performWrite(args: args, store: store, command: "plans.remove", preview: {
            guard let plan = try store.plan(positionId: positionId) else {
                throw CLIError.notFound("该标的还没有计划")
            }
            return ["positionId": positionId, "planVersion": plan.version,
                    "levels": plan.levels.count]
        }, body: {
            let plan = try store.removePlan(positionId: positionId, note: args.value("note"))
            return ["positionId": positionId, "removed": true, "planVersion": plan.version]
        })
    default:
        throw CLIError.usage("plans 需要 get|update|remove")
    }
}

private func drafts(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        let status = args.value("status")
        return try store.drafts(status: status, limit: Int(try args.int64("limit") ?? 100)).map(draftDict)
    case "create":
        let positionId = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
        let kind = args.value("kind") ?? "plan"
        let payload = try loadPayload(path: try args.require("payload-file"))
        let baseVersion = try args.int64("base-version").map(Int.init)
        let note = args.value("note")
        return try performWrite(args: args, store: store, command: "drafts.create", preview: {
            ["positionId": positionId, "kind": kind, "payload": payload, "baseVersion": optional(baseVersion)]
        }, body: {
            let draft = try store.addDraft(kind: kind, positionId: positionId, skill: "carapace",
                                           payload: payload, baseVersion: baseVersion,
                                           baseQuantity: nil, profileId: nil, note: note)
            return draftDict(draft)
        })
    case "apply":
        try args.requireYes("应用草稿")
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        guard let draft = try store.drafts(status: nil, limit: 500).first(where: { $0.id == id }) else {
            throw CLIError.notFound("草稿不存在")
        }
        guard draft.status == "pending" else {
            throw CLIError.validation("草稿已经是 \(draft.status) 状态，不能重复应用")
        }
        return try performWrite(args: args, store: store, command: "drafts.apply", preview: {
            ["id": id, "positionId": optional(draft.positionId), "kind": draft.kind]
        }, body: {
            let result = try DraftService.applyPlanDraft(draft, store: store)
            return ["plan": planDict(result.plan), "diff": jsonable(result.diff)]
        })
    case "discard":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        return try performWrite(args: args, store: store, command: "drafts.discard", preview: {
            ["id": id, "status": "discarded"]
        }, body: {
            try store.decideDraft(id: id, status: "discarded")
            return ["id": id, "status": "discarded"]
        })
    default:
        throw CLIError.usage("drafts 需要 list|create|apply|discard")
    }
}

// MARK: - Watch

private func watch(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        return try store.watches().map(positionDict)
    case "add":
        let code = try args.require("code")
        let name = try args.require("name")
        let market = InstrumentMarket(rawValue: args.value("market") ?? "cn") ?? .cn
        let source = args.value("source").flatMap(QuoteSource.init(rawValue:))
        let unit = args.value("unit").flatMap(UnitKind.init(rawValue:))
        let watchPrice = try args.double("watch-price")
        let note = args.value("note")
        let planLevels = try args.value("plan-file").map(loadLevels) ?? []
        let quoteKey = args.value("quote-key")
        return try performWrite(args: args, store: store, command: "watch.add", preview: {
            ["code": code, "name": name, "market": market.rawValue, "watchPrice": optional(watchPrice)]
        }, body: {
            let position = try store.addWatch(code: code, name: name, source: source, unit: unit,
                                              watchPrice: watchPrice, note: note,
                                              plan: planLevels,
                                              market: market, quoteKey: quoteKey)
            return positionDict(position)
        })
    case "update":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let watchPrice = try args.double("watch-price")
        let note = args.value("note")
        let name = args.value("name")
        return try performWrite(args: args, store: store, command: "watch.update", preview: {
            ["id": id, "watchPrice": optional(watchPrice), "note": optional(note)]
        }, body: {
            try store.updateWatch(id: id, watchPrice: watchPrice, note: note, name: name)
            guard let position = try store.position(id: id) else {
                throw CLIError.notFound("观察标的不存在")
            }
            return positionDict(position)
        })
    case "remove":
        try args.requireYes("删除观察")
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        return try performWrite(args: args, store: store, command: "watch.remove", preview: {
            ["id": id]
        }, body: {
            try store.removeWatch(id: id)
            return ["id": id, "removed": true]
        })
    case "convert":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let quantity = try args.double("quantity") ?? 0
        let cost = try args.double("cost") ?? 0
        let openedAt = args.value("opened-at") ?? Dates.today()
        return try performWrite(args: args, store: store, command: "watch.convert", preview: {
            ["id": id, "quantity": quantity, "cost": cost]
        }, body: {
            let position = try store.convertWatchToHolding(id: id, quantity: quantity, cost: cost, openedAt: openedAt)
            return positionDict(position)
        })
    case "carry":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let watchPrice = try args.double("watch-price")
        let note = args.value("note")
        return try performWrite(args: args, store: store, command: "watch.carry", preview: {
            ["id": id, "watchPrice": optional(watchPrice)]
        }, body: {
            let position = try store.carryClosedToWatch(positionId: id, watchPrice: watchPrice, note: note)
            return positionDict(position)
        })
    default:
        throw CLIError.usage("watch 需要 list|add|update|remove|convert|carry")
    }
}

// MARK: - Imports and accounts

private func imports(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "preview":
        let path = try args.require("file")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let account = try resolveAccount(args: args, store: store)
        let mapping = try loadMapping(path: args.value("mapping-file"))
        let preview = try ImportService.preview(data: data, accountId: account.id,
                                                store: store, mapping: mapping)
        return previewDict(preview)
    case "commit":
        try args.requireYes("提交交割单")
        let path = try args.require("file")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let account = try resolveAccount(args: args, store: store)
        let broker = args.value("broker") ?? "导入"
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let mapping = try loadMapping(path: args.value("mapping-file"))
        let includeNeedsReview = args.bool("include-needs-review")
        return try performWrite(args: args, store: store, command: "import.commit", preview: {
            let preview = try ImportService.preview(data: data, accountId: account.id,
                                                    store: store, mapping: mapping,
                                                    allowMissing: true)
            return previewDict(preview)
        }, body: {
            let preview = try ImportService.preview(data: data, accountId: account.id,
                                                    store: store, mapping: mapping)
            let result = try ImportService.commit(preview: preview, accountId: account.id,
                                                  broker: broker, fileName: fileName,
                                                  store: store,
                                                  includeNeedsReview: includeNeedsReview)
            return [
                "batch": batchDict(result.batch),
                "imported": result.imported,
                "skipped": result.skipped,
                "needsReview": result.needsReview,
                "errors": result.errors
            ]
        })
    case "rollback":
        try args.requireYes("回滚导入批次")
        let id = try args.int64("batch") ?? { throw CLIError.usage("缺少 --batch") }()
        return try performWrite(args: args, store: store, command: "import.rollback", preview: {
            ["batch": id]
        }, body: {
            let count = try ImportService.rollback(batchId: id, store: store)
            return ["batch": id, "reverted": count]
        })
    case "batches":
        return try store.importBatches(limit: Int(try args.int64("limit") ?? 100)).map(batchDict)
    case "executions":
        let batchId = try args.int64("batch")
        return try store.executions(batchId: batchId, limit: Int(try args.int64("limit") ?? 1000)).map(executionDict)
    default:
        throw CLIError.usage("import 需要 preview|commit|rollback|batches|executions")
    }
}

private func accounts(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        return try store.accounts().map(accountDict)
    case "add":
        let broker = try args.require("broker")
        let name = try args.require("name")
        let accountNo = args.value("account-no")
        let currency = args.value("currency") ?? "CNY"
        let isDefault = args.bool("default")
        return try performWrite(args: args, store: store, command: "accounts.add", preview: {
            ["broker": broker, "name": name, "currency": currency, "isDefault": isDefault]
        }, body: {
            accountDict(try store.addAccount(broker: broker, name: name, accountNo: accountNo,
                                             currency: currency, isDefault: isDefault))
        })
    default:
        throw CLIError.usage("accounts 需要 list|add")
    }
}

private func resolveAccount(args: CLIArgs, store: Store) throws -> Account {
    if let id = try args.int64("account"),
       let account = try store.accounts().first(where: { $0.id == id }) {
        return account
    }
    guard let account = try store.defaultAccount() else {
        throw CLIError.notFound("没有默认账户，先运行 accounts add --default")
    }
    return account
}

private func previewDict(_ preview: ImportPreview) -> [String: Any] {
    [
        "summary": [
            "total": preview.summary.total,
            "ready": preview.summary.ready,
            "duplicate": preview.summary.duplicate,
            "needsReview": preview.summary.needsReview,
            "errors": preview.summary.errors
        ],
        "mapping": preview.mapping,
        "headers": preview.headers,
        "rows": preview.rows.prefix(50).map { row in
            [
                "row": row.rowNumber,
                "tradeTime": row.tradeTime,
                "code": row.code,
                "name": row.name,
                "side": row.side.rawValue,
                "quantity": row.quantity,
                "price": row.price,
                "feeTotal": row.feeTotal,
                "status": row.status.rawValue,
                "message": row.message
            ] as [String: Any]
        }
    ]
}

// MARK: - Reviews

private func reviews(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        let includeDone = args.bool("include-done")
        return try store.reviews(includeDone: includeDone, limit: Int(try args.int64("limit") ?? 200)).map(reviewDict)
    case "get":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        guard let review = try store.review(id: id) else {
            throw CLIError.notFound("复盘不存在")
        }
        return reviewDict(review)
    case "create":
        let positionId = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
        guard let position = try store.position(id: positionId) else {
            throw CLIError.notFound("持仓不存在")
        }
        let kind = args.value("kind") ?? "plan"
        let dueAt = args.value("due") ?? Dates.today()
        let facts = try ReviewService.facts(store: store, position: position, quotes: [:])
        return try performWrite(args: args, store: store, command: "reviews.create", preview: {
            ["positionId": positionId, "kind": kind, "dueAt": dueAt]
        }, body: {
            reviewDict(try store.createReview(positionId: positionId, kind: kind, dueAt: dueAt,
                                              profileId: nil, factsJSON: facts))
        })
    case "save":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        let notes = try args.value("notes-file").map(readText) ?? args.value("notes") ?? ""
        let outcome = try args.value("outcome-file").map(readText)
        let complete = args.bool("complete")
        return try performWrite(args: args, store: store, command: "reviews.save", preview: {
            ["id": id, "notesLength": notes.count, "complete": complete]
        }, body: {
            try store.saveReview(id: id, notes: notes, outcomeJSON: outcome, complete: complete)
            guard let review = try store.review(id: id) else {
                throw CLIError.notFound("复盘不存在")
            }
            return reviewDict(review)
        })
    default:
        throw CLIError.usage("reviews 需要 list|get|create|save")
    }
}

// MARK: - Memories, profiles, metrics

private func memories(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        let scope = args.value("scope").flatMap(MemoryScope.init(rawValue:))
        let status = args.value("status") ?? "active"
        let items = try store.memories(scope: scope, status: status, limit: Int(try args.int64("limit") ?? 200))
        return items.map(memoryDict)
    case "context":
        let positionId = try args.int64("position")
        let code = args.value("code")
        let items = try MemoryEngine.context(store: store, positionId: positionId,
                                             profileId: nil, code: code)
        return ["memories": items.map(memoryDict), "text": MemoryEngine.contextBlock(items)]
    case "add":
        guard let scopeRaw = args.value("scope"), let scope = MemoryScope(rawValue: scopeRaw),
              scope != .profile else {
            throw CLIError.usage("--scope 必须是 global|instrument|position")
        }
        guard let kindRaw = args.value("kind"), let kind = MemoryKind(rawValue: kindRaw) else {
            throw CLIError.usage("--kind 必须是 principle|preference|pattern|lesson|fact|hypothesis")
        }
        let title = try args.require("title")
        let content = try args.require("content")
        let scopeId = args.value("scope-id")
        let evidence = args.value("evidence") ?? "外部 Agent 添加"
        let confidence = try args.double("confidence") ?? 0.8
        return try performWrite(args: args, store: store, command: "memories.add", preview: {
            ["scope": scope.rawValue, "kind": kind.rawValue, "title": title]
        }, body: {
            memoryDict(try store.addMemory(scope: scope, scopeId: scopeId, kind: kind,
                                           title: title, content: content, evidence: evidence,
                                           confidence: confidence, source: "agent"))
        })
    case "update":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        guard var memory = try store.memories(status: "active", limit: 1000).first(where: { $0.id == id })
                ?? store.memories(status: "archived", limit: 1000).first(where: { $0.id == id }) else {
            throw CLIError.notFound("记忆不存在")
        }
        if let title = args.value("title") { memory.title = title }
        if let content = args.value("content") { memory.content = content }
        if let confidence = try args.double("confidence") { memory.confidence = confidence }
        return try performWrite(args: args, store: store, command: "memories.update", preview: {
            ["id": id, "title": memory.title, "confidence": memory.confidence]
        }, body: {
            try store.updateMemory(memory)
            return memoryDict(memory)
        })
    case "archive":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        return try performWrite(args: args, store: store, command: "memories.archive", preview: {
            ["id": id, "status": "archived"]
        }, body: {
            try store.archiveMemory(id: id)
            return ["id": id, "status": "archived"]
        })
    default:
        throw CLIError.usage("memories 需要 list|context|add|update|archive")
    }
}


private func metrics(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        let id = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
        return try store.metrics(positionId: id).map(metricDict)
    case "set":
        let id = try args.int64("position") ?? { throw CLIError.usage("缺少 --position") }()
        let key = try args.require("key")
        let label = args.value("label") ?? key
        let value = try args.require("value")
        let unit = args.value("unit")
        let note = args.value("note")
        let display = unit.map { "\(value) \($0)" } ?? value
        return try performWrite(args: args, store: store, command: "metrics.set", preview: {
            ["positionId": id, "key": key, "label": label, "value": display]
        }, body: {
            try store.setMetric(positionId: id, key: key, label: label, value: display,
                                source: "agent", asOf: Dates.today(), note: note)
            return ["positionId": id, "key": key, "value": display]
        })
    default:
        throw CLIError.usage("metrics 需要 list|set")
    }
}

// MARK: - Style, alerts, notifications

private func style(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "compute":
        return styleDict(try StyleEngine.compute(store: store, hkdRate: CarapaceDefaults.hkdRate))
    case "snapshots":
        return try store.styleSnapshots(limit: Int(try args.int64("limit") ?? 50)).map { snapshot in
            [
                "id": snapshot.id,
                "asOf": snapshot.asOf,
                "narrative": snapshot.narrative,
                "metrics": jsonable(snapshot.metrics)
            ] as [String: Any]
        }
    case "save":
        let narrative = try readText(path: try args.require("narrative-file"))
        let metrics = try StyleEngine.compute(store: store, hkdRate: CarapaceDefaults.hkdRate)
        return try performWrite(args: args, store: store, command: "style.save", preview: {
            ["narrativeLength": narrative.count]
        }, body: {
            let snapshot = try store.saveStyleSnapshot(metrics, narrative: narrative)
            return ["id": snapshot.id, "asOf": snapshot.asOf, "narrative": snapshot.narrative]
        })
    default:
        throw CLIError.usage("style 需要 compute|snapshots|save")
    }
}

private func alerts(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        return try store.alerts(includeResolved: args.bool("resolved"),
                                limit: Int(try args.int64("limit") ?? 200)).map(alertDict)
    case "ack":
        let id = try args.require("id")
        return try performWrite(args: args, store: store, command: "alerts.ack", preview: {
            ["id": id, "acknowledged": true]
        }, body: {
            try store.acknowledgeAlert(id: id)
            return ["id": id, "acknowledged": true]
        })
    case "ack-all":
        return try performWrite(args: args, store: store, command: "alerts.ackAll", preview: {
            ["acknowledged": "all"]
        }, body: {
            try store.acknowledgeAllAlerts()
            return ["acknowledged": "all"]
        })
    default:
        throw CLIError.usage("alerts 需要 list|ack|ack-all")
    }
}

private func notifications(args: CLIArgs, store: Store) throws -> Any {
    switch args.verb {
    case "list":
        return try store.notifications(unreadOnly: args.bool("unread"),
                                        limit: Int(try args.int64("limit") ?? 200)).map(notificationDict)
    case "read":
        let id = try args.int64("id") ?? { throw CLIError.usage("缺少 --id") }()
        return try performWrite(args: args, store: store, command: "notifications.read", preview: {
            ["id": id]
        }, body: {
            try store.markNotificationRead(id: id)
            return ["id": id, "read": true]
        })
    case "read-all":
        return try performWrite(args: args, store: store, command: "notifications.readAll", preview: {
            ["read": "all"]
        }, body: {
            try store.markAllNotificationsRead()
            return ["read": "all"]
        })
    default:
        throw CLIError.usage("notifications 需要 list|read|read-all")
    }
}

// MARK: - Quotes and search

private func quotes(args: CLIArgs, store: Store) async throws -> Any {
    switch args.verb {
    case "get":
        let code = try args.require("code")
        let market = InstrumentMarket(rawValue: args.value("market") ?? "cn") ?? .cn
        let source = try quoteSource(for: args, market: market)
        let quoteKey: String
        if let explicit = args.value("quote-key") {
            quoteKey = explicit
        } else if market == .hk {
            quoteKey = "116.\(code)"
        } else if market == .us {
            quoteKey = await QuoteService.shared.resolveUSQuoteKey(symbol: code) ?? code
        } else {
            quoteKey = code
        }
        QuoteService.shared.cmbSpread = CarapaceDefaults.cmbSpread
        do {
            let quotes = try await QuoteService.shared.fetch(codes: [(quoteKey, source)], force: true)
            guard let quote = quotes[quoteKey.uppercased()] ?? quotes[quoteKey] else {
                throw CLIError.quote("没有拿到 \(code) 的行情")
            }
            return quoteDict(quote)
        } catch let error as QuoteError {
            throw CLIError.quote(error.localizedDescription)
        }
    case "tracked":
        let positions = try store.trackedPositions()
        QuoteService.shared.cmbSpread = CarapaceDefaults.cmbSpread
        let quotes = try await QuoteService.shared.fetch(positions: positions, force: args.bool("refresh"))
        return positions.compactMap { position -> [String: Any]? in
            guard let quote = quotes[position.quoteCode] else { return nil }
            var row = quoteDict(quote)
            row["positionId"] = position.id
            row["name"] = position.name
            return row
        }
    case "indices":
        QuoteService.shared.cmbSpread = CarapaceDefaults.cmbSpread
        let quotes = try await QuoteService.shared.fetchIndices()
        return quotes.values.map(quoteDict)
    default:
        throw CLIError.usage("quotes 需要 get|tracked|indices")
    }
}

private func search(args: CLIArgs) async throws -> Any {
    let keyword = try args.require("keyword")
    let results = try await QuoteService.shared.searchSymbols(keyword)
    return results.map { result in
        [
            "code": result.code,
            "name": result.name,
            "market": result.market,
            "instrumentMarket": result.instrumentMarket.rawValue,
            "source": result.source.rawValue,
            "unit": result.unit.rawValue,
            "quoteKey": optional(result.quoteKey),
            "canHold": result.canHold,
            "currency": result.currency
        ] as [String: Any]
    }
}

// MARK: - Settings and maintenance

private let settingKeys: Set<String> = [
    "hkdRate", "cmbSpread", "showIndexStrip", "showMenuBarIcon", "eastmoneyInterval",
    "sinaInterval", "backgroundCheck", "backgroundMinutes", "muted", "systemNotifications",
    "autoReview", "quietHours", "singlePositionLimit",
    "autoCheck", "autoUpdate", "relaunchAfterUpdate"
]

private func settings(args: CLIArgs) throws -> Any {
    let defaults = CarapaceDefaults.store
    switch args.verb {
    case "list":
        var result: [String: Any] = [:]
        for key in settingKeys {
            result[key] = optional(defaults.object(forKey: key))
        }
        return result
    case "get":
        let key = try args.require("key")
        guard settingKeys.contains(key) else { throw CLIError.usage("未知设置项：\(key)") }
        return ["key": key, "value": optional(defaults.object(forKey: key))]
    case "set":
        let key = try args.require("key")
        guard settingKeys.contains(key) else { throw CLIError.usage("未知设置项：\(key)") }
        let raw = try args.require("value")
        if ["showIndexStrip", "showMenuBarIcon", "backgroundCheck", "muted", "systemNotifications",
            "autoReview", "quietHours", "autoCheck", "autoUpdate",
            "relaunchAfterUpdate"].contains(key) {
            guard let value = Bool(raw) else { throw CLIError.validation("\(key) 必须是 true 或 false") }
            defaults.set(value, forKey: key)
        } else if let value = Double(raw) {
            defaults.set(value, forKey: key)
        } else {
            throw CLIError.validation("\(key) 必须是数字")
        }
        if !args.noNotify { CarapaceNotify.post() }
        return ["key": key, "value": optional(defaults.object(forKey: key))]
    default:
        throw CLIError.usage("settings 需要 list|get|set")
    }
}

private func backup(args: CLIArgs, store: Store) throws -> Any {
    let path = try args.require("to")
    try store.backup(to: URL(fileURLWithPath: path))
    return ["backup": path]
}

private func exportCSV(args: CLIArgs, store: Store) throws -> Any {
    let path = try args.require("to")
    try store.exportChangesCSV(to: URL(fileURLWithPath: path))
    return ["csv": path]
}

private func maintenance(args: CLIArgs) throws -> Any {
    guard args.verb == "purge-ai-keys" else {
        throw CLIError.usage("maintenance 需要 purge-ai-keys")
    }
    try args.requireYes("删除遗留 AI 密钥")
    return ["removed": purgeAIKeys()]
}

// MARK: - Internal helpers

private func plansFor(_ positions: [Position], store: Store) throws -> [Int64: Plan] {
    var result: [Int64: Plan] = [:]
    for position in positions {
        if let plan = try? store.plan(positionId: position.id) {
            result[position.id] = plan
        }
    }
    return result
}

private func executedFor(_ positions: [Position], store: Store) throws -> [Int64: Set<String>] {
    var result: [Int64: Set<String>] = [:]
    for position in positions {
        result[position.id] = (try? store.executedLevelPrices(positionId: position.id)) ?? []
    }
    return result
}

private func processRunning(_ name: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", name]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

private let aiKeyService = "com.ryan.carapace.ai"

private func aiKeyCount() -> Int {
    aiKeys().count
}

private func aiKeys() -> [[String: Any]] {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: aiKeyService,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let items = result as? [[String: Any]] else { return [] }
    return items
}

private func purgeAIKeys() -> Int {
    var removed = 0
    for item in aiKeys() {
        var delete = item
        delete[kSecClass as String] = kSecClassGenericPassword
        if SecItemDelete(delete as CFDictionary) == errSecSuccess { removed += 1 }
    }
    return removed
}