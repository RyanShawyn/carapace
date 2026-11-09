import Foundation
import CarapaceCore

// MARK: - JSON helpers

func optional(_ value: Any?) -> Any {
    value ?? NSNull()
}

func positionDict(_ p: Position) -> [String: Any] {
    [
        "id": p.id,
        "code": p.code,
        "name": p.name,
        "kind": p.kind.rawValue,
        "market": p.market.rawValue,
        "currency": p.currency,
        "source": p.source.rawValue,
        "unit": p.unit.rawValue,
        "quantity": p.quantity,
        "avgCost": p.avgCost,
        "status": p.status.rawValue,
        "openedAt": p.openedAt,
        "closedAt": optional(p.closedAt),
        "note": optional(p.note),
        "watchPrice": optional(p.watchPrice),
        "quoteKey": optional(p.quoteKey),
        "quoteCode": p.quoteCode
    ]
}

func levelDict(_ level: PlanLevel) -> [String: Any] {
    [
        "id": level.id,
        "kind": level.kind.rawValue,
        "price": level.price,
        "quantity": optional(level.quantity),
        "condition": level.condition
    ]
}

func planDict(_ plan: Plan) -> [String: Any] {
    [
        "id": plan.id,
        "positionId": plan.positionId,
        "version": plan.version,
        "author": plan.author,
        "description": optional(plan.description),
        "nextReview": optional(plan.nextReview),
        "levels": plan.levels.map(levelDict),
        "updatedAt": plan.updatedAt
    ]
}

func quoteDict(_ quote: Quote) -> [String: Any] {
    [
        "code": quote.code,
        "name": quote.name,
        "price": quote.price,
        "prevClose": quote.prevClose,
        "changePct": quote.changePct,
        "time": quote.time,
        "source": quote.source.rawValue,
        "sellPrice": optional(quote.sellPrice),
        "prevSellPrice": optional(quote.prevSellPrice),
        "valuationPrice": quote.valuationPrice
    ]
}

func changeDict(_ change: Change) -> [String: Any] {
    [
        "id": change.id,
        "positionId": change.positionId,
        "type": change.type.rawValue,
        "qtyBefore": optional(change.qtyBefore),
        "qtyAfter": optional(change.qtyAfter),
        "costBefore": optional(change.costBefore),
        "costAfter": optional(change.costAfter),
        "price": optional(change.price),
        "fee": optional(change.fee),
        "levelPrice": optional(change.levelPrice),
        "levelId": optional(change.levelId),
        "planVersion": optional(change.planVersion),
        "direction": optional(change.direction),
        "note": optional(change.note),
        "occurredAt": change.occurredAt,
        "createdAt": change.createdAt
    ]
}

func memoryDict(_ memory: MemoryItem) -> [String: Any] {
    [
        "id": memory.id,
        "scope": memory.scope.rawValue,
        "scopeId": optional(memory.scopeId),
        "kind": memory.kind.rawValue,
        "title": memory.title,
        "content": memory.content,
        "evidence": memory.evidence,
        "confidence": memory.confidence,
        "source": memory.source,
        "status": memory.status,
        "supersededBy": optional(memory.supersededBy),
        "createdAt": memory.createdAt,
        "updatedAt": memory.updatedAt,
        "lastUsedAt": optional(memory.lastUsedAt)
    ]
}

func reviewDict(_ review: ReviewRecord) -> [String: Any] {
    [
        "id": review.id,
        "positionId": optional(review.positionId),
        "kind": review.kind,
        "dueAt": optional(review.dueAt),
        "periodStart": optional(review.periodStart),
        "periodEnd": optional(review.periodEnd),
        "status": review.status,
        "facts": review.factsJSON,
        "notes": review.notes,
                "outcome": review.outcomeJSON,
        "completedAt": optional(review.completedAt),
        "createdAt": review.createdAt
    ]
}

func draftDict(_ draft: DraftRecord) -> [String: Any] {
    [
        "id": draft.id,
        "kind": draft.kind,
        "positionId": optional(draft.positionId),
        "skill": optional(draft.skill),
        "payload": draft.payload,
        "baseVersion": optional(draft.baseVersion),
        "baseQuantity": optional(draft.baseQuantity),
                "status": draft.status,
        "note": optional(draft.note),
        "createdAt": draft.createdAt,
        "decidedAt": optional(draft.decidedAt)
    ]
}


func metricDict(_ metric: PositionMetric) -> [String: Any] {
    [
        "id": metric.id,
        "positionId": metric.positionId,
        "key": metric.key,
        "label": metric.label,
        "value": metric.value,
        "source": metric.source,
        "asOf": metric.asOf,
        "note": optional(metric.note)
    ]
}

func alertDict(_ alert: Alert) -> [String: Any] {
    [
        "id": alert.id,
        "positionId": optional(alert.positionId),
        "kind": alert.kind.rawValue,
        "title": alert.title,
        "detail": alert.detail,
        "firstTriggeredAt": alert.firstTriggeredAt,
        "lastTriggeredAt": alert.lastTriggeredAt,
        "acknowledgedAt": optional(alert.acknowledgedAt),
        "resolvedAt": optional(alert.resolvedAt)
    ]
}

