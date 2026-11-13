import SwiftUI
import AppKit
import CarapaceCore

struct SettingsViewV5: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader("设置", subtitle: "自动化、通知、数据与更新")
                Picker("", selection: $state.settingsTab) {
                    ForEach(SettingsTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).padding(.bottom, 12)

                switch state.settingsTab {
                case .general: GeneralSettingsView(state: state)
                case .automation: AutomationSettingsView(state: state)
                case .notify: NotificationSettingsView(state: state)
                case .data: DataSettingsView(state: state)
                case .update: UpdateSettingsView(updater: state.updater)
                case .about: AboutSettingsView()
                }
            }
            .padding(20)
        }
        .background(Theme.panel)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("在菜单栏显示图标", isOn: Binding(
                        get: { state.showMenuBarIcon },
                        set: { visible in
                            state.showMenuBarIcon = visible
                            if !visible {
                                state.toastText = "菜单栏图标已隐藏；可在 App 菜单或 设置 → 通用 恢复"
                            }
                        }))
                    Text("隐藏后菜单栏不再显示乌龟；持仓提醒仍会写入通知列表并弹系统通知。恢复方式：主窗口「Carapace」菜单 → 显示菜单栏图标，或启动 App 时按住 Option。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 11.5))
            }
        }
    }
}

