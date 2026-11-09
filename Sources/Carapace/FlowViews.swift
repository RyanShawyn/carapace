import SwiftUI
import AppKit
import CarapaceCore

struct IntakeWizardView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var quick = true
    @State private var step = 1
    @State private var code = ""
    @State private var name = ""
    @State private var quantity = ""
    @State private var cost = ""
    @State private var thesis = ""
    @State private var invalidation = ""
    @State private var riskBudget = ""
    @State private var stopPrice = ""
    @State private var levels: [PlanLevel] = []
    @State private var error = ""
    @State private var searchResult: SymbolSearchResult?
    @State private var source: QuoteSource?
    @State private var unit: UnitKind?
    @State private var selectedMarket: InstrumentMarket = .cn
    @State private var selectedQuoteKey: String?
    @State private var confirmDiscard = false

    private var dirty: Bool {
        !code.isEmpty || !name.isEmpty || !quantity.isEmpty || !cost.isEmpty
            || !thesis.isEmpty || !invalidation.isEmpty || !riskBudget.isEmpty
            || !stopPrice.isEmpty || !levels.isEmpty || searchResult != nil
    }

    private var parsedCost: Double { Double(cost.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var parsedQty: Double { Double(quantity.replacingOccurrences(of: ",", with: "")) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建持仓").font(.system(size: 15, weight: .semibold))
                Pill(text: "预设流程", color: Theme.accent)
                Spacer()
                Picker("", selection: $quick) {
                    Text("快速").tag(true)
                    Text("完整").tag(false)
                }.pickerStyle(.segmented).frame(width: 150)
                Button {
                    if dirty { confirmDiscard = true } else { dismiss() }
                } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if quick {
                        quickForm
                    } else {
                        steps
                        switch step {
                        case 1: basicForm
                        case 2: logicForm
                        case 3: riskForm
                        case 4: planForm
                        default: confirm
                        }
                    }
                    if !error.isEmpty {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                    }
                }
                .padding(18)
            }
            Divider()
            HStack {
                Text(quick ? "快速模式：4 项即可" : "第 \(step) 步，共 5 步")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                Spacer()
                Button("取消") { dismiss() }
                if !quick && step > 1 {
                    Button("上一步") { step -= 1 }
                }
                if quick {
                    Button("保存持仓") { save() }.buttonStyle(.borderedProminent)
                } else if step < 5 {
                    Button("下一步") { step += 1 }.buttonStyle(.borderedProminent)
                } else {
                    Button("保存持仓") { save() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
        .frame(width: 760, height: 640)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            SymbolSearchField(selection: $searchResult, holdingsOnly: true)
                .onChange(of: searchResult) { result in
                    guard let result else { return }
                    code = result.code
                    name = result.name
                    source = result.source
                    unit = result.unit
                    selectedMarket = result.instrumentMarket
                    selectedQuoteKey = result.quoteKey
                }
            Text("港股按 HKD 输入数量和成本，合计按汇率折算；指数、美股请用「添加观察」。")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
        }
    }

    private var quickForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBox
            CardBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow {
                        Text("代码").foregroundStyle(Theme.muted)
                        TextField("600000", text: $code).textFieldStyle(.roundedBorder)
                        Text("名称").foregroundStyle(Theme.muted)
                        TextField("自动/手动", text: $name).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("数量").foregroundStyle(Theme.muted)
                        TextField("100", text: $quantity).textFieldStyle(.roundedBorder)
                        Text("成本").foregroundStyle(Theme.muted)
                        TextField("10.00", text: $cost).textFieldStyle(.roundedBorder)
                    }
                    }
                .font(.system(size: 11.5))
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                HStack(spacing: 5) {
                    Text(i < step ? "✓" : "\(i)")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(i == step ? Theme.accent : Theme.line.opacity(0.3))
                        .foregroundStyle(i == step ? .white : .primary)
                        .clipShape(Circle())
                    Text(["标的", "逻辑", "仓位", "计划", "确认"][i - 1]).font(.system(size: 10.5))
                }
                if i < 5 { Divider().frame(width: 14) }
            }
        }
    }

    private var basicForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBox
            CardBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text("代码").foregroundStyle(Theme.muted)
                    TextField("600000", text: $code).textFieldStyle(.roundedBorder)
                    Text("名称").foregroundStyle(Theme.muted)
                    TextField("自动/手动", text: $name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("数量").foregroundStyle(Theme.muted)
                    TextField("100", text: $quantity).textFieldStyle(.roundedBorder)
                    Text("成本").foregroundStyle(Theme.muted)
                    TextField("10.00", text: $cost).textFieldStyle(.roundedBorder)
                }
                }.font(.system(size: 11.5))
            }
        }
    }

    private var logicForm: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("为什么现在买？")
                    .font(.system(size: 11.5, weight: .semibold))
                TextEditor(text: $thesis).frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                Text("什么情况下逻辑不成立？")
                    .font(.system(size: 11.5, weight: .semibold))
                TextEditor(text: $invalidation).frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                Text("不填也能继续。")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var riskForm: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("单笔风险预算").font(.system(size: 11.5))
                    TextField("按需填写", text: $riskBudget).textFieldStyle(.roundedBorder).frame(width: 120)
                    Text("止损价").font(.system(size: 11.5))
                    TextField("可选", text: $stopPrice).textFieldStyle(.roundedBorder).frame(width: 100)
                }
                Text("按 1% 风险预算和止损价估算建议数量；实际数量仍以你填写的为准。")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
                if let stop = Double(stopPrice), stop > 0, parsedCost > stop,
                   let budget = Double(riskBudget) {
                    let suggested = budget / (parsedCost - stop)
                    Text("建议数量约 \(Fmt.money(suggested))")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var planForm: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("分档计划").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("添加一档") {
                        levels.append(PlanLevel(price: parsedCost, kind: .buy, quantity: nil, condition: ""))
                    }.controlSize(.small)
                }
                ForEach($levels) { $level in
                    HStack(spacing: 6) {
                        Picker("", selection: $level.kind) {
                            ForEach(PlanLevel.Kind.allCases, id: \.self) { k in
                                Text(k.cn).tag(k)
                            }
                        }.labelsHidden().frame(width: 80)
                        TextField("价格", value: $level.price, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        TextField("数量", text: quantityBinding($level))
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        TextField("条件", text: $level.condition).textFieldStyle(.roundedBorder)
                        Button {
                            levels.removeAll { $0.id == level.id }
                        } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var confirm: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                KeyValueRow(key: "代码", value: code)
                KeyValueRow(key: "名称", value: name.isEmpty ? code : name)
                KeyValueRow(key: "持仓", value: "\(quantity) · 成本 \(cost)")
                KeyValueRow(key: "计划", value: "\(levels.count) 档")
                KeyValueRow(key: "复盘", value: Dates.day.string(from: Date().addingTimeInterval(30 * 86_400)))
                Text("保存后持仓、计划、流水和复盘待办会一起创建。").font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
        }
    }

    private func quantityBinding(_ level: Binding<PlanLevel>) -> Binding<String> {
        Binding(
            get: { level.wrappedValue.quantity.map { String(format: "%.0f", $0) } ?? "" },
            set: { level.wrappedValue.quantity = Double($0) })
    }

    private func save() {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { error = "代码不能为空"; return }
        guard parsedQty > 0, parsedCost > 0 else { error = "数量和成本必须大于 0"; return }
        do {
            var notes: [String] = []
            if !thesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.append(thesis) }
            if !invalidation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes.append("失效条件：\(invalidation)")
            }
            if let stop = Double(stopPrice), stop > 0 { notes.append("止损价：\(Fmt.price(stop))") }
            if let budget = Double(riskBudget), budget > 0 { notes.append("单笔风险预算：\(Fmt.money(budget))") }
            let description = notes.joined(separator: "\n")
            _ = try state.addPosition(code: code, name: name, quantity: parsedQty, cost: parsedCost,
                                      source: source, unit: unit, plan: levels,
                                      description: description.isEmpty ? nil : description,
                                      nextReview: Dates.day.string(from: Date().addingTimeInterval(30 * 86_400)),
                                      market: selectedMarket, quoteKey: selectedQuoteKey)
            state.load()
            state.toastText = "持仓已保存"
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImportWizardView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pickedURL: URL?
    @State private var mapping: [String: String] = [:]
    @State private var includeNeedsReview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("导入交割单").font(.system(size: 15, weight: .semibold))
                Text("CSV · UTF-8/GBK").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CardBox {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pickedURL?.lastPathComponent ?? "还没有选择文件")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("选择券商导出的 CSV；导入前会预览、去重，并可按批次回滚。")
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button("选择文件") { chooseFile() }.controlSize(.small)
                        }
                    }
                    if let error = state.importError {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                    }
                    if state.importLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在解析文件…").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                        }
                    }
                    if let preview = state.importPreview {
                        CardBox {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("字段映射").font(.system(size: 12, weight: .semibold))
                                ForEach(ImportService.fields.filter(\.required)) { field in
                                    HStack(spacing: 8) {
                                        Text(field.label).font(.system(size: 11))
                                            .frame(width: 80, alignment: .leading)
                                        Picker("", selection: Binding(
                                            get: { mapping[field.key] ?? preview.mapping[field.key] ?? "" },
                                            set: { mapping[field.key] = $0 }
                                        )) {
                                            Text("未选择").tag("")
                                            ForEach(preview.headers, id: \.self) { header in
                                                Text(header).tag(header)
                                            }
                                        }.labelsHidden().frame(width: 220)
                                        if ImportService.missingRequired(
                                            mergedMapping(preview)).contains(where: { $0.key == field.key }) {
                                            Text("必填").font(.system(size: 9.5)).foregroundStyle(Theme.amber)
                                        }
                                        Spacer()
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button("重新预览") {
                                        guard let url = pickedURL else { return }
                                        state.previewImport(url: url, mapping: mergedMapping(preview))
                                    }.controlSize(.small)
                                }
                            }
                        }
                    }
                    if let preview = state.importPreview {
                        HStack(spacing: 10) {
                            StatCard(label: "总行数", value: "\(preview.summary.total)", detail: nil)
                            StatCard(label: "可导入", value: "\(preview.summary.ready)", detail: nil, tint: Theme.down)
                            StatCard(label: "重复", value: "\(preview.summary.duplicate)", detail: nil)
                            StatCard(label: "待确认", value: "\(preview.summary.needsReview)", detail: nil, tint: Theme.amber)
                            StatCard(label: "错误", value: "\(preview.summary.errors)", detail: nil, tint: Theme.up)
                        }
                        VStack(spacing: 0) {
                            HStack {
                                Text("日期").frame(width: 90, alignment: .leading)
                                Text("代码").frame(width: 70, alignment: .leading)
                                Text("方向").frame(width: 45, alignment: .leading)
                                Text("数量").frame(width: 70, alignment: .trailing)
                                Text("价格").frame(width: 70, alignment: .trailing)
                                Text("状态").frame(maxWidth: .infinity, alignment: .trailing)
                            }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Theme.line.opacity(0.18))
                            ForEach(preview.rows.prefix(100)) { row in
                                HStack {
                                    Text(row.tradeTime).frame(width: 90, alignment: .leading)
                                    Text(row.code).frame(width: 70, alignment: .leading)
                                    Text(row.side == .buy ? "买入" : "卖出").frame(width: 45, alignment: .leading)
                                    Text(String(format: "%.0f", row.quantity)).frame(width: 70, alignment: .trailing)
                                    Text(price(row.price)).frame(width: 70, alignment: .trailing)
                                    Text(statusLabel(row.status)).foregroundStyle(statusColor(row.status))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }.font(.system(size: 10.5)).monospacedDigit()
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                Divider()
                            }
                        }
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                        if preview.summary.needsReview > 0 {
                            Toggle("金额不一致的行按数量×价格修正后导入", isOn: $includeNeedsReview)
                                .toggleStyle(.checkbox).font(.system(size: 10.5))
                        }
                        Text("导入会按成交时间重建持仓；重复行按成交编号或字段哈希跳过。非 CNY 行不会导入。")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                }
                .padding(18)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认导入") { state.commitImport(includeNeedsReview: includeNeedsReview) }
                    .buttonStyle(.borderedProminent)
                    .disabled({
                        guard let preview = state.importPreview else { return true }
                        return preview.summary.ready + (includeNeedsReview ? preview.summary.needsReview : 0) == 0
                    }())
            }.padding(14)
        }
        .frame(width: 860, height: 620)
        .onAppear {
            state.importPreview = nil
            state.importError = nil
        }
        .onChange(of: state.importPreview?.fileHash) { _ in
            mapping = state.importPreview?.mapping ?? [:]
        }
    }

    private func mergedMapping(_ preview: ImportPreview) -> [String: String] {
        var merged = preview.mapping
        for (key, value) in mapping where !value.isEmpty { merged[key] = value }
        return merged
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pickedURL = url
        mapping = [:]
        includeNeedsReview = false
        state.previewImport(url: url)
    }

    private func statusLabel(_ status: ImportRowStatus) -> String {
        switch status {
        case .ready: return "可导入"
        case .duplicate: return "重复"
        case .needsReview: return "待确认"
        case .error: return "错误"
        }
    }

    private func statusColor(_ status: ImportRowStatus) -> Color {
        switch status {
        case .ready: return Theme.down
        case .duplicate: return Theme.muted
        case .needsReview: return Theme.amber
        case .error: return Theme.up
        }
    }
}