func notificationDict(_ notification: NotificationRecord) -> [String: Any] {
    [
        "id": notification.id,
        "alertId": optional(notification.alertId),
        "kind": notification.kind,
        "title": notification.title,
        "body": notification.body,
        "route": optional(notification.route),
        "createdAt": notification.createdAt,
        "readAt": optional(notification.readAt),
        "deliveredAt": optional(notification.deliveredAt),
        "delivery": notification.delivery
    ]
}

func accountDict(_ account: Account) -> [String: Any] {
    [
        "id": account.id,
        "broker": account.broker,
        "name": account.name,
        "accountNo": optional(account.accountNo),
        "currency": account.currency,
        "timezone": account.timezone,
        "isDefault": account.isDefault
    ]
}

func batchDict(_ batch: ImportBatch) -> [String: Any] {
    [
        "id": batch.id,
        "accountId": batch.accountId,
        "broker": batch.broker,
        "fileName": batch.fileName,
        "status": batch.status.rawValue,
        "rowsTotal": batch.rowsTotal,
        "rowsImported": batch.rowsImported,
        "rowsSkipped": batch.rowsSkipped,
        "rowsError": batch.rowsError,
        "error": optional(batch.error),
        "startedAt": batch.startedAt,
        "finishedAt": optional(batch.finishedAt)
    ]
}

func executionDict(_ execution: Execution) -> [String: Any] {
    [
        "id": execution.id,
        "accountId": execution.accountId,
        "batchId": optional(execution.batchId),
        "code": execution.code,
        "name": execution.name,
        "side": execution.side.rawValue,
        "quantity": execution.quantity,
        "price": execution.price,
        "amount": execution.amount,
        "feeTotal": execution.feeTotal,
        "currency": execution.currency,
        "tradeTime": execution.tradeTime,
        "status": execution.status,
        "dedupeKey": execution.dedupeKey,
        "changeId": optional(execution.changeId),
        "createdAt": execution.createdAt
    ]
}

func styleDict(_ metrics: StyleMetrics) -> [String: Any] {
    var dict = jsonable(metrics) as? [String: Any] ?? [:]
    dict["narrative"] = StyleEngine.narrative(metrics)
    return dict
}

// MARK: - Files

func loadLevels(path: String) throws -> [PlanLevel] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    if let levels = try? JSONDecoder().decode([PlanLevel].self, from: data) {
        return levels
    }
    struct Wrapper: Decodable { let levels: [PlanLevel] }
    if let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) {
        return wrapper.levels
    }
    throw CLIError.validation("levels 文件必须是数组或 {\"levels\": [...]}")
}

func loadPayload(path: String) throws -> String {
    let raw = try String(contentsOfFile: path, encoding: .utf8)
    guard let data = raw.data(using: .utf8),
          (try? JSONDecoder().decode(PlanDraftPayload.self, from: data)) != nil else {
        throw CLIError.validation("payload 文件不是有效的计划 JSON")
    }
    return raw
}

func readText(path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func loadJSON(path: String) throws -> Any {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONSerialization.jsonObject(with: data)
}

func loadMapping(path: String?) throws -> [String: String]? {
    guard let path else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
        throw CLIError.validation("mapping 文件必须是 {\"标准字段\":\"券商列名\"} 的 JSON 对象")
    }
    return mapping
}

// MARK: - Writes

func performWrite(
    args: CLIArgs,
    store: Store,
    command: String,
    preview: () throws -> [String: Any],
    body: () throws -> [String: Any]
) throws -> [String: Any] {
    if args.dryRun {
        var result = try preview()
        result["dry_run"] = true
        return result
    }

    let json = try store.writeIdempotentJSON(requestId: args.requestId, command: command) {
        let object = try body()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    if !args.noNotify {
        CarapaceNotify.post()
    }
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    var result = object as? [String: Any] ?? [:]
    result["dry_run"] = false
    return result
}

// MARK: - Misc

func parseChangeType(_ raw: String?) throws -> ChangeType? {
    guard let raw, !raw.isEmpty else { return nil }
    guard let type = ChangeType(rawValue: raw) else {
        throw CLIError.usage("未知流水类型：\(raw)")
    }
    return type
}

func positionByCode(_ code: String, store: Store) throws -> Position {
    if let holding = try store.openPosition(code: code) {
        return holding
    }
    if let watch = try store.watches().first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) {
        return watch
    }
    throw CLIError.notFound("没有找到 \(code) 的持仓或观察")
}

func quoteSource(for args: CLIArgs, market: InstrumentMarket) throws -> QuoteSource {
    if let raw = args.value("source"), let source = QuoteSource(rawValue: raw) {
        return source
    }
    switch market {
    case .cn: return .eastmoney
    case .hk: return .eastmoney
    case .us: return .eastmoney
    case .index: return .eastmoney
    }
}