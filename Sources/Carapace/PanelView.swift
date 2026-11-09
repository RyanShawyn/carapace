import SwiftUI
import CarapaceCore

/// 只读面板：持仓、计划、告警。增删改都在右键菜单打开的窗口里。
struct PanelView: View {
    @ObservedObject var state: AppState
    var onOpenApp: (() -> Void)? = nil
    var onOpenPosition: ((Int64) -> Void)? = nil
    var onEditWatch: ((Int64) -> Void)? = nil
    var onConvertWatch: ((Int64) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @AppStorage("panelWatchCollapsed") private var watchCollapsed = false

    // 面板只留盘中要看的东西；总盈亏只在主窗口显示。
    private var nameW: CGFloat { 120 }
    private var priceW: CGFloat { 62 }
    private var chgW: CGFloat { 56 }
    private var pnlW: CGFloat { 80 }
    private let qtyW: CGFloat = 66
    private var costW: CGFloat { 62 }
    private var posW: CGFloat { 48 }
    private var nextW: CGFloat { 88 }
    private let gap: CGFloat = 6
    private let pad: CGFloat = 14

    private var panelWidth: CGFloat { 684 }

    /// 持仓区最大高度；超过后滚动，避免把面板顶出屏幕。
    private var listHeight: CGFloat {
        let expanded: CGFloat = state.expanded == nil ? 0 : 140
        let rows = CGFloat(state.rows.count) * 38 + expanded
        // 观察行有两行（关注价/备注），比持仓行高一些。
        let watches = state.watchRows.isEmpty
            ? 0 : CGFloat(state.watchRows.count) * 52 + 24
        return min(max(rows + watches + 4, 44), 560)
    }

    var body: some View {
        VStack(spacing: 0) {
            UpdateBannerHost(updater: state.updater, compact: true)
            if !state.rows.isEmpty {
                header
                Divider().opacity(0.55)
            }
            if state.rows.isEmpty && state.watchRows.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(state.rows) { row in
                            rowView(row)
                            if state.expanded == row.id {
                                planView(row)
                            }
                            Divider().opacity(0.55)
                        }
                        if !state.watchRows.isEmpty {
                            watchSection
                        }
                    }
                }
                .frame(height: listHeight)
            }
            if state.showIndexStrip && !state.indexQuotes.isEmpty {
                indexStrip
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: panelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: gap) {
            Text("名称").frame(width: nameW, alignment: .leading)
            Text("现价").frame(width: priceW)
            Text("涨跌").frame(width: chgW)
            Text("今日盈亏").frame(width: pnlW)
            Text("持仓").frame(width: qtyW)
            Text("成本").frame(width: costW)
            Text("仓位").frame(width: posW)
            Text("下一档").frame(width: nextW)
            Button { onOpenApp?() } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 24)
            .help("打开 Carapace").accessibilityLabel("打开 Carapace")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, pad)
        .padding(.vertical, 7)
        // 表头和数据行都从面板左边缘开始排版，列宽才能对齐。
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("还没有持仓")
                .font(.system(size: 13, weight: .semibold))
            Text("打开 Carapace 新建持仓")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Index strip

    /// 通知上方的指数条：简称 + 点位 + 涨跌，一行放四个。
    private var indexStrip: some View {
        HStack(spacing: 18) {
            ForEach(MarketIndex.panel) { index in
                let quote = state.indexQuotes[index.secid]
                HStack(spacing: 4) {
                    Text(index.shortName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(quote.map { Fmt.money($0.price, digits: 2) } ?? "—")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(color(for: quote?.changePct))
                    if let quote {
                        Text(Fmt.signedPct(quote.changePct))
                            .font(.system(size: 10))
                            .foregroundStyle(color(for: quote.changePct))
                            .opacity(0.85)
                    }
                }
                .fixedSize()
                .help(quote.map { "\(index.fullName) · 行情 \($0.time)" } ?? "\(index.fullName) · 行情不可用")
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .padding(.horizontal, pad)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    private func rowView(_ row: PanelRow) -> some View {
        HStack(spacing: gap) {
            HStack(spacing: 3) {
                Text(row.position.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if row.position.market != .cn {
                    Text(marketBadge(row.position.market))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Theme.amber)
                }
            }
            .frame(width: nameW, alignment: .leading)

            Text(row.view.quote.map { Fmt.price($0.price) } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: priceW)

            VStack(spacing: 0) {
                Text(row.view.quote.map { Fmt.signedPct($0.changePct) } ?? "—")
                    .font(.system(size: 11.5))
                    .foregroundStyle(color(for: row.view.quote?.changePct))
                    .opacity(0.78)
                // 基金一天一个净值，标出净值日期，说明这段涨跌是哪天的。
                if let q = row.view.quote, q.source == .fund {
                    Text("净值 \(q.time.prefix(10).suffix(5))")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(width: chgW)

            Text(row.view.quote.map { _ in Fmt.signedMoney(row.view.todayPnl ?? 0) } ?? "—")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(color(for: row.view.quote.map { _ in row.view.todayPnl ?? 0 }))
                .frame(width: pnlW)

            Text(Fmt.money(row.position.quantity,
                           digits: row.position.unit.digits))
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: qtyW)

            Text(Fmt.price(row.position.avgCost))
                .font(.system(size: 12.5))
                .frame(width: costW)

            Text(state.weight(row).map { Fmt.pctInt($0) } ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: posW)

            Button {
                state.expanded = (state.expanded == row.id) ? nil : row.id
            } label: {
                HStack(spacing: 2) {
                    Text(levelText(row))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("›").font(.system(size: 10)).opacity(0.65)
                }
                .foregroundStyle(accent)
                .frame(width: nextW)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一档 \(levelText(row))")
        }
        .monospacedDigit()
        .padding(.horizontal, pad)
        .padding(.vertical, 9)
        // 数据行与表头一样铺满面板宽度，首列从同一左边缘开始。
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture { onOpenPosition?(row.id) }
        .contextMenu {
            Button("在 Carapace 中打开") { onOpenPosition?(row.id) }
        }
    }

    private func levelText(_ row: PanelRow) -> String {
        if let hit = row.hit { return "\(hit.kind == .buy ? "买" : "卖") \(Fmt.level(hit.price)) ✓" }
        if let next = row.next { return "\(next.kind == .buy ? "买" : "卖") \(Fmt.level(next.price))" }
        return "—"
    }

    // MARK: - Watch list

    private var watchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("观察 \(state.watchRows.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("· 不参与组合")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(watchCollapsed ? "展开 ▸" : "收起 ▾") {
                    watchCollapsed.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03))

            if !watchCollapsed {
                ForEach(state.watchRows) { row in
                    watchRow(row)
                    Divider().opacity(0.55)
                }
            }
        }
    }

    /// 观察行沿用持仓的列网格：持仓才有的列填「—」，关注价/距关注价/备注放在第二行。
    private func watchRow(_ row: PanelRow) -> some View {
        let p = row.position
        let hot = watchIsHot(row)
        return VStack(spacing: 0) {
            HStack(spacing: gap) {
                HStack(spacing: 3) {
                    Text(p.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if p.market != .cn {
                        Text(marketBadge(p.market))
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.amber)
                    }
                }
                .frame(width: nameW, alignment: .leading)

                Text(row.view.quote.map { Fmt.price($0.price) } ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: priceW)

                Text(row.view.quote.map { Fmt.signedPct($0.changePct) } ?? "—")
                    .font(.system(size: 11.5))
                    .foregroundStyle(color(for: row.view.quote?.changePct))
                    .opacity(0.78)
                    .frame(width: chgW)

                Text("—").font(.system(size: 12.5)).foregroundStyle(.tertiary)
                    .frame(width: pnlW)
                Text("—").font(.system(size: 12.5)).foregroundStyle(.tertiary)
                    .frame(width: qtyW)
                Text("—").font(.system(size: 12.5)).foregroundStyle(.tertiary)
                    .frame(width: costW)
                Text("—").font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(width: posW)

                Text(watchLevelText(row))
                    .font(.system(size: 12, weight: row.hit == nil ? .regular : .semibold))
                    .foregroundStyle(row.hit == nil ? (row.next == nil ? Color.secondary : accent) : Theme.amber)
                    .frame(width: nextW, alignment: .leading)
            }
            .monospacedDigit()
            .padding(.horizontal, pad)
            .padding(.top, 8)
            .padding(.bottom, watchMetaText(row) == nil ? 8 : 3)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let meta = watchMetaText(row) {
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(hot ? Theme.amber : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, pad)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hot ? Theme.amber.opacity(scheme == .dark ? 0.10 : 0.06) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.amber.opacity(hot ? 0.9 : 0.35))
                .frame(width: 2)
                .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenPosition?(p.id) }
        .help(p.note?.isEmpty == false ? p.note! : "观察标的")
        .contextMenu {
            Button("在 Carapace 中打开") { onOpenPosition?(p.id) }
            Button("编辑观察…") { onEditWatch?(p.id) }
            Button("转为持仓…") { onConvertWatch?(p.id) }
        }
    }

    private func watchMetaText(_ row: PanelRow) -> String? {
        var parts: [String] = []
        if let wp = row.position.watchPrice {
            parts.append("关注 \(Fmt.price(wp))")
            if let distance = watchDistance(row) {
                parts.append("距 \(Fmt.signedPct(distance))")
            }
        }
        if let note = row.position.note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func watchDistance(_ row: PanelRow) -> Double? {
        guard let wp = row.position.watchPrice, wp > 0,
              let price = row.view.quote?.price else { return nil }
        return (price - wp) / wp * 100
    }

    private func watchIsHot(_ row: PanelRow) -> Bool {
        guard let wp = row.position.watchPrice, wp > 0,
              let price = row.view.quote?.price else { return false }
        return price <= wp
    }

    private func watchLevelText(_ row: PanelRow) -> String {
        if let hit = row.hit { return "买 \(Fmt.level(hit.price)) ✓" }
        if let next = row.next { return "买 \(Fmt.level(next.price))" }
        return "—"
    }

    // MARK: - Plan (read-only)

    private func planView(_ row: PanelRow) -> some View {
        VStack(spacing: 0) {
            if let plan = row.plan,
               !plan.levels.isEmpty || !(plan.description ?? "").isEmpty
                   || !(plan.nextReview ?? "").isEmpty {
                if let quote = row.view.quote {
                    Text("\(quote.source.displayName) · 行情 \(quote.time)")
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, pad + 8).padding(.top, 5)
                }
                if let description = plan.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, pad + 8)
                        .padding(.top, 7)
                }
                if !plan.levels.isEmpty {
                    HStack(spacing: 6) {
                        Text("价格").frame(width: 60, alignment: .leading)
                        Text("动作").frame(width: 96, alignment: .leading)
                        Text("条件").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, pad + 8)
                    .padding(.top, 6)
                    .padding(.bottom, 3)

                    ForEach(Array(plan.levels.enumerated()), id: \.offset) { _, level in
                        let done = row.executed.contains(level.id)
                        HStack(spacing: 6) {
                            Text(Fmt.level(level.price))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 60, alignment: .leading)
                            Text(actionText(level, unit: row.position.unit))
                                .font(.system(size: 12))
                                .frame(width: 96, alignment: .leading)
                            Text(level.condition)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, pad + 8)
                        .padding(.vertical, 3)
                        .opacity(done ? 0.4 : 1)
                    }
                }
                if let review = plan.nextReview, !review.isEmpty {
                    Text("下次复盘 \(review)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, pad + 8)
                        .padding(.top, 2)
                }
            } else {
                Text("还没有计划，右键 → 编辑持仓…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, pad + 8)
                    .padding(.vertical, 6)
            }
            Spacer(minLength: 7)
        }
        .background(Color.primary.opacity(scheme == .dark ? 0.045 : 0.035))
    }

    private func actionText(_ level: PlanLevel, unit: UnitKind) -> String {
        switch level.kind {
        case .buy:
            return "买 " + qty(level.quantity, unit: unit)
        case .sell:
            return "卖 " + qty(level.quantity, unit: unit)
        case .stop:
            return "停止买入"
        }
    }

    private func qty(_ value: Double?, unit: UnitKind) -> String {
        guard let value else { return "" }
        return Fmt.money(value, digits: unit.digits) + unit.suffix
    }

    // MARK: - Footer

    /// 面板只列未确认的提醒；确认过的留在数据库里等条件消失后归档，不再占用面板。
    private var openAlerts: [CarapaceCore.Alert] {
        state.alerts.filter { !$0.isAcknowledged }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if openAlerts.isEmpty {
                    Text(state.footerStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(openAlerts.prefix(3))) { alert in
                        alertRow(alert)
                    }
                    HStack(spacing: 10) {
                        if openAlerts.count > 3 {
                            Text("还有 \(openAlerts.count - 3) 条")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Button("全部确认") { state.acknowledgeAll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                HStack(spacing: 3) {
                    Text("今日").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(state.todayTotal.map(Fmt.signedMoney) ?? "—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color(for: state.todayTotal ?? 0))
                }
                HStack(spacing: 3) {
                    Text("已知市值").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Fmt.wan(state.totalValue))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .fixedSize()
            .help(state.rows.contains { $0.position.market == .hk }
                  ? "港股价格与盈亏按 HKD 显示，合计按港币汇率折算成 CNY" : "")
        }
        .monospacedDigit()
        .padding(.horizontal, pad)
        .padding(.vertical, 8)
    }

    private func alertRow(_ alert: CarapaceCore.Alert) -> some View {
        let tint = alertTint(alert)
        return Button {
            if !alert.isAcknowledged { state.acknowledge(alert.id) }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: alertIcon(alert))
                    .font(.system(size: 10, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert.title).font(.system(size: 11.5, weight: .semibold))
                    if !alert.detail.isEmpty { Text(alert.detail).font(.system(size: 10)).opacity(0.8) }
                }
                Spacer(minLength: 4)
                Text(alert.isAcknowledged ? "已确认" : "点此确认").font(.system(size: 9.5)).opacity(0.7)
            }.foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(alert.kind == .review ? Color.clear : tint.opacity(alert.isAcknowledged ? 0.05 : 0.10)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .help(alert.isAcknowledged ? "条件消失后这条会归档" : "点此确认，菜单栏图标会恢复")
    }

    private func alertTint(_ alert: CarapaceCore.Alert) -> Color {
        if alert.isAcknowledged { return .secondary }
        switch alert.kind {
        case .quote, .risk: return Color(nsColor: .systemOrange)
        case .hit: return Color(nsColor: .systemBlue)
        case .watch: return Color(nsColor: .systemOrange)
        case .review: return .secondary
        }
    }

    private func alertIcon(_ alert: CarapaceCore.Alert) -> String {
        if alert.isAcknowledged { return "checkmark.circle" }
        switch alert.kind {
        case .quote, .risk: return "exclamationmark.triangle.fill"
        case .hit: return "circle.fill"
        case .watch: return "eye.fill"
        case .review: return "clock"
        }
    }

    // MARK: - Colors

    private var up: Color {
        scheme == .dark
            ? Color(red: 1.00, green: 0.48, blue: 0.44)
            : Color(red: 0.78, green: 0.16, blue: 0.16)
    }

    private var down: Color {
        scheme == .dark
            ? Color(red: 0.19, green: 0.82, blue: 0.35)
            : Color(red: 0.10, green: 0.50, blue: 0.22)
    }

    private var accent: Color {
        scheme == .dark
            ? Color(red: 0.35, green: 0.66, blue: 1.00)
            : Color(red: 0.00, green: 0.40, blue: 0.80)
    }

    private func color(for value: Double?) -> Color {
        guard let value else { return .secondary }
        return value >= 0 ? up : down
    }
}