private enum WatchMarket: String, CaseIterable, Identifiable {
    case stock, gold, fund, cmb, hk, us, index

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stock: return "A股 / ETF"
        case .gold: return "黄金"
        case .fund: return "场外基金"
        case .cmb: return "招行积存金"
        case .hk: return "港股"
        case .us: return "美股"
        case .index: return "指数"
        }
    }
    var source: QuoteSource {
        switch self {
        case .stock, .hk, .us, .index: return .eastmoney
        case .gold: return .sina
        case .fund: return .fund
        case .cmb: return .cmb
        }
    }
    var unit: UnitKind {
        switch self {
        case .stock, .hk, .us, .index: return .share
        case .gold, .cmb: return .gram
        case .fund: return .fund
        }
    }
    var instrumentMarket: InstrumentMarket {
        switch self {
        case .stock, .gold, .fund, .cmb: return .cn
        case .hk: return .hk
        case .us: return .us
        case .index: return .index
        }
    }
    init(source: QuoteSource) {
        switch source {
        case .eastmoney: self = .stock
        case .sina: self = .gold
        case .fund: self = .fund
        case .cmb: self = .cmb
        }
    }
    static func from(_ p: Position) -> WatchMarket {
        switch p.market {
        case .hk: return .hk
        case .us: return .us
        case .index: return .index
        case .cn: return WatchMarket(source: p.source)
        }
    }
}

