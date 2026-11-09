import Foundation

// MARK: - Analysis profiles

public struct ProfileQuestion: Codable, Equatable, Sendable {
    public var label: String
    public var placeholder: String
    public var required: Bool

    public init(label: String, placeholder: String = "", required: Bool = false) {
        self.label = label
        self.placeholder = placeholder
        self.required = required
    }
}

public struct MetricDefinition: Codable, Equatable, Identifiable, Sendable {
    public var key: String
    public var label: String
    public var source: String       // auto | manual | import
    public var unit: String?

    public var id: String { key }

    public init(key: String, label: String, source: String = "manual", unit: String? = nil) {
        self.key = key
        self.label = label
        self.source = source
        self.unit = unit
    }
}

public struct PlanTemplateLevel: Codable, Equatable, Sendable {
    public var kind: PlanLevel.Kind
    public var price: Double
    public var quantity: Double?
    public var condition: String

    public init(kind: PlanLevel.Kind, price: Double, quantity: Double?, condition: String) {
        self.kind = kind
        self.price = price
        self.quantity = quantity
        self.condition = condition
    }
}

public struct InstrumentProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var assetClass: String
    public var summary: String
    public var questions: [ProfileQuestion]
    public var metrics: [MetricDefinition]
    public var planTemplate: [PlanTemplateLevel]
    public var reviewQuestions: [String]
    public var riskRules: String
    public var prompt: String
    public var builtIn: Bool
    public var enabled: Bool
    public var version: Int
    public var updatedAt: String

    public init(id: String, name: String, assetClass: String, summary: String,
                questions: [ProfileQuestion], metrics: [MetricDefinition],
                planTemplate: [PlanTemplateLevel], reviewQuestions: [String],
                riskRules: String, prompt: String, builtIn: Bool = true,
                enabled: Bool = true, version: Int = 1,
                updatedAt: String = Dates.now()) {
        self.id = id
        self.name = name
        self.assetClass = assetClass
        self.summary = summary
        self.questions = questions
        self.metrics = metrics
        self.planTemplate = planTemplate
        self.reviewQuestions = reviewQuestions
        self.riskRules = riskRules
        self.prompt = prompt
        self.builtIn = builtIn
        self.enabled = enabled
        self.version = version
        self.updatedAt = updatedAt
    }
}

public struct PositionMetric: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var positionId: Int64
    public var key: String
    public var label: String
    public var value: String
    public var source: String
    public var asOf: String
    public var note: String?

    public init(id: Int64, positionId: Int64, key: String, label: String,
                value: String, source: String, asOf: String, note: String? = nil) {
        self.id = id
        self.positionId = positionId
        self.key = key
        self.label = label
        self.value = value
        self.source = source
        self.asOf = asOf
        self.note = note
    }
}

// MARK: - Accounts and imports

public struct Account: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var broker: String
    public var name: String
    public var accountNo: String?
    public var currency: String
    public var timezone: String
    public var isDefault: Bool

    public init(id: Int64, broker: String, name: String, accountNo: String? = nil,
                currency: String = "CNY", timezone: String = "Asia/Shanghai",
                isDefault: Bool = false) {
        self.id = id
        self.broker = broker
        self.name = name
        self.accountNo = accountNo
        self.currency = currency
        self.timezone = timezone
        self.isDefault = isDefault
    }
}

