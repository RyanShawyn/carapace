import Foundation

public enum DraftService {
    /// 把草稿里的计划档位写入计划。App 与 CLI 共用，避免两份逻辑漂移。
    @discardableResult
    public static func applyPlanDraft(
        _ draft: DraftRecord,
        store: Store,
        author: String = "agent"
    ) throws -> PlanUpdateResult {
        guard draft.kind == "plan", let positionId = draft.positionId else {
            throw StoreError.validation("草稿不是计划类型")
        }
        guard let data = draft.payload.data(using: .utf8) else {
            throw StoreError.validation("草稿内容不是有效 UTF-8")
        }
        let payload = try JSONDecoder().decode(PlanDraftPayload.self, from: data)
        let isWatch = try store.position(id: positionId)?.kind == .watch

        let levels = payload.levels.compactMap { item -> PlanLevel? in
            guard let kind = PlanLevel.Kind(rawValue: item.kind) else { return nil }
            return PlanLevel(price: item.price, kind: kind,
                             quantity: item.quantity, condition: item.condition)
        }.filter { !isWatch || $0.kind == .buy }

        guard !levels.isEmpty else {
            throw StoreError.validation("草稿没有有效档位")
        }

        let result = try store.updatePlan(
            positionId: positionId,
            levels: levels,
            description: payload.description,
            nextReview: payload.nextReview,
            note: "应用外部草稿",
            author: author,
            ifVersion: draft.baseVersion
        )
        try store.decideDraft(id: draft.id, status: "applied")
        return result
    }
}