struct WatchEditorSheet: View {
    @ObservedObject var state: AppState
    let watchId: Int64?
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var market: WatchMarket = .stock
    @State private var watchPrice = ""
    @State private var note = ""
    @State private var bulk = ""
    @State private var isBulk = false
    @State private var error = ""
    @State private var saving = false
    @State private var searchResult: SymbolSearchResult?
    @State private var quoteKey: String?
    @State private var confirmDiscard = false

    private var editing: Position? { watchId.flatMap { state.anyPosition(id: $0) } }
    private var dirty: Bool {
        if let p = editing {
            return name != p.name
                || watchPrice != (p.watchPrice.map { price($0) } ?? "")
                || note != (p.note ?? "")
        }
        return !code.isEmpty || !name.isEmpty || !watchPrice.isEmpty
            || !note.isEmpty || !bulk.isEmpty || searchResult != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editing == nil ? "添加观察" : "编辑观察 · \(editing?.name ?? "")")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    if dirty { confirmDiscard = true } else { dismiss() }
                } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }

            if editing == nil {
                Picker("", selection: $isBulk) {
                    Text("单个").tag(false)
                    Text("批量粘贴").tag(true)
                }.pickerStyle(.segmented).frame(width: 180)
            }

            ScrollView {
                if editing == nil && isBulk {
                    bulkForm
                } else {
                    singleForm
                }
            }

            if !error.isEmpty {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(editing == nil && isBulk ? "一行一条：代码[,关注价[,备注]]" : "观察不占用仓位，也不计入组合。")
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
                Spacer()
                Button("取消") { dismiss() }
                Button(editing == nil ? "保存观察" : "保存修改") {
                    if editing == nil && isBulk { saveBulk() } else { saveSingle() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
        .padding(16)
        .frame(width: 560, height: editing == nil && isBulk ? 520 : 460)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear(perform: prefill)
    }

    private var singleForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing == nil {
                SymbolSearchField(selection: $searchResult)
                    .onChange(of: searchResult) { result in
                        guard let result else { return }
                        code = result.code
                        name = result.name
                        quoteKey = result.quoteKey
                        switch result.instrumentMarket {
                        case .hk: market = .hk
                        case .us: market = .us
                        case .index: market = .index
                        case .cn: market = WatchMarket(source: result.source)
                        }
                    }
            }
            row("代码") {
                TextField("600000", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .disabled(editing != nil)
            }
            row("类型") {
                Picker("", selection: $market) {
                    ForEach(WatchMarket.allCases) { m in Text(m.title).tag(m) }
                }.labelsHidden().disabled(editing != nil)
            }
            row("名称") {
                HStack(spacing: 6) {
                    TextField("留空自动查询", text: $name).textFieldStyle(.roundedBorder)
                    Button("查询") { Task { await lookup() } }.controlSize(.small)
                }
            }
            row("关注价") {
                TextField("可选", text: $watchPrice).textFieldStyle(.roundedBorder)
            }
            row("备注") {
                TextField("关注理由 / 失效条件", text: $note).textFieldStyle(.roundedBorder)
            }
            Text("关注价可空；计划只允许买入档，数量可留空。已有持仓的代码不能重复观察。")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
        }
    }

    private var bulkForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("仅支持 A股 / ETF；名称留空会调用行情接口补齐。")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            TextEditor(text: $bulk)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
            Text("示例：601318,50.00,等季报确认")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                .frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func prefill() {
        guard let p = editing else { return }
        code = p.code
        name = p.name
        market = WatchMarket.from(p)
        quoteKey = p.quoteKey
        watchPrice = p.watchPrice.map { price($0) } ?? ""
        note = p.note ?? ""
    }

    private func lookup() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let found = await state.lookupName(code: trimmed, source: market.source) {
            name = found
        } else {
            error = "没有查到名称，保存时会用代码代替"
        }
    }

    private func parsePrice() -> Double? {
        let trimmed = watchPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: "")), value > 0 else {
            error = "关注价必须大于 0"
            return nil
        }
        return value
    }

    private func saveSingle() {
        error = ""
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { error = "代码不能为空"; return }
        let parsed = parsePrice()
        if !watchPrice.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil { return }
        saving = true
        Task {
            do {
                if let id = watchId {
                    try state.updateWatch(id: id, watchPrice: parsed,
                                          note: note.isEmpty ? nil : note,
                                          name: name)
                    state.toastText = "观察已更新"
                } else {
                    var finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalName.isEmpty {
                        finalName = market.instrumentMarket == .cn
                            ? (await state.lookupName(code: trimmedCode, source: market.source) ?? trimmedCode)
                            : trimmedCode
                    }
                    var key = quoteKey
                    if market.instrumentMarket == .us, key == nil {
                        key = await QuoteService.shared.resolveUSQuoteKey(symbol: trimmedCode)
                        if key == nil { throw StoreError.validation("没有找到该美股的行情") }
                    }
                    if market.instrumentMarket == .index, key == nil {
                        throw StoreError.validation("指数请从搜索结果选择")
                    }
                    _ = try state.addWatch(code: trimmedCode, name: finalName,
                                           source: market.source, unit: market.unit,
                                           watchPrice: parsed,
                                           note: note.isEmpty ? nil : note,
                                           market: market.instrumentMarket,
                                           quoteKey: key)
                    state.toastText = "已加入观察"
                }
                saving = false
                dismiss()
            } catch {
                saving = false
                self.error = error.localizedDescription
            }
        }
    }

    private func saveBulk() {
        error = ""
        let lines = bulk.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { error = "先粘贴至少一行代码"; return }
        saving = true
        Task {
            var added = 0
            var failures: [String] = []
            for line in lines {
                let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let rawCode = parts.first ?? ""
                guard !rawCode.isEmpty else { continue }
                let rawPrice = parts.count > 1 ? parts[1] : ""
                let rawNote = parts.count > 2 ? parts[2] : ""
                let parsedPrice = rawPrice.isEmpty ? nil : Double(rawPrice)
                let foundName = await state.lookupName(code: rawCode, source: .eastmoney) ?? rawCode
                do {
                    _ = try state.addWatch(code: rawCode, name: foundName,
                                           source: .eastmoney, unit: .share,
                                           watchPrice: parsedPrice,
                                           note: rawNote.isEmpty ? nil : rawNote)
                    added += 1
                } catch {
                    failures.append("\(rawCode)：\(error.localizedDescription)")
                }
            }
            saving = false
            if added > 0 {
                state.toastText = "新增 \(added) 个观察" + (failures.isEmpty ? "" : "，跳过 \(failures.count) 个")
                dismiss()
            } else {
                error = failures.prefix(3).joined(separator: "\n")
            }
        }
    }
}