public struct ImportMapping: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var broker: String
    public var name: String
    public var version: Int
    /// 标准字段 -> 券商列名
    public var fields: [String: String]
    public var createdAt: String
    public var updatedAt: String

    public init(id: Int64, broker: String, name: String, version: Int = 1,
                fields: [String: String], createdAt: String, updatedAt: String) {
        self.id = id
        self.broker = broker
        self.name = name
        self.version = version
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ImportBatchStatus: String, Codable, Sendable {
    case preview, committed, voided, failed
}

public struct ImportBatch: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var accountId: Int64
    public var broker: String
    public var fileName: String
    public var fileHash: String
    public var mappingId: Int64?
    public var status: ImportBatchStatus
    public var rowsTotal: Int
    public var rowsImported: Int
    public var rowsSkipped: Int
    public var rowsError: Int
    public var error: String?
    public var startedAt: String
    public var finishedAt: String?

    public init(id: Int64, accountId: Int64, broker: String, fileName: String,
                fileHash: String, mappingId: Int64?, status: ImportBatchStatus,
                rowsTotal: Int, rowsImported: Int, rowsSkipped: Int, rowsError: Int,
                error: String? = nil, startedAt: String, finishedAt: String? = nil) {
        self.id = id
        self.accountId = accountId
        self.broker = broker
        self.fileName = fileName
        self.fileHash = fileHash
        self.mappingId = mappingId
        self.status = status
        self.rowsTotal = rowsTotal
        self.rowsImported = rowsImported
        self.rowsSkipped = rowsSkipped
        self.rowsError = rowsError
        self.error = error
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct Execution: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var accountId: Int64
    public var batchId: Int64?
    public var brokerTradeId: String?
    public var orderId: String?
    public var code: String
    public var name: String
    public var side: TradeSide
    public var quantity: Double
    public var price: Double
    public var amount: Double
    public var feeCommission: Double
    public var feeStamp: Double
    public var feeTransfer: Double
    public var feeOther: Double
    public var feeTotal: Double
    public var currency: String
    public var tradeTime: String
    public var settleDate: String?
    public var source: String
    public var dedupeKey: String
    public var changeId: Int64?
    public var status: String
    public var voidedAt: String?
    public var createdAt: String

    public init(id: Int64 = 0, accountId: Int64, batchId: Int64? = nil,
                brokerTradeId: String? = nil, orderId: String? = nil,
                code: String, name: String = "", side: TradeSide,
                quantity: Double, price: Double, amount: Double = 0,
                feeCommission: Double = 0, feeStamp: Double = 0,
                feeTransfer: Double = 0, feeOther: Double = 0,
                feeTotal: Double = 0, currency: String = "CNY",
                tradeTime: String, settleDate: String? = nil,
                source: String = "import", dedupeKey: String = "",
                changeId: Int64? = nil, status: String = "active",
                voidedAt: String? = nil, createdAt: String = Dates.now()) {
        self.id = id
        self.accountId = accountId
        self.batchId = batchId
        self.brokerTradeId = brokerTradeId
        self.orderId = orderId
        self.code = code
        self.name = name
        self.side = side
        self.quantity = quantity
        self.price = price
        self.amount = amount == 0 ? quantity * price : amount
        self.feeCommission = feeCommission
        self.feeStamp = feeStamp
        self.feeTransfer = feeTransfer
        self.feeOther = feeOther
        self.feeTotal = feeTotal == 0 ? feeCommission + feeStamp + feeTransfer + feeOther : feeTotal
        self.currency = currency
        self.tradeTime = tradeTime
        self.settleDate = settleDate
        self.source = source
        self.dedupeKey = dedupeKey
        self.changeId = changeId
        self.status = status
        self.voidedAt = voidedAt
        self.createdAt = createdAt
    }
}

public enum ImportRowStatus: String, Codable, Sendable {
    case ready, duplicate, needsReview, error
}

public struct ImportPreviewRow: Identifiable, Equatable, Sendable {
    public var id: Int { rowNumber }
    public var rowNumber: Int
    public var tradeTime: String
    public var code: String
    public var name: String
    public var side: TradeSide
    public var quantity: Double
    public var price: Double
    public var amount: Double
    public var feeTotal: Double
    public var currency: String
    public var brokerTradeId: String?
    public var dedupeKey: String
    public var status: ImportRowStatus
    public var message: String
    public var raw: [String: String]

    public init(rowNumber: Int, tradeTime: String, code: String, name: String = "",
                side: TradeSide, quantity: Double, price: Double, amount: Double = 0,
                feeTotal: Double = 0, currency: String = "CNY",
                brokerTradeId: String? = nil, dedupeKey: String = "",
                status: ImportRowStatus = .ready, message: String = "",
                raw: [String: String] = [:]) {
        self.rowNumber = rowNumber
        self.tradeTime = tradeTime
        self.code = code
        self.name = name
        self.side = side
        self.quantity = quantity
        self.price = price
        self.amount = amount == 0 ? quantity * price : amount
        self.feeTotal = feeTotal
        self.currency = currency
        self.brokerTradeId = brokerTradeId
        self.dedupeKey = dedupeKey
        self.status = status
        self.message = message
        self.raw = raw
    }
}

public struct ImportResult: Sendable {
    public var batch: ImportBatch
    public var imported: Int
    public var skipped: Int
    public var needsReview: Int
    public var errors: Int

    public init(batch: ImportBatch, imported: Int, skipped: Int,
                needsReview: Int, errors: Int) {
        self.batch = batch
        self.imported = imported
        self.skipped = skipped
        self.needsReview = needsReview
        self.errors = errors
    }
}

// MARK: - Memory and style

public enum MemoryScope: String, Codable, CaseIterable, Sendable {
    case global, profile, instrument, position
}

public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case principle, preference, pattern, lesson, fact, hypothesis
}

