import Foundation
import CarapaceCore

@MainActor
extension AppState {
    func ensureDueReviews(force: Bool = false) {
        guard autoReview else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastReviewSweep) >= 60 else { return }
        lastReviewSweep = now
        let all = allPositions(includeClosed: true)
        for p in all where p.kind == .holding {
            let plan = try? store.plan(positionId: p.id)
            if p.status == .closed {
                let exists = reviewRecords.contains { $0.positionId == p.id && $0.kind == "exit" }
                if !exists {
                    _ = try? store.createReview(positionId: p.id, kind: "exit",
                                                dueAt: p.closedAt ?? Dates.today(),
                                                profileId: nil,
                                                factsJSON: reviewFacts(for: p))
                }
            } else if let due = plan?.nextReview, let date = Dates.parse(due), date <= Date() {
                let exists = reviewRecords.contains {
                    $0.positionId == p.id && $0.kind == "plan" && $0.dueAt == due
                }
                if !exists {
                    _ = try? store.createReview(positionId: p.id, kind: "plan",
                                                dueAt: due, profileId: nil,
                                                factsJSON: reviewFacts(for: p))
                }
            }
        }
        reviewRecords = (try? store.reviews(includeDone: true, limit: 500)) ?? []
    }

    func loadV5() {
        memories = (try? store.memories(status: "active", limit: 500)) ?? []
        reviewRecords = (try? store.reviews(includeDone: true, limit: 500)) ?? []
        drafts = (try? store.drafts(status: nil, limit: 200)) ?? []
        notifications = (try? store.notifications(limit: 200)) ?? []
        recentChanges = (try? store.allChanges(limit: 500)) ?? []
        importBatches = (try? store.importBatches(limit: 20)) ?? []
        if selectedPositionId == nil {
            selectedPositionId = rows.first?.id ?? allPositions().first?.id
        } else if let id = selectedPositionId, position(id: id) == nil {
            selectedPositionId = rows.first?.id ?? allPositions().first?.id
        }
        if selectedReviewId == nil {
            selectedReviewId = reviewRecords.first { $0.status != "done" }?.id ?? reviewRecords.first?.id
        }
        notifyPendingDrafts()
        ensureDueReviews()
    }

    private func notifyPendingDrafts() {
        guard CarapaceDefaults.notifyEnabled(.draft) else {
            notifications = (try? store.notifications(limit: 200)) ?? notifications
            return
        }
        for draft in drafts where draft.status == "pending" {
            let alertId = "draft:\(draft.id)"
            // 读过就不再反复提醒；草稿被重新生成时会换成新的 id。
            guard (try? store.hasNotification(alertId: alertId)) == false else { continue }
            let name = draft.positionId.flatMap { anyPosition(id: $0)?.name } ?? "组合"
            try? store.addNotificationIfNeeded(
                alertId: alertId, kind: "draft",
                title: "计划草稿待确认",
                body: "\(name) · 基准 v\(draft.baseVersion ?? 0)",
                route: draft.positionId.map { "position:\($0)" })
        }
        notifications = (try? store.notifications(limit: 200)) ?? notifications
    }

    func metrics(for positionId: Int64) -> [PositionMetric] {
        (try? store.metrics(positionId: positionId)) ?? []
    }

    var dueReviews: [ReviewRecord] { reviewRecords.filter { $0.status != "done" } }
    var unreadNotifications: Int { notifications.filter { $0.readAt == nil }.count }
    var pendingDrafts: [DraftRecord] { drafts.filter { $0.status == "pending" } }

    func selectPosition(_ id: Int64, tab: PositionTab = .plan) {
        selectedPositionId = id
        positionTab = tab
        showPositionDetail = true
        section = .positions
    }

    func executedLevels(for positionId: Int64) -> Set<String> {
        (try? store.executedLevelPrices(positionId: positionId)) ?? []
    }

    func anyPosition(id: Int64) -> Position? {
        position(id: id) ?? allPositions().first { $0.id == id }
    }

    func styleMetrics() -> StyleMetrics {
        if let styleCache { return styleCache }
        let metrics = (try? StyleEngine.compute(store: store, hkdRate: hkdRate)) ?? StyleMetrics(
            holdingDays: 0, concentration: 0, planRate: 0, offPlanRate: 0,
            reviewRate: 0, pattern: "样本不足", best: "—", worst: "—")
        styleCache = metrics
        return metrics
    }

    func saveStyleSnapshot() {
        let metrics = styleMetrics()
        do {
            _ = try store.saveStyleSnapshot(metrics, narrative: StyleEngine.narrative(metrics))
            toastText = "风格快照已保存"
        } catch {
            toastText = error.localizedDescription
        }
    }

    func applyPlanDraft(_ draft: DraftRecord) {
        do {
            _ = try DraftService.applyPlanDraft(draft, store: store)
            load()
            toastText = "计划草稿已应用"
        } catch {
            toastText = error.localizedDescription
        }
    }

    func discardDraft(_ draft: DraftRecord) throws {
        try store.decideDraft(id: draft.id, status: "discarded")
        drafts = (try? store.drafts(status: nil, limit: 200)) ?? []
    }

    func addMemory(scope: MemoryScope, scopeId: String?, kind: MemoryKind,
                   title: String, content: String, confidence: Double = 0.8) throws {
        _ = try store.addMemory(scope: scope, scopeId: scopeId, kind: kind,
                                title: title, content: content, evidence: "用户手动添加",
                                confidence: confidence, source: "user")
        memories = (try? store.memories(status: "active", limit: 500)) ?? []
    }

    func saveReview(_ review: ReviewRecord, notes: String, complete: Bool) throws {
        try store.saveReview(id: review.id, notes: notes, complete: complete)
        reviewRecords = (try? store.reviews(includeDone: true, limit: 500)) ?? []
    }

    private func reviewFacts(for p: Position) -> String {
        (try? ReviewService.facts(store: store, position: p, quotes: quotes)) ?? "[]"
    }

    func previewImport(url: URL, mapping: [String: String]? = nil) {
        importLoading = true
        importFileName = url.lastPathComponent
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                guard let account = try self.store.defaultAccount() else {
                    throw ImportError.commit("没有默认账户")
                }
                let store = self.store
                let accountId = account.id
                let preview = try await Task.detached {
                    try ImportService.preview(data: data, accountId: accountId,
                                              store: store, mapping: mapping,
                                              allowMissing: true)
                }.value
                self.importPreview = preview
                self.importError = ImportService.missingRequired(preview.mapping).isEmpty
                    ? nil : "请先完成必填字段映射"
            } catch {
                self.importPreview = nil
                self.importError = error.localizedDescription
            }
            self.importLoading = false
        }
    }

    func commitImport(includeNeedsReview: Bool = false) {
        guard let preview = importPreview, let account = try? store.defaultAccount() else { return }
        do {
            let result = try ImportService.commit(
                preview: preview, accountId: account.id,
                broker: "导入", fileName: importFileName ?? "import.csv", store: store,
                includeNeedsReview: includeNeedsReview)
            lastImport = result.batch
            importPreview = nil
            showImport = false
            load()
            toastText = "导入 \(result.imported) 笔 · 跳过 \(result.skipped) · 待确认 \(result.needsReview) · 错误 \(result.errors)"
        } catch {
            importError = error.localizedDescription
        }
    }

    func rollbackImport(_ batch: ImportBatch) {
        do {
            _ = try ImportService.rollback(batchId: batch.id, store: store)
            load()
            toastText = "已回滚批次"
        } catch {
            toastText = error.localizedDescription
        }
    }

    func openNotification(_ notification: NotificationRecord) {
        try? store.markNotificationRead(id: notification.id)
        notifPanelOpen = false
        if let route = notification.route { openRoute(route) }
        loadV5()
    }

    private func openRoute(_ route: String) {
        if route.hasPrefix("position:"), let id = Int64(route.dropFirst("position:".count)) {
            selectPosition(id)
        } else if route == "reviews" {
            section = .reviews
        } else if route == "settings" {
            section = .settings
        } else {
            section = .overview
        }
    }

    }