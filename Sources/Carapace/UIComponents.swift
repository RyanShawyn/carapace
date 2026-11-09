import SwiftUI
import CarapaceCore

extension Theme {
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    static var sidebar: Color { Color(nsColor: .underPageBackgroundColor) }
    static var muted: Color { Color(nsColor: .secondaryLabelColor) }
    static var faint: Color { Color(nsColor: .tertiaryLabelColor) }
    static var up: Color { Color(nsColor: .systemRed) }
    static var down: Color { Color(nsColor: .systemGreen) }
    static var amber: Color { Color(nsColor: .systemOrange) }
    static var accentSoft: Color { Theme.accent.opacity(0.10) }
    static var line: Color { Color(nsColor: .separatorColor) }
}

func marketBadge(_ market: InstrumentMarket) -> String {
    switch market {
    case .cn: return ""
    case .hk: return "港"
    case .us: return "美"
    case .index: return "指"
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.bottom, 14)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
            if let detail {
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// 代码/名称/拼音搜索：输入后列出可选标的，选中再填代码和名称。
struct SymbolSearchField: View {
    @Binding var selection: SymbolSearchResult?
    var placeholder = "输入代码、名称或拼音"
    var holdingsOnly = false
    @State private var query = ""
    @State private var results: [SymbolSearchResult] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var visibleResults: [SymbolSearchResult] {
        holdingsOnly ? results.filter(\.canHold) : results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                if searching {
                    ProgressView().controlSize(.small)
                }
                if selection != nil {
                    Button {
                        selection = nil
                        query = ""
                        results = []
                        searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.soft)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(focused ? Theme.accent : Theme.line, lineWidth: 1))

            if let selection {
                HStack(spacing: 6) {
                    Text(selection.name).font(.system(size: 11.5, weight: .semibold))
                    Text(selection.code).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                    Pill(text: selection.market, color: Theme.accent)
                    Spacer()
                }
            }

            if focused && !visibleResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(visibleResults.prefix(8)) { result in
                            Button { choose(result) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.name).font(.system(size: 12, weight: .medium))
                                        Text(result.code).font(.system(size: 10)).foregroundStyle(Theme.faint)
                                    }
                                    Spacer()
                                    Text(result.market).font(.system(size: 9.5)).foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 210)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            } else if focused && !query.trimmingCharacters(in: .whitespaces).isEmpty && !searching {
                if let searchError {
                    Text("搜索失败：\(searchError)")
                        .font(.system(size: 10)).foregroundStyle(Theme.amber)
                } else {
                    Text(holdingsOnly && !results.isEmpty
                         ? "港美股和指数请用「添加观察」"
                         : "没有找到，可以直接输入代码")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
            }
        }
        .onChange(of: query) { value in schedule(value) }
        .onAppear {
            // Sheet 打开后直接可以输入，不用先点一下搜索框。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func schedule(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { selection = nil }
        guard !trimmed.isEmpty else {
            results = []
            searching = false
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            searching = true
            searchError = nil
            do {
                let found = try await QuoteService.shared.searchSymbols(trimmed)
                if Task.isCancelled { return }
                results = found
            } catch {
                if Task.isCancelled { return }
                results = []
                searchError = error.localizedDescription
            }
            searching = false
        }
    }

    private func choose(_ result: SymbolSearchResult) {
        selection = result
        query = ""
        results = []
        searchError = nil
        focused = false
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(34)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}

struct CardBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(key).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer(minLength: 10)
            Text(value).font(.system(size: 11.5)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.primary.opacity(0.88))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .clipShape(Capsule())
            .padding(.bottom, 18)
    }
}

func money(_ v: Double) -> String { Fmt.money(v) }
func price(_ v: Double) -> String { Fmt.price(v) }
func signedMoney(_ v: Double) -> String { Fmt.signedMoney(v) }
func pct(_ v: Double) -> String { Fmt.pct(v) }


/// 表单有未保存修改时拦截 Esc/关闭，并给一个明确的放弃确认。
struct DiscardConfirmation: ViewModifier {
    let isDirty: Bool
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty)
            .alert("放弃未保存的修改？", isPresented: $isPresented) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { dismiss() }
            }
    }
}

extension View {
    func discardConfirmation(isDirty: Bool, isPresented: Binding<Bool>) -> some View {
        modifier(DiscardConfirmation(isDirty: isDirty, isPresented: isPresented))
    }
}

extension PlanLevel.Kind {
    var cn: String {
        switch self {
        case .buy: return "买入"
        case .sell: return "卖出"
        case .stop: return "停止买入"
        }
    }
}