public struct MemoryItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var scope: MemoryScope
    public var scopeId: String?
    public var kind: MemoryKind
    public var title: String
    public var content: String
    public var evidence: String
    public var confidence: Double
    public var source: String
    public var status: String
    public var supersededBy: Int64?
    public var createdAt: String
    public var updatedAt: String
    public var lastUsedAt: String?

    public init(id: Int64, scope: MemoryScope, scopeId: String? = nil,
                kind: MemoryKind, title: String, content: String,
                evidence: String = "", confidence: Double = 0.5,
                source: String = "user", status: String = "active",
                supersededBy: Int64? = nil, createdAt: String,
                updatedAt: String, lastUsedAt: String? = nil) {
        self.id = id
        self.scope = scope
        self.scopeId = scopeId
        self.kind = kind
        self.title = title
        self.content = content
        self.evidence = evidence
        self.confidence = confidence
        self.source = source
        self.status = status
        self.supersededBy = supersededBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct MemoryProposal: Identifiable, Equatable, Sendable {
    public var id: String
    public var scope: MemoryScope
    public var scopeId: String?
    public var kind: MemoryKind
    public var title: String
    public var content: String
    public var evidence: String
    public var confidence: Double
    public var supersedes: Int64?

    public init(id: String = UUID().uuidString, scope: MemoryScope,
                scopeId: String? = nil, kind: MemoryKind, title: String,
                content: String, evidence: String = "", confidence: Double = 0.5,
                supersedes: Int64? = nil) {
        self.id = id
        self.scope = scope
        self.scopeId = scopeId
        self.kind = kind
        self.title = title
        self.content = content
        self.evidence = evidence
        self.confidence = confidence
        self.supersedes = supersedes
    }
}

public struct StyleMetrics: Codable, Equatable, Sendable {
    public var holdingDays: Double
    public var concentration: Double
    public var planRate: Double
    public var offPlanRate: Double
    public var reviewRate: Double
    public var pattern: String
    public var best: String
    public var worst: String

    public init(holdingDays: Double, concentration: Double, planRate: Double,
                offPlanRate: Double, reviewRate: Double, pattern: String,
                best: String, worst: String) {
        self.holdingDays = holdingDays
        self.concentration = concentration
        self.planRate = planRate
        self.offPlanRate = offPlanRate
        self.reviewRate = reviewRate
        self.pattern = pattern
        self.best = best
        self.worst = worst
    }
}

public struct StyleSnapshot: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var asOf: String
    public var metrics: StyleMetrics
    public var narrative: String

    public init(id: Int64, asOf: String, metrics: StyleMetrics, narrative: String) {
        self.id = id
        self.asOf = asOf
        self.metrics = metrics
        self.narrative = narrative
    }
}

