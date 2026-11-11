import SwiftUI
import CarapaceCore

struct OverviewView: View {
    @ObservedObject var state: AppState

    private var subtitle: String {
        if let e = state.quoteError, !e.isEmpty { return "行情异常 · \(e)" }
        let time = state.lastUpdated.map {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.timeZone = MarketHours.zone
            return f.string(from: $0)
        } ?? "—"
        return "行情 \(time) · 东方财富 / 新浪"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("总览", subtitle: subtitle) {
                    HStack(spacing: 7) {
                        Button("刷新") { state.refresh() }.controlSize(.small)
                        Button("新建持仓") { state.showIntake = true }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }

                HStack(spacing: 10) {
                    StatCard(label: "总市值", value: money(state.portfolio?.totalValue ?? 0),
                             detail: "成本 \(money(state.portfolio?.totalCost ?? 0))")
                    StatCard(label: "今日盈亏", value: state.portfolio?.todayPnl.map(signedMoney) ?? "—",
                             detail: state.portfolio?.todayPnl == nil ? "行情不完整" : "按现价计算",
                             tint: (state.portfolio?.todayPnl ?? 0) >= 0 ? Theme.up : Theme.down)
                    StatCard(label: "未实现盈亏", value: state.portfolio?.totalPnl.map(signedMoney) ?? "—",
                             detail: state.portfolio?.totalPnl == nil ? "行情不完整" : "按平均成本",
                             tint: (state.portfolio?.totalPnl ?? 0) >= 0 ? Theme.up : Theme.down)
                    StatCard(label: "仓位 / 风险", value: "\(state.rows.count) 只",
                             detail: "前三大 \(pct(top3Weight(state))) · 停止档 \(stopCoverage(state))")
                }

                HStack(alignment: .top, spacing: 12) {
                    attentionCard
                    weeklyCard
                }
                .padding(.top, 12)

                SectionTitle(title: "持仓", detail: "\(state.rows.count) 只 · 点击进入详情")
                if state.rows.isEmpty {
                    EmptyState(icon: "tray", title: "还没有持仓",
                               detail: "从代码开始，补数量、成本和计划。",
                               actionTitle: "新建第一笔") { state.showIntake = true }
                } else {
                    OverviewPositionTable(state: state)
                }
                if state.rows.contains(where: { $0.position.market == .hk }) {
                    Text("港股价格与盈亏按 HKD 显示；总市值、今日盈亏和仓位按港币汇率折算成 CNY。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .padding(.top, 6)
                }

                if !state.watchRows.isEmpty {
                    HStack(spacing: 8) {
                        SectionTitle(title: "观察标的",
                                     detail: "\(state.watchRows.count) 只 · 不参与组合")
                        Button("查看全部") {
                            state.section = .positions
                            state.holdTab = .watch
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.accent)
                    }
                    OverviewWatchTable(state: state)
                }

                CardBox {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: state.backgroundCheck ? "bolt.badge.automatic" : "bolt.slash")
                            .foregroundStyle(state.backgroundCheck ? Theme.accent : Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.backgroundCheck ? "后台行情已开启" : "后台行情已关闭")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("行情每 \(Int(state.backgroundMinutes)) 分钟检查一次；计划到期\(state.autoReview ? "自动" : "不自动")创建复盘。交割单导入与计划写入仍需手动确认。")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("设置") {
                            state.section = .settings
                            state.settingsTab = .automation
                        }.controlSize(.small)
                    }
                }
                .padding(.top, 12)
            }
            .padding(20)
        }
        .background(Theme.panel)
    }

    private var attentionCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("需要你处理").font(.system(size: 12.5, weight: .semibold))
                    Pill(text: "\(state.dueReviews.count + state.pendingDrafts.count)", color: Theme.amber)
                    Spacer()
                }
                if state.dueReviews.isEmpty && state.pendingDrafts.isEmpty && state.unreadNotifications == 0 {
                    Text("没有待处理事项").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                ForEach(state.dueReviews.prefix(3)) { review in
                    Button {
                        state.section = .reviews
                        state.selectedReviewId = review.id
                    } label: {
                        attentionRow("\(review.kind == "exit" ? "清仓复盘" : "计划复盘") · \(positionName(review.positionId))",
                                     detail: review.dueAt ?? "", tint: Theme.amber)
                    }.buttonStyle(.plain)
                }
                ForEach(state.pendingDrafts.prefix(2)) { draft in
                    Button {
                        state.section = .positions
                        state.activeSheet = .drafts
                    } label: {
                        attentionRow("草稿待确认", detail: draft.kind, tint: Theme.accent)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var weeklyCard: some View {
        let views = state.portfolio?.views ?? []
        let best = views.compactMap { v -> (String, Double)? in
            guard let p = v.totalPnl else { return nil }
            return (v.position.name, p * v.fxRate)
        }.max { $0.1 < $1.1 }
        let worst = views.compactMap { v -> (String, Double)? in
            guard let p = v.totalPnl else { return nil }
            return (v.position.name, p * v.fxRate)
        }.min { $0.1 < $1.1 }
        let weekStart = Dates.day.string(
            from: Calendar(identifier: .gregorian).date(byAdding: .day, value: -6, to: Date()) ?? Date())
        let changes = state.recentChanges.filter { $0.occurredAt >= weekStart }
        let trades = changes.filter { $0.type == .buy || $0.type == .sell || $0.type == .clear }
        let planned = trades.filter { $0.levelId != nil || $0.levelPrice != nil }
        return CardBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("近 7 天结果").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button("复盘") { state.section = .reviews }.buttonStyle(.plain)
                        .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
                resultLine("未实现盈亏", state.portfolio?.totalPnl.map(signedMoney) ?? "—")
                resultLine("今日盈亏", state.portfolio?.todayPnl.map(signedMoney) ?? "—")
                resultLine("当前贡献最大", best.map { "\($0.0) \(signedMoney($0.1))" } ?? "—")
                resultLine("当前拖累最大", worst.map { "\($0.0) \(signedMoney($0.1))" } ?? "—")
                resultLine("计划执行", "\(planned.count) / \(trades.count)")
                Text("成交统计来自最近 7 天流水；周/月归因在复盘页生成。")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    private func attentionRow(_ title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11.5))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
    }

    private func resultLine(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
        }
    }

    private func positionName(_ id: Int64?) -> String {
        guard let id else { return "组合" }
        return state.anyPosition(id: id)?.name ?? "#\(id)"
    }

}

