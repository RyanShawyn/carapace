import Foundation

public struct PlanDraftPayload: Codable, Sendable {
    public var levels: [PlanDraftLevel]
    public var description: String?
    public var nextReview: String?

    public init(levels: [PlanDraftLevel], description: String? = nil, nextReview: String? = nil) {
        self.levels = levels
        self.description = description
        self.nextReview = nextReview
    }
}

public struct PlanDraftLevel: Codable, Sendable {
    public var kind: String
    public var price: Double
    public var quantity: Double?
    public var condition: String

    public init(kind: String, price: Double, quantity: Double? = nil, condition: String = "") {
        self.kind = kind
        self.price = price
        self.quantity = quantity
        self.condition = condition
    }
}