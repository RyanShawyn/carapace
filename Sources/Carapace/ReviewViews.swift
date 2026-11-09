import SwiftUI
import CarapaceCore

struct ReviewsView: View {
    @ObservedObject var state: AppState
    @State private var showAddMemory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("复盘", subtitle: "复盘、记忆与风格") {
                    HStack(spacing: 7) {
                        Button("新增记忆") { showAddMemory = true }.controlSize(.small)
                    }
                }
                Picker("", selection: $state.reviewTab) {
                    ForEach(ReviewTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 260).padding(.bottom, 12)

                switch state.reviewTab {
                case .reviews: reviews
                case .memory: memory
                case .style: style
                }
            }
            .padding(20)
        }
        .background(Theme.panel)
        .sheet(isPresented: $showAddMemory) {
            AddMemoryView(state: state, isPresented: $showAddMemory)
        }
    }

    private var reviews: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                if state.reviewRecords.isEmpty {
                    EmptyState(icon: "arrow.triangle.2.circlepath", title: "还没有复盘",
                               detail: "计划到期、档位执行或清仓时会生成复盘。")
                } else {
                    ForEach(state.reviewRecords) { review in
                        Button {
                            state.selectedReviewId = review.id
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(positionName(review.positionId))
                                        .font(.system(size: 12, weight: .semibold))
                                    Pill(text: review.status == "done" ? "已完成" : "待复盘",
                                         color: review.status == "done" ? Theme.down : Theme.amber)
                                    Spacer()
                                }
                                Text(review.kind == "exit" ? "清仓复盘" : review.kind == "weekly" ? "周报" : "计划复盘")
                                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
                                if let due = review.dueAt {
                                    Text("到期 \(due)").font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(state.selectedReviewId == review.id ? Theme.accentSoft : Color.clear)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(width: 250)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))

            if let review = state.reviewRecords.first(where: { $0.id == state.selectedReviewId })
                ?? state.reviewRecords.first {
                ReviewDetailView(state: state, review: review)
            } else {
                EmptyState(icon: "text.book.closed", title: "选择一条复盘",
                           detail: "左侧列出待复盘和已完成的记录。")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var memory: some View {
        Group {
            if state.memories.isEmpty {
                EmptyState(icon: "brain.head.profile", title: "还没有记忆",
                           detail: "复盘时把有效的判断记下来；外部 Agent 引用记忆时会标注编号。",
                           actionTitle: "新增记忆") { showAddMemory = true }
            } else {
                memoryGrid
            }
        }
    }

    private var memoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(state.memories) { m in
                Button {
                    state.activeSheet = .memory(m.id)
                } label: {
                    CardBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Pill(text: memoryKind(m.kind), color: memoryColor(m.kind))
                                Text(scopeText(m)).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                                Spacer()
                            }
                            Text(m.title).font(.system(size: 12.5, weight: .semibold))
                            Text(m.content).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                .lineLimit(3)
                            Text("置信度 \(Int(m.confidence * 100))% · 使用 \(m.updatedAt.prefix(10))")
                                .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var style: some View {
        let m = state.styleMetrics()
        return VStack(alignment: .leading, spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("我的投资风格").font(.system(size: 13.5, weight: .semibold))
                        Pill(text: "体系 v1", color: Theme.accent)
                        Spacer()
                        Button("更新快照") { state.saveStyleSnapshot() }
                            .controlSize(.small)
                    }
                    Text(StyleEngine.narrative(m)).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        StatCard(label: "持有周期", value: "\(Int(m.holdingDays.rounded())) 天", detail: "平均")
                        StatCard(label: "集中度", value: pct(m.concentration * 100), detail: "前三大")
                        StatCard(label: "计划执行", value: pct(m.planRate * 100), detail: "按档位")
                        StatCard(label: "计划外", value: pct(m.offPlanRate * 100), detail: "成交占比")
                        StatCard(label: "复盘完成", value: pct(m.reviewRate * 100), detail: "已完成")
                        StatCard(label: "模式", value: m.pattern, detail: "自动归类")
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                cardList("体系 · 原则", state.memories.filter { $0.kind == .principle || $0.kind == .preference })
                cardList("最近教训", state.memories.filter { $0.kind == .lesson })
                cardList("待验证", state.memories.filter { $0.kind == .hypothesis })
            }
        }
    }

    private func cardList(_ title: String, _ list: [MemoryItem]) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if list.isEmpty {
                    Text("还没有记录").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                ForEach(list) { m in
                    Button { state.activeSheet = .memory(m.id) } label: {
                        HStack {
                            Text(m.title).font(.system(size: 11))
                            Spacer()
                            Text("\(Int(m.confidence * 100))%").font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func positionName(_ id: Int64?) -> String {
        guard let id else { return "组合" }
        return state.anyPosition(id: id)?.name ?? "#\(id)"
    }

    private func memoryKind(_ kind: MemoryKind) -> String {
        switch kind {
        case .principle: return "原则"
        case .preference: return "偏好"
        case .pattern: return "模式"
        case .lesson: return "教训"
        case .fact: return "事实"
        case .hypothesis: return "待验证"
        }
    }

    private func memoryColor(_ kind: MemoryKind) -> Color {
        switch kind {
        case .principle, .preference: return Theme.accent
        case .lesson: return Theme.amber
        case .hypothesis: return Theme.muted
        default: return Theme.faint
        }
    }

    private func scopeText(_ m: MemoryItem) -> String {
        switch m.scope {
        case .global: return "全局"
        case .profile: return "历史分组"
        case .instrument: return m.scopeId ?? "标的"
        case .position: return "持仓 #\(m.scopeId ?? "")"
        }
    }
}

struct ReviewDetailView: View {
    @ObservedObject var state: AppState
    let review: ReviewRecord
    @State private var notes = ""
    @State private var errorMessage = ""

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(review.kind == "exit" ? "清仓复盘" : review.kind == "weekly" ? "周报" : "计划复盘")
                        .font(.system(size: 14, weight: .semibold))
                    Pill(text: review.status == "done" ? "已完成" : "待复盘",
                         color: review.status == "done" ? Theme.down : Theme.amber)
                    Spacer()
                    if review.status != "done" {
                        Text("在 Claude Code 里说「整理这条复盘」即可让外部 Agent 帮你起草。")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                }
                if let due = review.dueAt {
                    Text("到期 \(due)").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                facts
                if !review.outcomeJSON.isEmpty, review.outcomeJSON != "[]" {
                    Text("结果归因").font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                    outcome
                }
                Text("我的判断").font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                TextEditor(text: $notes)
                    .font(.system(size: 11.5))
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                }
                HStack {
                    Button("保存") {
                        do {
                            try state.saveReview(review, notes: notes, complete: false)
                            state.toastText = "复盘已保存"
                        } catch { errorMessage = error.localizedDescription }
                    }.controlSize(.small)
                    Button("完成复盘") {
                        do {
                            try state.saveReview(review, notes: notes, complete: true)
                            state.toastText = "复盘已完成"
                        } catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                }
            }
        }
        .onAppear { notes = review.notes }
        .onChange(of: review.id) { _ in notes = review.notes }
    }

    private var facts: some View {
        let items = decodePairs(review.factsJSON)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.0).font(.system(size: 9.5)).foregroundStyle(Theme.muted)
                    Text(pair.1).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.line.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var outcome: some View {
        let items = decodePairs(review.outcomeJSON)
        return VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.0).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(pair.1).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                }
            }
        }
    }

    private var positionName: String {
        guard let id = review.positionId else { return "组合" }
        return state.anyPosition(id: id)?.name ?? "#\(id)"
    }

    private func decodePairs(_ json: String) -> [(String, String)] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let rows = object as? [[String]] {
            return rows.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
        }
        if let dict = object as? [String: Any] {
            return dict.map { ($0.key, String(describing: $0.value)) }.sorted { $0.0 < $1.0 }
        }
        return []
    }
}