struct AutomationSettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动化只做读取、整理和草稿").font(.system(size: 12, weight: .semibold))
                    Text("持仓和计划的写入仍需要一次确认；交易类草稿不会自动应用。")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
            }
            CardBox {
                VStack(alignment: .leading, spacing: 9) {
                    Text("已接线").font(.system(size: 12, weight: .semibold))
                    Toggle("后台行情刷新", isOn: $state.backgroundCheck)
                    HStack {
                        Text("刷新间隔").font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $state.backgroundMinutes) {
                            ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { value in
                                Text("每 \(Int(value)) 分钟").tag(value)
                            }
                        }.labelsHidden().frame(width: 110)
                        .disabled(!state.backgroundCheck)
                    }
                    Toggle("计划到期自动创建复盘", isOn: $state.autoReview)
                }
                .font(.system(size: 11.5))
            }
            CardBox {
                Text("交割单导入、计划写入和成交记录都保持手动确认；草稿由外部 Agent 生成，在「草稿中心」确认后才写入。")
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct NotificationSettingsView: View {
    @ObservedObject var state: AppState
    @State private var authStatus = "检查中…"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("系统通知", isOn: $state.systemNotifications)
                    Toggle("静默菜单栏标记", isOn: $state.muted)
                    Toggle("免打扰 22:30–07:30", isOn: $state.quietHours)
                    Text("价格提醒只在穿越未执行档位时触发；免打扰期间不发送系统通知，菜单栏和面板内的提醒仍然保留。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 11.5))
            }
            CardBox {
                HStack {
                    Text("系统通知权限").font(.system(size: 11.5))
                    Text(authStatus).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("打开系统设置") {
                        NotificationService.shared.openSystemSettings()
                    }.controlSize(.small)
                    Button("发送测试") {
                        guard state.systemNotifications else {
                            state.toastText = "先打开「系统通知」"
                            return
                        }
                        NotificationService.shared.send(id: "test-\(UUID().uuidString)",
                                                        title: "Carapace 测试通知",
                                                        body: "通知链路正常。",
                                                        enabled: true)
                        state.toastText = "已发送测试通知"
                    }.controlSize(.small)
                }
            }
            CardBox {
                VStack(alignment: .leading, spacing: 9) {
                    Text("分类开关").font(.system(size: 12, weight: .semibold))
                    ForEach(NotifyCategory.allCases, id: \.rawValue) { category in
                        Toggle(category.title, isOn: state.notifyBinding(category))
                    }
                    Text("关闭某一类后，该类提醒不再写入通知列表，也不再弹系统通知；已经产生的提醒保留。开关只影响之后新触发的提醒，菜单栏和总览里的提醒状态不受影响。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 11.5))
            }
        }
        .task { authStatus = await NotificationService.shared.authorizationDescription() }
        .onChange(of: state.systemNotifications) { _ in
            Task { authStatus = await NotificationService.shared.authorizationDescription() }
        }
    }
}

struct DataSettingsView: View {
    @ObservedObject var state: AppState
    @State private var message = ""
    @State private var accounts: [Account] = []
    @State private var broker = ""
    @State private var accountName = ""
    @State private var accountCurrency = "CNY"
    @State private var makeDefault = false
    @State private var rollbackTarget: ImportBatch?
    @State private var confirmClearMemory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountsCard
            importCard
            quoteCard
            databaseCard
            cleanupCard
        }
        .onAppear { reloadAccounts() }
        .alert("回滚这个导入批次？", isPresented: Binding(
            get: { rollbackTarget != nil },
            set: { if !$0 { rollbackTarget = nil } })) {
            Button("取消", role: .cancel) { rollbackTarget = nil }
            Button("回滚", role: .destructive) {
                if let batch = rollbackTarget { state.rollbackImport(batch) }
                rollbackTarget = nil
            }
        } message: {
            if let batch = rollbackTarget {
                Text("批次 #\(batch.id) · \(batch.fileName) · 导入 \(batch.rowsImported) 笔")
            }
        }
        .alert("清空全部记忆？", isPresented: $confirmClearMemory) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                for memory in state.memories { try? state.store.archiveMemory(id: memory.id) }
                state.loadV5()
                message = "已归档全部记忆"
            }
        } message: {
            Text("记忆会被归档，当前界面不再显示。")
        }
    }

    private var accountsCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                Text("账户").font(.system(size: 12.5, weight: .semibold))
                ForEach(accounts) { account in
                    HStack {
                        Text("\(account.broker) · \(account.name) · \(account.currency)")
                            .font(.system(size: 11))
                        if account.isDefault { Pill(text: "默认", color: Theme.accent) }
                        Spacer()
                    }
                }
                if accounts.isEmpty {
                    Text("还没有账户").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                Divider()
                HStack(spacing: 6) {
                    TextField("券商", text: $broker).textFieldStyle(.roundedBorder).frame(width: 90)
                    TextField("账户名", text: $accountName).textFieldStyle(.roundedBorder).frame(width: 110)
                    TextField("币种", text: $accountCurrency).textFieldStyle(.roundedBorder).frame(width: 60)
                    Toggle("默认", isOn: $makeDefault).toggleStyle(.checkbox).font(.system(size: 10.5))
                    Spacer()
                    Button("添加") {
                        do {
                            _ = try state.store.addAccount(
                                broker: broker.isEmpty ? "手工" : broker,
                                name: accountName.isEmpty ? "账户" : accountName,
                                currency: accountCurrency, isDefault: makeDefault)
                            broker = ""; accountName = ""; makeDefault = false
                            reloadAccounts()
                            message = "账户已添加"
                        } catch { message = error.localizedDescription }
                    }.controlSize(.small)
                }
                Text("默认账户用于交割单导入；手工建仓也会挂到默认账户。")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var importCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("交割单").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button("导入交割单") { state.showImport = true }.controlSize(.small)
                }
                if let batch = state.lastImport {
                    Text("最近批次 \(batch.fileName) · 导入 \(batch.rowsImported) 笔")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
                ForEach(state.importBatches.prefix(5)) { batch in
                    HStack {
                        Text("#\(batch.id) · \(batch.fileName) · \(batchStatus(batch.status)) · \(batch.rowsImported)/\(batch.rowsTotal)")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                        Spacer()
                        if batch.status == .committed {
                            Button("回滚") { rollbackTarget = batch }.controlSize(.small)
                        }
                    }
                }
                Text("导入前可预览和映射字段；重复行跳过，回滚后可重新导入。")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var quoteCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                Text("行情").font(.system(size: 12.5, weight: .semibold))
                HStack {
                    Text("东方财富间隔").font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $state.eastmoneyInterval) {
                        ForEach(QuoteSource.eastmoney.intervalChoices, id: \.self) {
                            Text("\(Int($0)) 秒").tag($0)
                        }
                    }.labelsHidden().frame(width: 100)
                }
                HStack {
                    Text("新浪间隔").font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $state.sinaInterval) {
                        ForEach(QuoteSource.sina.intervalChoices, id: \.self) {
                            Text("\(Int($0)) 秒").tag($0)
                        }
                    }.labelsHidden().frame(width: 100)
                }
                Divider()
                Toggle("显示指数条", isOn: $state.showIndexStrip)
                    .toggleStyle(.checkbox).font(.system(size: 11.5))
                HStack {
                    Text("港币兑人民币").font(.system(size: 11))
                    Spacer()
                    TextField("0.850", value: $state.hkdRate,
                              format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                    Button("按行情刷新") { state.refreshHKD(force: true) }
                        .controlSize(.small)
                }
                HStack {
                    Text("招行积存金点差").font(.system(size: 11))
                    Spacer()
                    Stepper(value: $state.cmbSpread, in: 0...20, step: 0.5) {
                        Text(String(format: "%.1f 元/克", state.cmbSpread))
                            .font(.system(size: 10.5, design: .monospaced))
                    }.frame(width: 150)
                }
                HStack {
                    Text("单只仓位上限").font(.system(size: 11))
                    Slider(value: $state.singlePositionLimit, in: 0.05...1.0, step: 0.05)
                        .frame(width: 140)
                    Text(Fmt.pctInt(state.singlePositionLimit * 100))
                        .font(.system(size: 10.5, design: .monospaced)).frame(width: 36)
                }
                Text("点差：现价 = 沪金99 + 点差/2，持仓金额 = 沪金99 − 点差/2。仓位超限会进入「需要你处理」和菜单栏提醒。")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var databaseCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                Text("数据库").font(.system(size: 12.5, weight: .semibold))
                Text(state.store.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted).textSelection(.enabled)
                HStack {
                    Button("打开文件夹") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: state.store.path)])
                    }
                    Button("备份") { backup() }
                    Button("校验并修复") {
                        do {
                            let fixed = try state.store.verifyAll()
                            message = "修复 \(fixed) 处"
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    Button("导出 CSV") { exportCSV() }
                }.controlSize(.small)
                if !message.isEmpty {
                    Text(message).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var cleanupCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("清理").font(.system(size: 12.5, weight: .semibold))
                HStack {
                    Button("删除遗留 AI 密钥") {
                        let removed = KeychainCleanup.purge()
                        message = removed == 0 ? "没有遗留密钥" : "已删除 \(removed) 个密钥"
                    }
                    Button("清空记忆") { confirmClearMemory = true }
                }.controlSize(.small)
            }
        }
    }

    private func reloadAccounts() {
        accounts = (try? state.store.accounts()) ?? []
    }

    private func batchStatus(_ status: ImportBatchStatus) -> String {
        switch status {
        case .preview: return "预览"
        case .committed: return "已导入"
        case .voided: return "已回滚"
        case .failed: return "失败"
        }
    }

    private func backup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "carapace-backup.sqlite3"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.store.backup(to: url)
            message = "已备份到 \(url.path)"
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "carapace-changes.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.store.exportChangesCSV(to: url)
            message = "已导出 \(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if updater.isPresenting {
                UpdateBanner(updater: updater)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
            }
            CardBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Carapace \(updater.currentVersion)")
                            .font(.system(size: 14, weight: .semibold))
                        Text(updater.statusText)
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if updater.phase.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("立即检查") { updater.check(manual: true) }
                            .controlSize(.small)
                    }
                }
            }
            CardBox {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("自动检查更新", isOn: $updater.autoCheck)
                    Toggle("发现新版本后自动安装", isOn: $updater.autoUpdate)
                    Toggle("更新后自动重启", isOn: $updater.relaunchAfterUpdate)
                    Text("默认启动时和每 24 小时检查一次，发现新版本只提示，由你点「立即更新」。开启自动安装后会倒计时 10 秒；窗口不可见或正在编辑时暂停。下载/安装阶段可取消。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 11.5))
            }
            CardBox {
                VStack(alignment: .leading, spacing: 5) {
                    Text("更新来源").font(.system(size: 12, weight: .semibold))
                    Text("github.com/\(UpdateController.repo) 的公开 Release。安装包必须通过 SHA-256 和版本校验，否则保留旧版本。")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    Text("安装包是 ad-hoc 签名：codesign 只校验完整性，不证明发布者身份。请以 Release 里的 SHA-256 为准。")
                        .font(.system(size: 10)).foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("更新只替换 App 本体；数据库、设置和通知在 ~/Library/Application Support/Carapace，不会被覆盖。")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Carapace \(AppVersion.short)").font(.system(size: 16, weight: .semibold))
                    Text("壳是仓位，缩回壳里是风控，慢是久期。")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("仅用于个人记录，不构成投资建议。不接券商、不下单。")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
            }
            CardBox {
                VStack(alignment: .leading, spacing: 4) {
                    KeyValueRow(key: "Bundle", value: "com.ryan.carapace")
                    KeyValueRow(key: "最低系统", value: "macOS 13")
                    KeyValueRow(key: "外部接口", value: "carapace CLI / skills")
                    KeyValueRow(key: "行情", value: "东方财富 / 新浪公开接口")
                    KeyValueRow(key: "数据", value: "本机 SQLite，目录 0700、文件 0600")
                }
            }
        }
    }
}