// MARK: - Reviews, drafts, notifications

public struct ReviewRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var positionId: Int64?
    public var kind: String
    public var dueAt: String?
    public var periodStart: String?
    public var periodEnd: String?
    public var status: String
    public var factsJSON: String
    public var notes: String
    public var profileId: String?
    public var outcomeJSON: String
    public var completedAt: String?
    public var createdAt: String

    public init(id: Int64, positionId: Int64?, kind: String, dueAt: String? = nil,
                periodStart: String? = nil, periodEnd: String? = nil,
                status: String = "due", factsJSON: String = "[]", notes: String = "",
                profileId: String? = nil,
                outcomeJSON: String = "[]",
                completedAt: String? = nil, createdAt: String) {
        self.id = id
        self.positionId = positionId
        self.kind = kind
        self.dueAt = dueAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.status = status
        self.factsJSON = factsJSON
        self.notes = notes
        self.profileId = profileId
        self.outcomeJSON = outcomeJSON
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

public struct DraftRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: String
    public var positionId: Int64?
    public var skill: String?
    public var payload: String
    public var baseVersion: Int?
    public var baseQuantity: Double?
    public var profileId: String?
    public var status: String
    public var note: String?
    public var createdAt: String
    public var decidedAt: String?

    public init(id: Int64, kind: String, positionId: Int64? = nil,
                skill: String? = nil, payload: String,
                baseVersion: Int? = nil, baseQuantity: Double? = nil,
                profileId: String? = nil, status: String = "pending",
                note: String? = nil, createdAt: String, decidedAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.positionId = positionId
        self.skill = skill
        self.payload = payload
        self.baseVersion = baseVersion
        self.baseQuantity = baseQuantity
        self.profileId = profileId
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }
}

public struct NotificationRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var alertId: String?
    public var kind: String
    public var title: String
    public var body: String
    public var route: String?
    public var createdAt: String
    public var readAt: String?
    public var deliveredAt: String?
    public var delivery: String

    public init(id: Int64, alertId: String? = nil, kind: String,
                title: String, body: String = "", route: String? = nil,
                createdAt: String, readAt: String? = nil,
                deliveredAt: String? = nil, delivery: String = "inapp") {
        self.id = id
        self.alertId = alertId
        self.kind = kind
        self.title = title
        self.body = body
        self.route = route
        self.createdAt = createdAt
        self.readAt = readAt
        self.deliveredAt = deliveredAt
        self.delivery = delivery
    }
}

// MARK: - Small shared helpers

public struct ImportSummary: Sendable {
    public var total: Int
    public var ready: Int
    public var duplicate: Int
    public var needsReview: Int
    public var errors: Int

    public init(total: Int, ready: Int, duplicate: Int, needsReview: Int, errors: Int) {
        self.total = total
        self.ready = ready
        self.duplicate = duplicate
        self.needsReview = needsReview
        self.errors = errors
    }
}

public struct RiskReport: Sendable {
    public var totalValue: Double
    public var totalCost: Double
    public var positionWeight: [Int64: Double]
    public var top3Weight: Double
    public var stopRisk: Double
    public var overLimit: [Int64]
    public var notes: [String]

    public init(totalValue: Double, totalCost: Double,
                positionWeight: [Int64: Double], top3Weight: Double,
                stopRisk: Double, overLimit: [Int64], notes: [String]) {
        self.totalValue = totalValue
        self.totalCost = totalCost
        self.positionWeight = positionWeight
        self.top3Weight = top3Weight
        self.stopRisk = stopRisk
        self.overLimit = overLimit
        self.notes = notes
    }
}
