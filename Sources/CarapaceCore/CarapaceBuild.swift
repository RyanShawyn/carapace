import Foundation

public enum CarapaceBuild {
    /// 打包进 App 后优先读 Info.plist，避免 CLI 版本与安装包版本脱节。
    public static let version: String = {
        let bundleURL = Bundle.main.bundleURL
        var candidates = [
            bundleURL.appendingPathComponent("Contents/Info.plist"),
            bundleURL.deletingLastPathComponent().appendingPathComponent("Info.plist")
        ]
        // 从仓库直接 swift run 时，向上找几级就能到仓库根目录的 Resources/Info.plist。
        var directory = bundleURL
        for _ in 0..<4 {
            directory = directory.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("Resources/Info.plist"))
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let short = plist["CFBundleShortVersionString"] as? String,
               !short.isEmpty {
                return short
            }
        }
        return "0.8.7"
    }()
    /// CLI 与 skill 之间的契约版本；不兼容时 skill 应停止并提示升级。
    public static let apiVersion = 1
}