struct AddMemoryView: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @State private var scope: MemoryScope = .global
    @State private var kind: MemoryKind = .principle
    @State private var title = ""
    @State private var content = ""
    @State private var confidence = 0.8
    @State private var scopeId = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新增记忆").font(.system(size: 15, weight: .semibold))
            Picker("范围", selection: $scope) {
                Text("全局").tag(MemoryScope.global)
                Text("标的").tag(MemoryScope.instrument)
                Text("持仓").tag(MemoryScope.position)
            }
            if scope == .instrument {
                TextField("标的代码，如 600000", text: $scopeId)
                    .textFieldStyle(.roundedBorder)
            } else if scope == .position {
                Picker("持仓", selection: $scopeId) {
                    Text("选择持仓").tag("")
                    ForEach(state.rows) { row in
                        Text(row.position.name).tag(String(row.id))
                    }
                }
            }
            Picker("类型", selection: $kind) {
                Text("原则").tag(MemoryKind.principle)
                Text("偏好").tag(MemoryKind.preference)
                Text("模式").tag(MemoryKind.pattern)
                Text("教训").tag(MemoryKind.lesson)
                Text("事实").tag(MemoryKind.fact)
                Text("待验证").tag(MemoryKind.hypothesis)
            }
            TextField("标题", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $content).frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
            HStack {
                Text("置信度 \(Int(confidence * 100))%")
                Slider(value: $confidence, in: 0.1...1.0)
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
            }
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("保存") {
                    do {
                        try state.addMemory(scope: scope,
                                            scopeId: scope == .global ? nil : scopeId,
                                            kind: kind, title: title, content: content,
                                            confidence: confidence)
                        isPresented = false
                    } catch {
                        self.error = error.localizedDescription
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || (scope != .global && scopeId.isEmpty))
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