struct PositionsView: View {
    @ObservedObject var state: AppState
    @State private var confirmRemoveWatch = false
    @State private var removingWatchId: Int64?

    var body: some View {
        if state.showPositionDetail, let id = state.selectedPositionId {
            PositionDetailView(state: state, positionId: id)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader("持仓", subtitle: "持仓、计划与流水") {
                        HStack(spacing: 7) {
                            Button("导入交割单") { state.showImport = true }.controlSize(.small)
                            Button("新建持仓") { state.showIntake = true }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                    Picker("", selection: $state.holdTab) {
                        ForEach(HoldTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .padding(.bottom, 12)

                    switch state.holdTab {
                    case .positions: holdings
                    case .watch: watchList
                    case .plans: plans
                    case .ledger: ledger
                    }
                }
                .padding(20)
            }
            .background(Theme.panel)
        }
    }

    private var holdings: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.rows.isEmpty {
                EmptyState(icon: "tray", title: "还没有持仓", detail: "新建第一笔持仓后，这里会显示仓位、成本和下一档。",
                           actionTitle: "新建持仓") { state.showIntake = true }
            } else {
                OverviewPositionTable(state: state)
                if state.rows.contains(where: { $0.position.market == .hk }) {
                    Text("港股价格与盈亏按 HKD 显示；组合合计按港币汇率折算成 CNY。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .padding(.top, 6)
                }
            }
            SectionTitle(title: "组合风险", detail: "按你设置的上限计算")
            HStack(spacing: 12) {
                CardBox {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("集中度").font(.system(size: 12, weight: .semibold))
                        Text("前三大 \(pct(top3Weight(state)))").font(.system(size: 18, weight: .semibold))
                        Text("单只上限 20%，超限会在通知里提示。").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                CardBox {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("停止档覆盖").font(.system(size: 12, weight: .semibold))
                        Text(stopCoverage(state)).font(.system(size: 18, weight: .semibold))
                        Text("停止档用于暂停加仓，不是止损；在计划里添加「停止买入」档。")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var watchList: some View {
        let rows = state.watchRows
        let hot = rows.filter(watchRowIsHot)
        let longest = rows.max { $0.position.heldDays < $1.position.heldDays }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                watchStat("观察标的", "\(rows.count) 只",
                          rows.isEmpty ? "还没有观察" : "全部不参与组合",
                          tint: rows.isEmpty ? Theme.muted : Theme.amber)
                watchStat("已到关注价", "\(hot.count) 只",
                          hot.first?.position.name ?? "暂无",
                          tint: hot.isEmpty ? Theme.muted : Theme.amber)
                watchStat("最长观察", longest.map { "\($0.position.heldDays) 天" } ?? "—",
                          longest?.position.name ?? "—")
            }

            if rows.isEmpty {
                EmptyState(icon: "eye", title: "还没有观察标的",
                           detail: "把想买但还没买的标的加进来，跌破关注价时菜单栏会提醒你。",
                           actionTitle: "添加观察") {
                    state.activeSheet = .watchEditor(nil)
                }
            } else {
                watchTable(rows)
                Text("观察标的不计入总市值与盈亏；买入或导入同代码成交后会自动转为持仓。")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
        }
        .alert("移除这个观察标的？", isPresented: $confirmRemoveWatch) {
            Button("取消", role: .cancel) { removingWatchId = nil }
            Button("移除", role: .destructive) {
                if let id = removingWatchId {
                    do {
                        try state.removeWatch(id: id)
                        state.toastText = "已移除观察"
                    } catch { state.toastText = error.localizedDescription }
                }
                removingWatchId = nil
            }
        } message: {
            Text("观察备注、计划和指标会一起删除，已记录的复盘会保留。")
        }
    }

    private func watchStat(_ title: String, _ value: String, _ detail: String,
                           tint: Color = .primary) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func watchTable(_ rows: [PanelRow]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("名称").frame(width: 196, alignment: .leading)
                Text("现价").frame(width: 68, alignment: .trailing)
                Text("涨跌").frame(width: 62, alignment: .trailing)
                Text("关注价").frame(width: 72, alignment: .trailing)
                Text("距关注价").frame(width: 82, alignment: .trailing)
                Text("下一档").frame(width: 88, alignment: .trailing)
                Text("备注").frame(maxWidth: .infinity, alignment: .leading)
                Text("操作").frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.line.opacity(0.18))

            ForEach(rows) { row in
                let p = row.position
                let hot = watchRowIsHot(row)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(p.name).font(.system(size: 12, weight: .semibold))
                            Pill(text: "观察", color: Theme.amber)
                        }
                        Text(p.market == .cn ? p.code : "\(p.code) · \(p.market.displayName)")
                            .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                    }.frame(width: 196, alignment: .leading)

                    Text(row.view.quote.map { price($0.price) } ?? "—")
                        .frame(width: 68, alignment: .trailing)
                    Text(row.view.quote.map { pct($0.changePct) } ?? "—")
                        .foregroundStyle((row.view.quote?.changePct ?? 0) >= 0 ? Theme.up : Theme.down)
                        .frame(width: 62, alignment: .trailing)
                    Text(p.watchPrice.map { price($0) } ?? "—")
                        .frame(width: 72, alignment: .trailing)
                    Text(watchGapText(row))
                        .foregroundStyle(hot ? Theme.amber : Theme.muted)
                        .frame(width: 82, alignment: .trailing)
                    Text(watchNextText(row))
                        .foregroundStyle(row.hit != nil ? Theme.amber : (row.next == nil ? Theme.muted : Theme.accent))
                        .frame(width: 88, alignment: .trailing)
                    Text(p.note?.isEmpty == false ? p.note! : "—")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("转为持仓…") { state.activeSheet = .convertWatch(p.id) }
                        .controlSize(.small)
                        .disabled(!p.market.isHoldable)
                        .help(p.market.isHoldable ? "" : "美股和指数目前只支持观察")
                        .frame(width: 96, alignment: .trailing)
                }
                .font(.system(size: 11.5)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(hot ? Theme.amber.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { state.selectPosition(p.id) }
                .contextMenu {
                    Button("在 Carapace 中打开") { state.selectPosition(p.id) }
                    Button("编辑观察…") { state.activeSheet = .watchEditor(p.id) }
                    Button("转为持仓…") { state.activeSheet = .convertWatch(p.id) }
                        .disabled(!p.market.isHoldable)
                    Divider()
                    Button("移除观察…", role: .destructive) {
                        removingWatchId = p.id
                        confirmRemoveWatch = true
                    }
                }
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    private var plans: some View {
        let open = state.allPositions(includeClosed: false) + state.watchRows.map(\.position)
        return VStack(spacing: 0) {
            HStack {
                Text("标的").frame(width: 190, alignment: .leading)
                Text("版本").frame(width: 55, alignment: .trailing)
                Text("档位").frame(width: 55, alignment: .trailing)
                Text("下次复盘").frame(width: 110, alignment: .trailing)
                Text("状态").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.line.opacity(0.18))
            ForEach(open) { p in
                let plan = state.plans[p.id]
                Button {
                    state.selectPosition(p.id, tab: .plan)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(p.name).font(.system(size: 12, weight: .semibold))
                                if p.kind == .watch { Pill(text: "观察", color: Theme.amber) }
                            }
                            Text(p.market == .cn ? p.code : p.market.displayName).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                        }.frame(width: 190, alignment: .leading)
                        Text("v\(plan?.version ?? 0)").frame(width: 55, alignment: .trailing)
                        Text("\(plan?.levels.count ?? 0)").frame(width: 55, alignment: .trailing)
                        Text(p.kind == .watch ? "—" : (plan?.nextReview ?? "—"))
                            .frame(width: 110, alignment: .trailing)
                        Text(p.kind == .watch
                             ? (plan == nil ? "未建计划" : "观察中")
                             : (plan.map { $0.nextReview != nil ? "正常" : "待设置" } ?? "未建计划"))
                            .foregroundStyle(plan == nil ? Theme.amber : Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 11.5)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    private var ledger: some View {
        let changes = state.recentChanges
        return VStack(spacing: 0) {
            HStack {
                Button("导出 CSV") { exportCSV(state) }.controlSize(.small)
                Spacer()
                if let batch = state.lastImport {
                    Button("回滚最近批次") { state.rollbackImport(batch) }.controlSize(.small)
                }
            }.padding(.bottom, 8)
            HStack {
                Text("日期").frame(width: 90, alignment: .leading)
                Text("类型").frame(width: 48, alignment: .leading)
                Text("摘要").frame(maxWidth: .infinity, alignment: .leading)
                Text("数量").frame(width: 70, alignment: .trailing)
                Text("价格").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.line.opacity(0.18))
            ForEach(changes) { c in
                HStack {
                    Text(String(c.occurredAt.prefix(10))).frame(width: 90, alignment: .leading)
                    Text(changeLabel(c.type)).frame(width: 48, alignment: .leading)
                    Text(changeSummary(c)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(c.qtyAfter.map { String(format: "%.0f", $0) } ?? "—")
                        .frame(width: 70, alignment: .trailing)
                    Text(c.price.map(price) ?? "—").frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 11)).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}

struct OverviewPositionTable: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("名称").frame(width: 160, alignment: .leading)
                Text("现价").frame(width: 66, alignment: .trailing)
                Text("涨跌").frame(width: 60, alignment: .trailing)
                Text("今日盈亏").frame(width: 82, alignment: .trailing)
                Text("总盈亏").frame(width: 82, alignment: .trailing)
                Text("持仓").frame(width: 72, alignment: .trailing)
                Text("成本").frame(width: 62, alignment: .trailing)
                Text("仓位").frame(width: 50, alignment: .trailing)
                Text("下一档").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.line.opacity(0.18))
            ForEach(state.rows) { row in
                Button { state.selectPosition(row.id) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.position.name).font(.system(size: 12, weight: .semibold))
                            Text(codeLine(row)).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                        }.frame(width: 160, alignment: .leading)
                        Text(row.view.quote.map { price($0.price) } ?? "—").frame(width: 66, alignment: .trailing)
                        Text(row.view.quote.map { pct($0.changePct) } ?? "—")
                            .foregroundStyle((row.view.quote?.changePct ?? 0) >= 0 ? Theme.up : Theme.down)
                            .frame(width: 60, alignment: .trailing)
                        Text(row.view.todayPnl.map(signedMoney) ?? "—")
                            .foregroundStyle((row.view.todayPnl ?? 0) >= 0 ? Theme.up : Theme.down)
                            .frame(width: 82, alignment: .trailing)
                        Text(row.view.totalPnl.map(signedMoney) ?? "—")
                            .foregroundStyle((row.view.totalPnl ?? 0) >= 0 ? Theme.up : Theme.down)
                            .frame(width: 82, alignment: .trailing)
                        Text(Fmt.qty(row.position.quantity, unit: row.position.unit))
                            .frame(width: 72, alignment: .trailing)
                        Text(price(row.position.avgCost)).frame(width: 62, alignment: .trailing)
                        Text(row.view.weight.map { pct($0 * 100) } ?? "—")
                            .foregroundStyle(Theme.muted).frame(width: 50, alignment: .trailing)
                        Text(positionNextText(row))
                            .foregroundStyle(row.hit != nil ? Theme.accent : Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 11.5)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("在 Carapace 中打开") { state.selectPosition(row.id) }
                    Button("记一笔…") { state.activeSheet = .trade(row.id) }
                    Button("编辑持仓…") { state.activeSheet = .editPosition(row.id) }
                    Button("清仓…") { state.activeSheet = .clear(row.id) }
                }
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}

struct OverviewWatchTable: View {
    @ObservedObject var state: AppState
    @State private var confirmRemoveWatch = false
    @State private var removingId: Int64?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("名称").frame(width: 196, alignment: .leading)
                Text("现价").frame(width: 68, alignment: .trailing)
                Text("涨跌").frame(width: 62, alignment: .trailing)
                Text("关注价").frame(width: 72, alignment: .trailing)
                Text("距关注价").frame(width: 82, alignment: .trailing)
                Text("下一档").frame(width: 88, alignment: .trailing)
                Text("备注").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.line.opacity(0.18))

            ForEach(state.watchRows.prefix(5)) { row in
                let p = row.position
                let hot = watchRowIsHot(row)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.system(size: 12, weight: .semibold))
                        Text(p.market == .cn ? p.code : "\(p.code) · \(p.market.displayName)")
                            .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                    }.frame(width: 196, alignment: .leading)
                    Text(row.view.quote.map { price($0.price) } ?? "—")
                        .frame(width: 68, alignment: .trailing)
                    Text(row.view.quote.map { pct($0.changePct) } ?? "—")
                        .foregroundStyle((row.view.quote?.changePct ?? 0) >= 0 ? Theme.up : Theme.down)
                        .frame(width: 62, alignment: .trailing)
                    Text(p.watchPrice.map { price($0) } ?? "—")
                        .frame(width: 72, alignment: .trailing)
                    Text(watchGapText(row))
                        .foregroundStyle(hot ? Theme.amber : Theme.muted)
                        .frame(width: 82, alignment: .trailing)
                    Text(watchNextText(row))
                        .foregroundStyle(row.hit != nil ? Theme.amber : (row.next == nil ? Theme.muted : Theme.accent))
                        .frame(width: 88, alignment: .trailing)
                    Text(p.note?.isEmpty == false ? p.note! : "—")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11.5)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(hot ? Theme.amber.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { state.selectPosition(p.id) }
                .contextMenu {
                    Button("在 Carapace 中打开") { state.selectPosition(p.id) }
                    Button("编辑观察…") { state.activeSheet = .watchEditor(p.id) }
                    Button("转为持仓…") { state.activeSheet = .convertWatch(p.id) }
                        .disabled(!p.market.isHoldable)
                    Divider()
                    Button("移除观察…", role: .destructive) {
                        removingId = p.id
                        confirmRemoveWatch = true
                    }
                }
                Divider()
            }

            if state.watchRows.count > 5 {
                HStack {
                    Text("还有 \(state.watchRows.count - 5) 只")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Button("查看全部") {
                        state.section = .positions
                        state.holdTab = .watch
                    }.buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .alert("移除这个观察标的？", isPresented: $confirmRemoveWatch) {
            Button("取消", role: .cancel) { removingId = nil }
            Button("移除", role: .destructive) {
                if let id = removingId {
                    do {
                        try state.removeWatch(id: id)
                        state.toastText = "已移除观察"
                    } catch { state.toastText = error.localizedDescription }
                }
                removingId = nil
            }
        } message: {
            Text("观察备注、计划和指标会一起删除，已记录的复盘会保留。")
        }
    }
}

struct PositionDetailView: View {
    @ObservedObject var state: AppState
    let positionId: Int64
    @State private var confirmRemoveWatch = false
    @State private var confirmRemovePlan = false

    var body: some View {
        let p = state.anyPosition(id: positionId)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        state.showPositionDetail = false
                    } label: {
                        Label("持仓", systemImage: "chevron.left")
                    }.buttonStyle(.plain).foregroundStyle(Theme.muted).font(.system(size: 11))
                    Spacer()
                }.padding(.bottom, 8)

                if let p {
                    header(p)
                    if p.kind == .watch {
                        planTab(p).padding(.top, 12)
                    } else {
                        Picker("", selection: $state.positionTab) {
                            ForEach(PositionTab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 240).padding(.vertical, 10)
                        switch state.positionTab {
                        case .plan: planTab(p)
                        case .ledger: ledgerTab(p)
                        case .review: reviewTab(p)
                        }
                    }
                } else {
                    EmptyState(icon: "questionmark", title: "持仓不存在", detail: "它可能已经清仓或被删除。")
                }
            }
            .padding(20)
        }
        .background(Theme.panel)
        .alert("移除这个观察标的？", isPresented: $confirmRemoveWatch) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                do {
                    try state.removeWatch(id: positionId)
                    state.showPositionDetail = false
                } catch { state.toastText = error.localizedDescription }
            }
        } message: {
            Text("观察备注、计划和指标会一起删除，已记录的复盘会保留。")
        }
        .alert("移除这个计划？", isPresented: $confirmRemovePlan) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                do {
                    try state.removePlan(positionId: positionId)
                    state.toastText = "计划已移除"
                } catch { state.toastText = error.localizedDescription }
            }
        } message: {
            Text("只删除计划档位，持仓或观察标的本身保留；移除记录会写入流水。")
        }
    }

    @ViewBuilder
    private func header(_ p: Position) -> some View {
        if p.kind == .watch {
            watchHeader(p)
        } else {
            holdingHeader(p)
        }
    }

    private func watchHeader(_ p: Position) -> some View {
        let quote = state.quotes[p.quoteCode]
        let gap: Double? = {
            guard let wp = p.watchPrice, wp > 0, let q = quote else { return nil }
            return (q.price - wp) / wp * 100
        }()
        let suffix = p.market == .cn ? "" : " \(p.currency)"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.name).font(.system(size: 22, weight: .bold))
                Text(p.code).font(.system(size: 11)).foregroundStyle(Theme.faint)
                Pill(text: "观察中", color: Theme.amber)
                if p.market != .cn {
                    Pill(text: p.market.displayName, color: Theme.amber)
                }
                Spacer()
                                Button("转为持仓…") { state.activeSheet = .convertWatch(p.id) }.controlSize(.small)
                    .disabled(!p.market.isHoldable)
                    .help(p.market.isHoldable ? "" : "美股和指数目前只支持观察")
                Button("编辑观察") { state.activeSheet = .watchEditor(p.id) }.controlSize(.small)
                Button("移除") { confirmRemoveWatch = true }
                    .controlSize(.small).foregroundStyle(Theme.up)
            }
            HStack(spacing: 14) {
                metric("现价", quote.map { price($0.price) + suffix } ?? "—")
                metric("涨跌", quote.map { pct($0.changePct) } ?? "—",
                       tint: (quote?.changePct ?? 0) >= 0 ? Theme.up : Theme.down)
                metric("关注价", p.watchPrice.map { price($0) + suffix } ?? "—")
                metric("距关注价", gap.map { String(format: "%+.2f%%", $0) } ?? "—",
                       tint: (gap ?? 1) <= 0 ? Theme.amber : .primary)
                metric("观察天数", "\(p.heldDays) 天")
            }
        }
    }

    private func holdingHeader(_ p: Position) -> some View {
        let view = state.portfolio?.views.first { $0.id == p.id }
        let suffix = p.market == .cn ? "" : " \(p.currency)"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.name).font(.system(size: 22, weight: .bold))
                Text(p.code).font(.system(size: 11)).foregroundStyle(Theme.faint)
                Pill(text: p.status == .open ? "持仓中" : "已清仓",
                     color: p.status == .open ? Theme.accent : Theme.muted)
                if p.market != .cn { Pill(text: p.market.displayName, color: Theme.amber) }
                Spacer()
                                Button("记一笔") { state.activeSheet = .trade(p.id) }.controlSize(.small)
                Button("编辑") { state.activeSheet = .editPosition(p.id) }.controlSize(.small)
                Button("清仓") { state.activeSheet = .clear(p.id) }.controlSize(.small)
                    .foregroundStyle(Theme.up)
            }
            HStack(spacing: 14) {
                metric("现价", (view?.quote.map { price($0.price) } ?? "—") + (view?.quote == nil ? "" : suffix))
                metric("成本", price(p.avgCost) + suffix)
                metric("持仓", Fmt.qty(p.quantity, unit: p.unit))
                metric("市值", (view?.value.map(money) ?? "—") + (view?.value == nil ? "" : suffix))
                metric("今日", (view?.todayPnl.map(signedMoney) ?? "—") + (view?.todayPnl == nil ? "" : suffix),
                       tint: (view?.todayPnl ?? 0) >= 0 ? Theme.up : Theme.down)
                metric("未实现", (view?.totalPnl.map(signedMoney) ?? "—") + (view?.totalPnl == nil ? "" : suffix),
                       tint: (view?.totalPnl ?? 0) >= 0 ? Theme.up : Theme.down)
            }
            if p.market != .cn {
                Text("港股按 HKD 计价；组合市值、盈亏和仓位已按港币汇率折算成 CNY。")
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
        }
    }

    private func metric(_ key: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).monospacedDigit()
        }
    }

    private func planTab(_ p: Position) -> some View {
        let plan = state.plans[p.id]
        let executed = state.executedLevels(for: p.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if p.kind == .watch {
                    Text("观察阶段只设买入档；建仓后再补卖出和停止档，数量可以留空。")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.amber.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(.bottom, 8)
                }
                HStack {
                    Text("计划 v\(plan?.version ?? 0)").font(.system(size: 13.5, weight: .semibold))
                    if let next = plan?.nextReview {
                        Text("下次复盘 \(next)").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("草稿…") { state.activeSheet = .drafts }
                        .controlSize(.small)
                    Button("手写/编辑") { state.activeSheet = .editPlan(p.id) }
                        .controlSize(.small)
                    if plan != nil {
                        Button("移除计划") { confirmRemovePlan = true }
                            .controlSize(.small).foregroundStyle(Theme.up)
                    }
                }.padding(.bottom, 8)
                if let description = plan?.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }

                if let levels = plan?.levels, !levels.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("方向").frame(width: 70, alignment: .leading)
                            Text("价格").frame(width: 75, alignment: .leading)
                            Text("数量").frame(width: 75, alignment: .leading)
                            Text("条件").frame(maxWidth: .infinity, alignment: .leading)
                            Text("状态").frame(width: 70, alignment: .trailing)
                        }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.line.opacity(0.18))
                        ForEach(levels) { level in
                            HStack {
                                Text(level.kind.cn)
                                    .foregroundStyle(level.kind == .buy ? Theme.up : level.kind == .sell ? Theme.down : Theme.amber)
                                    .frame(width: 70, alignment: .leading)
                                Text(price(level.price)).frame(width: 75, alignment: .leading)
                                Text(level.quantity.map { Fmt.money($0) } ?? "—")
                                    .frame(width: 75, alignment: .leading)
                                Text(level.condition).frame(maxWidth: .infinity, alignment: .leading)
                                Text(executed.contains(level.id) ? "已执行" : "未触发")
                                    .foregroundStyle(executed.contains(level.id) ? Theme.down : Theme.muted)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .font(.system(size: 11)).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            Divider()
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                } else {
                    EmptyState(icon: "list.bullet.rectangle",
                               title: plan == nil ? "还没有计划" : "还没有档位",
                               detail: plan == nil
                                   ? "可以手写档位，或让外部 Agent 生成草稿。"
                                   : "计划说明已保存；点「手写/编辑」补充价格档位。",
                               actionTitle: "写计划") {
                        state.activeSheet = .editPlan(p.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("计划草稿由外部 Agent 生成，在「草稿…」里确认后才写入。")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                Spacer()
            }
            .frame(width: 260)
        }
    }

    private func ledgerTab(_ p: Position) -> some View {
        let changes = state.changes(for: p.id)
        return VStack(spacing: 0) {
            ForEach(changes) { c in
                HStack {
                    Text(String(c.occurredAt.prefix(10))).frame(width: 90, alignment: .leading)
                    Text(changeLabel(c.type)).frame(width: 48, alignment: .leading)
                    Text(changeSummary(c)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(c.qtyAfter.map { String(format: "%.0f", $0) } ?? "—")
                        .frame(width: 70, alignment: .trailing)
                    Text(c.price.map(price) ?? "—").frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 11)).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
    }

    private func reviewTab(_ p: Position) -> some View {
        let review = state.reviewRecords.first { $0.positionId == p.id }
        return CardBox {
            if let review {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(review.kind == "exit" ? "清仓复盘" : "计划复盘")
                            .font(.system(size: 13, weight: .semibold))
                        Pill(text: review.status == "done" ? "已完成" : "待复盘",
                             color: review.status == "done" ? Theme.down : Theme.amber)
                        Spacer()
                        Button("打开复盘") {
                            state.section = .reviews
                            state.selectedReviewId = review.id
                        }.controlSize(.small)
                    }
                    Text(review.notes.isEmpty ? "还没有填写判断。" : review.notes)
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                                    }
            } else {
                EmptyState(icon: "arrow.triangle.2.circlepath", title: "还没有复盘",
                           detail: "计划到期、档位执行或清仓时会生成复盘待办。") {
                    createReviewFor(p)
                }
            }
        }
    }

    private func createReviewFor(_ p: Position) {
        let facts = [
            ["持仓天数", "\(max(1, Int(Date().timeIntervalSince(Dates.parse(p.openedAt) ?? Date()) / 86_400))) 天"],
            ["成本", price(p.avgCost)],
            ["现价", state.quotes[p.quoteCode].map { price($0.price) } ?? "—"]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: facts)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "[]"
        _ = try? state.store.createReview(positionId: p.id, kind: "plan",
                                          dueAt: Dates.today(),
                                          profileId: nil,
                                          factsJSON: json)
        state.loadV5()
    }
}

