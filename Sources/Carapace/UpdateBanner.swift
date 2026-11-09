import SwiftUI
import CarapaceCore

/// 只负责观察 updater 并在需要时挂出横幅，避免父视图不刷新导致横幅不出现。
struct UpdateBannerHost: View {
    @ObservedObject var updater: UpdateController
    var compact = false

    var body: some View {
        if updater.isPresenting {
            UpdateBanner(updater: updater, compact: compact)
        }
    }
}

/// 更新横幅：显示「发现了什么、现在到哪一步、还剩多少」，并允许取消或立即开始。
struct UpdateBanner: View {
    @ObservedObject var updater: UpdateController
    var compact = false

    @ViewBuilder
    var body: some View {
        if updater.isPresenting {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if updater.phase.isBusy, canCancelInstall {
                        Button("取消") { updater.cancelInstall() }
                            .controlSize(.small)
                    } else if updater.pending != nil, !updater.phase.isBusy {
                        Button("立即更新") { updater.installPending() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("稍后") { updater.cancelPending() }
                            .controlSize(.small)
                        Button("跳过此版本") { updater.cancelPending(skip: true) }
                            .controlSize(.small)
                    } else if case .failed = updater.phase {
                        Button("关闭") { updater.cancelPending() }
                            .controlSize(.small)
                    }
                }
                Text(updater.statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = updater.downloadProgress, case .downloading = updater.phase {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: compact ? 240 : 320)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var canCancelInstall: Bool {
        switch updater.phase {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    private var icon: String {
        switch updater.phase {
        case .failed: return "exclamationmark.triangle"
        case .installing: return "arrow.triangle.2.circlepath"
        case .downloading, .verifying: return "arrow.down.circle"
        default: return updater.pending == nil ? "checkmark.circle" : "arrow.down.circle"
        }
    }

    private var tint: Color {
        if case .failed = updater.phase { return Theme.amber }
        return Theme.accent
    }

    private var title: String {
        switch updater.phase {
        case .checking: return "正在检查更新"
        case .downloading: return "正在下载 Carapace \(updater.pending?.version ?? "")"
        case .verifying: return "正在校验安装包"
        case .installing: return "正在安装 Carapace \(updater.pending?.version ?? "")"
        case .failed: return "更新没有完成"
        case .idle:
            if let pending = updater.pending { return "发现 Carapace \(pending.version)" }
            return ""
        }
    }
}