struct ConvertWatchSheet: View {
    @ObservedObject var state: AppState
    let watchId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var cost = ""
    @State private var date = Dates.today()
    @State private var error = ""
    @State private var initialCost = ""
    @State private var confirmDiscard = false

    private var watch: Position? { state.anyPosition(id: watchId) }
    private var dirty: Bool { !quantity.isEmpty || cost != initialCost || date != Dates.today() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转为持仓 · \(watch?.name ?? "")")
                .font(.system(size: 15, weight: .semibold))
            HStack {
                Text("数量").font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 50, alignment: .leading)
                TextField("100", text: $quantity).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("成本").font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 50, alignment: .leading)
                TextField("买入价", text: $cost).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("日期").font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 50, alignment: .leading)
                TextField("YYYY-MM-DD", text: $date).textFieldStyle(.roundedBorder)
            }
            if let watch {
                let levels = state.plans[watch.id]?.levels.count ?? 0
                let metrics = state.metrics(for: watch.id).count
                Text("继承：\(levels) 个买入档 · \(metrics) 项指标")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            Text("保存后观察行删除，进入持仓详情；观察备注会保留。")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
            if !error.isEmpty { Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber) }
            Spacer()
            HStack {
                Spacer()
                Button("取消") {
                    if dirty { confirmDiscard = true } else { dismiss() }
                }
                Button("确认建仓") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear {
            if let watch, let q = state.quotes[watch.quoteCode] {
                cost = price(q.price)
                initialCost = cost
            }
        }
    }

    private func save() {
        guard let q = Double(quantity.replacingOccurrences(of: ",", with: "")), q > 0 else {
            error = "数量必须大于 0"; return
        }
        guard let c = Double(cost.replacingOccurrences(of: ",", with: "")), c > 0 else {
            error = "成本必须大于 0"; return
        }
        do {
            let p = try state.convertWatch(id: watchId, quantity: q, cost: c, openedAt: date)
            state.selectedPositionId = p.id
            state.showPositionDetail = true
            state.section = .positions
            state.toastText = "已转为持仓"
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SheetHost: View {
    @ObservedObject var state: AppState
    let sheet: AppState.ActiveSheet

    var body: some View {
        switch sheet {
        case .trade(let id): TradeSheet(state: state, positionId: id)
        case .clear(let id): ClearSheet(state: state, positionId: id)
        case .editPosition(let id): EditPositionSheet(state: state, positionId: id)
        case .editPlan(let id): PlanEditorSheet(state: state, positionId: id)
        case .drafts: DraftsSheet(state: state)
        case .memory(let id): MemorySheet(state: state, memoryId: id)
        case .importSheet: ImportWizardView(state: state)
        case .watchEditor(let id): WatchEditorSheet(state: state, watchId: id)
        case .convertWatch(let id): ConvertWatchSheet(state: state, watchId: id)
        }
    }
}

struct TradeSheet: View {
    @ObservedObject var state: AppState
    let positionId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var side: TradeSide = .buy
    @State private var quantity = ""
    @State private var priceText = ""
    @State private var fee = "0"
    @State private var date = Dates.today()
    @State private var levelId: String?
    @State private var note = ""
    @State private var error = ""
    @State private var initialPrice = ""
    @State private var confirmDiscard = false

    private var position: Position? { state.anyPosition(id: positionId) }
    private var dirty: Bool {
        !quantity.isEmpty || !note.isEmpty || fee != "0" || date != Dates.today()
            || levelId != nil || side != .buy || priceText != initialPrice
    }
    private var levels: [PlanLevel] {
        let done = state.executedLevels(for: positionId)
        return (state.plans[positionId]?.levels ?? []).filter {
            $0.kind.rawValue == side.rawValue && !done.contains($0.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("记一笔 · \(position?.name ?? "")").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    if dirty { confirmDiscard = true } else { dismiss() }
                } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            Picker("", selection: $side) {
                Text("买入").tag(TradeSide.buy)
                Text("卖出").tag(TradeSide.sell)
            }.pickerStyle(.segmented)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("数量").foregroundStyle(Theme.muted)
                    TextField("", text: $quantity).textFieldStyle(.roundedBorder)
                    Text("价格").foregroundStyle(Theme.muted)
                    TextField("", text: $priceText).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("费用").foregroundStyle(Theme.muted)
                    TextField("0", text: $fee).textFieldStyle(.roundedBorder)
                    Text("日期").foregroundStyle(Theme.muted)
                    TextField("YYYY-MM-DD", text: $date).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("档位").foregroundStyle(Theme.muted)
                    Picker("", selection: $levelId) {
                        Text("不关联（计划外）").tag(String?.none)
                        ForEach(levels) { level in
                            Text("\(level.kind.cn) \(price(level.price))").tag(String?.some(level.id))
                        }
                    }.labelsHidden()
                }
            }.font(.system(size: 11.5))
            TextField("备注", text: $note).textFieldStyle(.roundedBorder)
            if let p = position, let q = number(quantity), let px = number(priceText), q > 0, px > 0 {
                let after = side == .buy ? p.quantity + q : p.quantity - q
                let newCost = side == .buy
                    ? (p.quantity * p.avgCost + q * px + (Double(fee) ?? 0)) / max(after, 1)
                    : p.avgCost
                Text("持仓 \(Fmt.qty(p.quantity, unit: p.unit)) → \(Fmt.qty(after, unit: p.unit)) · 成本 \(price(p.avgCost)) → \(price(newCost))")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            if !error.isEmpty { Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber) }
            Spacer()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存成交") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 480, height: 420)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear {
            priceText = position.flatMap { state.quotes[$0.quoteCode] }.map { price($0.price) } ?? ""
            initialPrice = priceText
        }
        .onChange(of: side) { _ in
            levelId = nil
            error = ""
        }
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func save() {
        guard let q = number(quantity), q > 0 else { error = "数量必须大于 0"; return }
        guard let px = number(priceText), px > 0 else { error = "价格必须大于 0"; return }
        guard Dates.isDay(date) else { error = "成交日期格式应为 YYYY-MM-DD"; return }
        let feeValue: Double
        if fee.trimmingCharacters(in: .whitespaces).isEmpty {
            feeValue = 0
        } else if let parsed = number(fee), parsed >= 0 {
            feeValue = parsed
        } else {
            error = "手续费必须是非负数字"
            return
        }
        do {
            try state.recordTrade(id: positionId, side: side, quantity: q, price: px,
                                  fee: feeValue, levelId: levelId,
                                  note: note.isEmpty ? nil : note, occurredAt: date)
            state.toastText = "成交已记录"
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ClearSheet: View {
    @ObservedObject var state: AppState
    let positionId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var fee = "0"
    @State private var note = ""
    @State private var error = ""
    @State private var keepWatch = true
    @State private var initialPrice = ""
    @State private var confirmDiscard = false

    private var dirty: Bool { priceText != initialPrice || fee != "0" || !note.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("清仓 · \(state.anyPosition(id: positionId)?.name ?? "")")
                .font(.system(size: 15, weight: .semibold))
            TextField("清仓价格", text: $priceText).textFieldStyle(.roundedBorder)
            TextField("手续费", text: $fee).textFieldStyle(.roundedBorder)
            TextField("备注（为什么清仓）", text: $note).textFieldStyle(.roundedBorder)
            if let p = state.anyPosition(id: positionId), let px = Double(priceText) {
                let proceeds = px * p.quantity - (Double(fee) ?? 0)
                let realized = (px - p.avgCost) * p.quantity - (Double(fee) ?? 0)
                Text("预计净回款 \(money(proceeds)) · 已实现 \(signedMoney(realized))")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Toggle("清仓后保留观察", isOn: $keepWatch)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
            Text("保留未执行的买入档，关注价取本次卖出价；原持仓的复盘和历史都保留。")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
            if !error.isEmpty { Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber) }
            Spacer()
            HStack {
                Spacer()
                Button("取消") {
                    if dirty { confirmDiscard = true } else { dismiss() }
                }
                Button("确认清仓") { clear() }.buttonStyle(.borderedProminent)
                    .foregroundStyle(Theme.up)
            }
        }
        .padding(16)
        .frame(width: 460, height: 340)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear {
            if let p = state.anyPosition(id: positionId) {
                priceText = state.quotes[p.quoteCode].map { price($0.price) } ?? ""
                initialPrice = priceText
            }
        }
    }

    private func clear() {
        let px = Double(priceText.replacingOccurrences(of: ",", with: "")) ?? 0
        guard px > 0 else { error = "价格必须大于 0"; return }
        let feeValue: Double
        if fee.trimmingCharacters(in: .whitespaces).isEmpty {
            feeValue = 0
        } else if let parsed = Double(fee.replacingOccurrences(of: ",", with: "")), parsed >= 0 {
            feeValue = parsed
        } else {
            error = "手续费必须是非负数字"
            return
        }
        do {
            _ = try state.clearPosition(positionId: positionId, price: px,
                                        fee: feeValue,
                                        note: note.isEmpty ? nil : note)
            if keepWatch {
                let carryNote = [note.isEmpty ? nil : note,
                                 "\(Dates.today()) 以 \(price(px)) 清仓"]
                    .compactMap { $0 }
                    .joined(separator: "；")
                _ = try state.carryToWatch(positionId: positionId, watchPrice: px, note: carryNote)
                state.toastText = "已清仓，已保留观察"
            } else {
                state.toastText = "已清仓，复盘待办已创建"
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct EditPositionSheet: View {
    @ObservedObject var state: AppState
    let positionId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var cost = ""
    @State private var reason = ""
    @State private var error = ""
    @State private var initialQuantity = ""
    @State private var initialCost = ""
    @State private var confirmDiscard = false

    private var dirty: Bool {
        quantity != initialQuantity || cost != initialCost || !reason.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑持仓 · \(state.anyPosition(id: positionId)?.name ?? "")")
                .font(.system(size: 15, weight: .semibold))
            HStack {
                TextField("数量", text: $quantity).textFieldStyle(.roundedBorder)
                TextField("成本", text: $cost).textFieldStyle(.roundedBorder)
            }
            TextField("修正原因（改数量/成本时必填）", text: $reason).textFieldStyle(.roundedBorder)
            Text("日常买卖请用「记一笔」；修正会写入流水，不覆盖历史。")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
            if !error.isEmpty { Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber) }
            Spacer()
            HStack {
                Spacer()
                Button("取消") {
                    if dirty { confirmDiscard = true } else { dismiss() }
                }
                Button("保存") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 460, height: 280)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear {
            if let p = state.anyPosition(id: positionId) {
                quantity = String(format: "%.0f", p.quantity)
                cost = String(format: "%.2f", p.avgCost)
                initialQuantity = quantity
                initialCost = cost
            }
        }
    }

    private func save() {
        guard let q = Double(quantity), let c = Double(cost) else { error = "请输入有效数字"; return }
        do {
            try state.correctPosition(id: positionId, quantity: q, cost: c, reason: reason)
            state.toastText = "持仓已保存"
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct PlanEditorSheet: View {
    @ObservedObject var state: AppState
    let positionId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var levels: [PlanLevel] = []
    @State private var reviewDate = ""
    @State private var note = ""
    @State private var error = ""
    @State private var confirmDiscard = false

    private var isWatch: Bool { state.anyPosition(id: positionId)?.kind == .watch }
    private var dirty: Bool {
        let plan = state.plans[positionId]
        return levels != (plan?.levels ?? [])
            || note != (plan?.description ?? "")
            || reviewDate != (plan?.nextReview ?? "")
    }
    private var kinds: [PlanLevel.Kind] { isWatch ? [.buy] : PlanLevel.Kind.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑计划 · \(state.anyPosition(id: positionId)?.name ?? "")")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(isWatch ? "添加买入档" : "添加一档") {
                    levels.append(PlanLevel(price: 0, kind: .buy, quantity: nil, condition: ""))
                }.controlSize(.small)
                Button {
                    if dirty { confirmDiscard = true } else { dismiss() }
                } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            HStack {
                if !isWatch {
                    Text("下次复盘").font(.system(size: 11))
                    TextField("YYYY-MM-DD", text: $reviewDate).textFieldStyle(.roundedBorder).frame(width: 130)
                } else {
                    Text("观察阶段只设买入档，数量可留空").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
                TextField("说明", text: $note).textFieldStyle(.roundedBorder)
            }
            ScrollView {
                VStack(spacing: 5) {
                    ForEach($levels) { $level in
                        HStack(spacing: 6) {
                            Picker("", selection: $level.kind) {
                                ForEach(kinds, id: \.self) { k in
                                    Text(k.cn).tag(k)
                                }
                            }.labelsHidden().frame(width: 80)
                            TextField("价格", value: $level.price, format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 90)
                            TextField("数量", text: quantityBinding($level))
                                .textFieldStyle(.roundedBorder).frame(width: 90)
                            TextField("条件", text: $level.condition).textFieldStyle(.roundedBorder)
                            Button {
                                levels.removeAll { $0.id == level.id }
                            } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !error.isEmpty { Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.amber) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存计划") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 760, height: 560)
        .discardConfirmation(isDirty: dirty, isPresented: $confirmDiscard)
        .onAppear {
            if let plan = state.plans[positionId] {
                levels = plan.levels
                reviewDate = plan.nextReview ?? ""
                note = plan.description ?? ""
            }
        }
    }

    private func quantityBinding(_ level: Binding<PlanLevel>) -> Binding<String> {
        Binding(
            get: { level.wrappedValue.quantity.map { String(format: "%.0f", $0) } ?? "" },
            set: { level.wrappedValue.quantity = Double($0) })
    }

    private func save() {
        do {
            _ = try state.updatePlan(positionId: positionId, levels: levels,
                                     description: note.isEmpty ? nil : note,
                                     nextReview: isWatch ? nil : (reviewDate.isEmpty ? nil : reviewDate),
                                     note: "手动编辑", ifVersion: state.plans[positionId]?.version)
            state.toastText = "计划已保存"
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DraftsSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var applyTarget: DraftRecord?
    @State private var discardTarget: DraftRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("草稿中心").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            if state.drafts.isEmpty {
                EmptyState(icon: "doc.text", title: "没有草稿", detail: "外部 Agent 生成的计划草稿会出现在这里，确认后才写入。")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.drafts) { draft in
                            CardBox {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Pill(text: draft.status == "pending" ? "待确认" : draft.status == "applied" ? "已应用" : "已放弃",
                                             color: draft.status == "pending" ? Theme.amber : draft.status == "applied" ? Theme.down : Theme.muted)
                                        Text(draft.kind == "plan" ? "计划草稿" : draft.kind)
                                            .font(.system(size: 12, weight: .semibold))
                                        Spacer()
                                        Text(draft.createdAt.prefix(16)).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                                    }
                                    if draft.kind == "plan",
                                       let data = draft.payload.data(using: .utf8),
                                       let payload = try? JSONDecoder().decode(PlanDraftPayload.self, from: data) {
                                        Text(payload.description ?? "计划草稿").font(.system(size: 10.5))
                                            .foregroundStyle(Theme.muted).lineLimit(3)
                                        ForEach(Array(payload.levels.enumerated()), id: \.offset) { _, level in
                                            HStack {
                                                Text(level.kind).frame(width: 40, alignment: .leading)
                                                Text(price(level.price)).frame(width: 70, alignment: .leading)
                                                Text(level.quantity.map { Fmt.money($0) } ?? "—").frame(width: 70, alignment: .leading)
                                                Text(level.condition).foregroundStyle(Theme.muted)
                                                Spacer()
                                            }.font(.system(size: 10))
                                        }
                                        Text("基准 v\(draft.baseVersion ?? 0)").font(.system(size: 9)).foregroundStyle(Theme.faint)
                                    } else {
                                        Text(draft.payload).font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.muted).lineLimit(3)
                                    }
                                    if draft.status == "pending" {
                                        HStack {
                                            Button("应用") { applyTarget = draft }.controlSize(.small)
                                            Button("放弃") { discardTarget = draft }.controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .alert("应用这份草稿？", isPresented: Binding(
            get: { applyTarget != nil },
            set: { if !$0 { applyTarget = nil } })) {
            Button("取消", role: .cancel) { applyTarget = nil }
            Button("应用") {
                if let draft = applyTarget { state.applyPlanDraft(draft) }
                applyTarget = nil
            }
        } message: {
            if let draft = applyTarget {
                Text("将基于 v\(draft.baseVersion ?? 0) 写入新的计划版本。")
            }
        }
        .alert("放弃这份草稿？", isPresented: Binding(
            get: { discardTarget != nil },
            set: { if !$0 { discardTarget = nil } })) {
            Button("取消", role: .cancel) { discardTarget = nil }
            Button("放弃", role: .destructive) {
                if let draft = discardTarget {
                    do { try state.discardDraft(draft) }
                    catch { state.toastText = error.localizedDescription }
                }
                discardTarget = nil
            }
        }
    }
}

struct MemorySheet: View {
    @ObservedObject var state: AppState
    let memoryId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var confirmArchive = false

    var body: some View {
        let m = state.memories.first { $0.id == memoryId }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m?.title ?? "记忆").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭")
            }
            if let m {
                HStack { Pill(text: m.scope.rawValue, color: Theme.accent); Pill(text: m.kind.rawValue, color: Theme.amber) }
                Text(m.content).font(.system(size: 12))
                KeyValueRow(key: "置信度", value: "\(Int(m.confidence * 100))%")
                KeyValueRow(key: "证据", value: m.evidence)
                KeyValueRow(key: "更新时间", value: m.updatedAt)
                HStack {
                    Spacer()
                    Button("归档") { confirmArchive = true }
                    Button("关闭") { dismiss() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 480)
        .alert("归档这条记忆？", isPresented: $confirmArchive) {
            Button("取消", role: .cancel) {}
            Button("归档", role: .destructive) {
                guard let m else { return }
                do {
                    try state.store.archiveMemory(id: m.id)
                    state.loadV5()
                    dismiss()
                } catch { state.toastText = error.localizedDescription }
            }
        }
    }
}