@MainActor
func top3Weight(_ state: AppState) -> Double {
    let values = (state.portfolio?.views ?? []).compactMap(\.valueCNY).sorted(by: >)
    let total = values.reduce(0, +)
    guard total > 0 else { return 0 }
    return values.prefix(3).reduce(0, +) / total
}

@MainActor
func stopCoverage(_ state: AppState) -> String {
    let holdings = state.rows
    let covered = holdings.filter { row in
        row.plan?.levels.contains { $0.kind == .stop } == true
    }.count
    return "\(covered) / \(holdings.count) 只"
}

func changeLabel(_ type: ChangeType) -> String {
    switch type {
    case .open: return "建仓"
    case .buy: return "买入"
    case .sell: return "卖出"
    case .clear: return "清仓"
    case .adjust: return "修正"
    case .plan: return "计划"
    case .cost: return "成本"
    }
}

func changeSummary(_ c: Change) -> String {
    switch c.type {
    case .open:
        return "建仓 \(c.qtyAfter.map { String(format: "%.0f", $0) } ?? "") @ \(c.price.map(price) ?? "")"
    case .buy, .sell:
        let qty = abs((c.qtyAfter ?? 0) - (c.qtyBefore ?? 0))
        return "\(c.type == .buy ? "买入" : "卖出") \(String(format: "%.0f", qty)) @ \(c.price.map(price) ?? "")" + (c.note.map { " · \($0)" } ?? "")
    case .clear:
        return "清仓 @ \(c.price.map(price) ?? "")"
    case .adjust:
        return "修正持仓" + (c.note.map { " · \($0)" } ?? "")
    case .plan:
        return "计划变更" + (c.note.map { " · \($0)" } ?? "")
    case .cost:
        return "成本 \(c.costBefore.map(price) ?? "") → \(c.costAfter.map(price) ?? "")"
    }
}

