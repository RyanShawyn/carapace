import Foundation

public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case quote, hit, watch, review, risk
}

public struct Alert: Identifiable, Equatable, Sendable {
    public var id: String
    public var positionId: Int64?
    public var kind: AlertKind
    public var title: String
    public var detail: String
    public var firstTriggeredAt: String
    public var lastTriggeredAt: String
    public var acknowledgedAt: String?
    public var resolvedAt: String?

    public var isAcknowledged: Bool { acknowledgedAt != nil }
    public var glyph: String {
        switch kind {
        case .quote: return "turtle.error"
        case .hit: return "turtle.trigger"
        case .watch: return "turtle.watch"
        case .review: return "turtle.review"
        case .risk: return "turtle.error"
        }
    }
}

public struct AlertSignal: Equatable, Sendable {
    public var id: String
    public var positionId: Int64?
    public var kind: AlertKind
    public var title: String
    public var detail: String

    public init(id: String, positionId: Int64? = nil, kind: AlertKind,
                title: String, detail: String = "") {
        self.id = id
        self.positionId = positionId
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public enum AlertEngine {
    public static func crossed(previous: Quote?, current: Quote?, level: PlanLevel) -> Bool {
        guard let current, current.price > 0 else { return false }
        guard let previous, previous.price > 0 else {
            switch level.kind {
            case .buy: return current.price <= level.price
            case .sell, .stop: return current.price >= level.price
            }
        }
        switch level.kind {
        case .buy:
            return previous.price > level.price && current.price <= level.price
        case .sell, .stop:
            return previous.price < level.price && current.price >= level.price
        }
    }
}