@MainActor
func exportCSV(_ state: AppState) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "carapace-changes.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? state.store.exportChangesCSV(to: url)
    state.toastText = "已导出 CSV"
}

/// 基金一天一个净值，在代码后面标出净值日期（MM-dd），说明这段涨跌是哪天的。
private func codeLine(_ row: PanelRow) -> String {
    let code = row.position.market == .cn
        ? row.position.code
        : "\(row.position.code) · \(row.position.market.displayName)"
    guard let q = row.view.quote, q.source == .fund, q.time.count >= 10 else {
        return code
    }
    return "\(code) · 净值 \(q.time.prefix(10).suffix(5))"
}

// MARK: - Watch helpers

func watchGapPct(_ row: PanelRow) -> Double? {
    guard let wp = row.position.watchPrice, wp > 0,
          let value = row.view.quote?.price else { return nil }
    return (value - wp) / wp * 100
}

func watchRowIsHot(_ row: PanelRow) -> Bool {
    (watchGapPct(row) ?? 1) <= 0
}

func watchGapText(_ row: PanelRow) -> String {
    watchGapPct(row).map(Fmt.signedPct) ?? "—"
}

func watchNextText(_ row: PanelRow) -> String {
    if let hit = row.hit { return "买 \(price(hit.price)) ✓" }
    if let next = row.next { return "买 \(price(next.price))" }
    return "—"
}

func positionNextText(_ row: PanelRow) -> String {
    if let hit = row.hit {
        return "\(hit.kind == .buy ? "买" : "卖") \(price(hit.price)) ✓"
    }
    if let next = row.next {
        return "\(next.kind == .buy ? "买" : "卖") \(price(next.price))"
    }
    return "—"
}
