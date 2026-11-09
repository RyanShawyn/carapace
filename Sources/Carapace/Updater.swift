import Foundation
import AppKit
import CryptoKit
import CarapaceCore

enum UpdatePhase: Equatable {
    case idle
    case checking
    case downloading
    case verifying
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing: return true
        case .idle, .failed: return false
        }
    }
}

enum UpdateError: LocalizedError {
    case noRelease
    case noAsset
    case noChecksum
    case checksum(expected: String, actual: String)
    case download(Int)
    case mount
    case badBundle
    case versionMismatch(expected: String, actual: String)
    case signature
    case noPermission(String)
    case command(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noRelease: return "获取最新版本失败"
        case .noAsset: return "该版本没有 dmg 安装包"
        case .noChecksum: return "安装包缺少 SHA-256 校验值，已拒绝更新"
        case .checksum(let expected, let actual):
            return "安装包校验失败（期望 \(expected.prefix(12))…，实际 \(actual.prefix(12))…）"
        case .download(let code): return "下载失败（HTTP \(code)）"
        case .mount: return "无法挂载 dmg"
        case .badBundle: return "dmg 里没有有效的 Carapace.app"
        case .versionMismatch(let expected, let actual):
            return "dmg 版本 \(actual) 与发布版本 \(expected) 不一致"
        case .signature: return "新 App 签名校验失败，未替换"
        case .noPermission(let path): return "\(path) 不可写，无法替换 App"
        case .command(let text): return "命令失败：\(text)"
        case .cancelled: return "已取消更新"
        }
    }
}

/// 更新源；放在类型外，避免非隔离的 Asset 引用 @MainActor 静态属性。
enum UpdateSource {
    static let repo = "RyanShawyn/carapace"
}

struct UpdateRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let id: Int
        let name: String
        let browserDownloadURL: String
        let size: Int
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case id, name, size, digest
            case browserDownloadURL = "browser_download_url"
        }

        var url: URL? { URL(string: browserDownloadURL) }

        /// github.com 的 releases/download 直链会偶发 504；API 资产端点会直接 302 到 CDN，更稳。
        var apiURL: URL? {
            URL(string: "https://api.github.com/repos/\(UpdateSource.repo)/releases/assets/\(id)")
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
    }

    var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V")
            ? String(tagName.dropFirst()) : tagName
    }

    var dmg: Asset? { assets.first { $0.name.lowercased().hasSuffix(".dmg") } }
    var checksumAsset: Asset? { assets.first { $0.name.lowercased().hasSuffix(".sha256") } }
}

/// 应用内更新：检查公开的 releases 仓库，下载、校验、退出后由 helper 替换并重启。
@MainActor
final class UpdateController: ObservableObject {
    static let repo = UpdateSource.repo
    static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var latest: UpdateRelease?
    /// 已发现但还没开始安装的版本。
    @Published private(set) var pending: UpdateRelease?
    /// 自动更新的倒计时秒数；用户可取消。
    @Published private(set) var countdown: Int?
    /// 下载进度 0...1；未知时为 nil。
    @Published private(set) var downloadProgress: Double?
    /// 用户手动点了「检查更新」；用于在手动检查时也显示顶部进度。
    @Published private(set) var checkingManually = false
    /// 用户选择跳过的版本；自动检查不再提示，手动检查仍可更新。
    @Published private(set) var skippedVersion: String?
    @Published private(set) var lastCheck: Date? {
        didSet { CarapaceDefaults.store.set(lastCheck, forKey: "lastUpdateCheck") }
    }
    /// 自动检查（默认开）：启动时和每 24 小时检查，有新版本只提示。
    @Published var autoCheck: Bool {
        didSet {
            CarapaceDefaults.store.set(autoCheck, forKey: "autoCheck")
            if autoCheck { schedule() } else { timer?.invalidate() }
        }
    }
    /// 自动安装（默认关）：发现新版本后倒计时自动替换。
    @Published var autoUpdate: Bool {
        didSet {
            CarapaceDefaults.store.set(autoUpdate, forKey: "autoUpdate")
            if !autoUpdate {
                countdownTimer?.invalidate()
                countdownTimer = nil
                countdown = nil
            }
        }
    }
    @Published var relaunchAfterUpdate: Bool {
        didSet { CarapaceDefaults.store.set(relaunchAfterUpdate, forKey: "relaunchAfterUpdate") }
    }

    private var timer: Timer?
    private var countdownTimer: Timer?
    private var busy = false
    private var logHandle: FileHandle?
    private var cancelRequested = false

    init() {
        let defaults = CarapaceDefaults.store
        autoCheck = defaults.object(forKey: "autoCheck") as? Bool ?? true
        // 默认只提示，不自动替换正在运行的 App。
        autoUpdate = defaults.object(forKey: "autoUpdate") as? Bool ?? false
        relaunchAfterUpdate = defaults.object(forKey: "relaunchAfterUpdate") as? Bool ?? true
        skippedVersion = defaults.string(forKey: "skippedUpdateVersion")
        if let stored = defaults.object(forKey: "lastUpdateCheck") as? Date { lastCheck = stored }
    }

    var currentVersion: String { AppVersion.short }

    var statusText: String {
        switch phase {
        case .idle:
            if pending != nil {
                if let countdown { return "\(countdown) 秒后自动更新，可取消" }
                return "可以现在更新，或稍后再说"
            }
            if let lastCheck {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                return "上次检查 \(formatter.string(from: lastCheck))"
            }
            return "尚未检查"
        case .checking: return "正在检查…"
        case .downloading:
            if let downloadProgress {
                return "正在下载 \(pending?.version ?? "更新")… \(Int(downloadProgress * 100))%"
            }
            return "正在下载 \(pending?.version ?? "更新")…"
        case .verifying: return "正在校验安装包…"
        case .installing:
            let version = pending?.version ?? "更新"
            return relaunchAfterUpdate
                ? "正在安装 \(version)，随后重启…"
                : "正在安装 \(version)，完成后请手动打开"
        case .failed(let message): return "更新失败：\(message)"
        }
    }

    var isPresenting: Bool {
        if pending != nil { return true }
        switch phase {
        case .checking: return checkingManually
        case .downloading, .verifying, .installing, .failed: return true
        default: return false
        }
    }

    /// 启动时调用：全自动模式下延迟检查，之后每 24 小时检查一次。
    func start() {
        guard autoCheck else { return }
        schedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.check(manual: false)
        }
    }

    func check(manual: Bool, force: Bool = false) {
        guard !busy else { return }
        // 自动更新不在模态窗/编辑表单打开时打断用户；下一个周期再试。
        if !manual, NSApp.modalWindow != nil { return }
        busy = true
        checkingManually = manual
        phase = .checking
        Task { [weak self] in
            guard let self else { return }
            defer { self.checkingManually = false }
            do {
                let release = try await self.fetchLatest()
                self.lastCheck = Date()
                self.latest = release
                self.phase = .idle

                let newer = force || UpdateVersion.isNewer(release.version, than: self.currentVersion)
                guard newer else {
                    if manual { self.inform("已是最新版本",
                                             "当前 \(self.currentVersion)，最新 \(release.version)。") }
                    self.busy = false
                    return
                }
                if !manual, !force, release.version == self.skippedVersion {
                    self.busy = false
                    return
                }
                self.pending = release
                self.phase = .idle
                self.busy = false
                self.notifyAvailable(release)
                if !manual, self.autoUpdate { self.startCountdown() }
                return
            } catch {
                self.phase = .failed(error.localizedDescription)
                if manual { self.inform("检查更新失败", error.localizedDescription) }
            }
            self.busy = false
        }
    }

    // MARK: - Pending update

    /// 自动更新先倒计时 10 秒，用户可以在横幅里取消。
    private func startCountdown() {
        countdownTimer?.invalidate()
        countdown = 10
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                guard let value = self.countdown else { timer.invalidate(); return }
                if value <= 1 {
                    // 没有可见窗口或正在编辑时，倒计时停在 1 秒，等用户回到界面。
                    guard self.canInstallNow() else {
                        self.countdown = 1
                        return
                    }
                    timer.invalidate()
                    self.countdown = nil
                    self.installPending()
                } else {
                    self.countdown = value - 1
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func installPending() {
        guard let release = pending, !busy, canInstallNow() else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
        cancelRequested = false
        busy = true
        Task { [weak self] in
            guard let self else { return }
            await self.install(release, manual: false)
            self.busy = false
        }
    }

    func cancelPending(skip: Bool = false) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
        if skip, let version = pending?.version {
            skippedVersion = version
            CarapaceDefaults.store.set(version, forKey: "skippedUpdateVersion")
        }
        pending = nil
        phase = .idle
    }

    func cancelInstall() {
        guard phase.isBusy else { return }
        cancelRequested = true
    }

    private func canInstallNow() -> Bool {
        guard NSApp.modalWindow == nil else { return false }
        if NSApp.windows.contains(where: { $0.isVisible && $0.attachedSheet != nil }) { return false }
        // 没有任何可见窗口时横幅不可见，自动安装会变成无提示退出。
        return NSApp.windows.contains { $0.isVisible && $0.contentViewController != nil }
    }

    private func notifyAvailable(_ release: UpdateRelease) {
        NotificationService.shared.send(
            id: "update-available-\(release.version)",
            title: "Carapace \(release.version) 可用",
            body: autoUpdate ? "10 秒后自动更新，打开 App 可以取消。" : "打开 App，在更新横幅里确认。",
            enabled: CarapaceDefaults.notifyEnabled(.update)
                && (CarapaceDefaults.store.object(forKey: "systemNotifications") as? Bool ?? false))
    }

    // MARK: - Network

    private func fetchLatest() async throws -> UpdateRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else {
            throw UpdateError.noRelease
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Carapace/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.noRelease
        }
        return try JSONDecoder().decode(UpdateRelease.self, from: data)
    }

    /// API 资产端点优先，浏览器直链兜底：两者走的是不同链路，直链 504 时 API 仍可用。
    private func remoteURLs(for asset: UpdateRelease.Asset) -> [URL] {
        var urls: [URL] = []
        if let api = asset.apiURL { urls.append(api) }
        if let direct = asset.url, direct != asset.apiURL { urls.append(direct) }
        return urls
    }

    private func request(for remote: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: remote)
        request.timeoutInterval = timeout
        request.setValue("Carapace/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if remote.host == "api.github.com" {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private func download(_ asset: UpdateRelease.Asset, to url: URL) async throws {
        let remotes = remoteURLs(for: asset)
        guard !remotes.isEmpty else { throw UpdateError.noAsset }

        downloadProgress = 0
        defer { downloadProgress = nil }

        var lastError: Error = UpdateError.noAsset
        for remote in remotes {
            do {
                try await downloadOnce(remote, asset: asset, to: url)
                return
            } catch {
                if case UpdateError.cancelled = error { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    private func downloadOnce(_ remote: URL, asset: UpdateRelease.Asset, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = UpdateDownloadDelegate(
                destination: url,
                onProgress: { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value }
                },
                completion: { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                })
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.attach(session)
            session.downloadTask(with: request(for: remote, timeout: 60)).resume()
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue
        if let size, asset.size > 0, size != asset.size {
            throw UpdateError.command("下载大小不一致（\(size) / \(asset.size)）")
        }
    }

    private func expectedChecksum(for release: UpdateRelease) async throws -> String {
        if let digest = release.dmg?.digest, !digest.isEmpty {
            return digest.replacingOccurrences(of: "sha256:", with: "").lowercased()
        }
        guard let asset = release.checksumAsset else { throw UpdateError.noChecksum }
        for remote in remoteURLs(for: asset) {
            guard let (data, response) = try? await URLSession.shared.data(
                    for: request(for: remote, timeout: 20)),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
            let text = String(data: data, encoding: .utf8) ?? ""
            guard let match = text.range(of: "[0-9a-fA-F]{64}", options: .regularExpression) else {
                continue
            }
            return String(text[match]).lowercased()
        }
        throw UpdateError.noChecksum
    }

    // MARK: - Install

    private func install(_ release: UpdateRelease, manual: Bool) async {
        var mountPoint: URL?
        do {
            guard let asset = release.dmg else { throw UpdateError.noAsset }
            let expected = try await expectedChecksum(for: release)
            guard expected.count == 64 else { throw UpdateError.noChecksum }

            phase = .downloading
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("Carapace-\(release.version)-\(UUID().uuidString).dmg")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try await download(asset, to: temporary)
            if cancelRequested { throw UpdateError.cancelled }

            phase = .verifying
            let actual = try Self.sha256(of: temporary)
            guard actual == expected else {
                throw UpdateError.checksum(expected: expected, actual: actual)
            }

            let mount = try Self.mount(temporary)
            mountPoint = mount
            let source = mount.appendingPathComponent("Carapace.app")
            guard let newVersion = Self.bundleVersion(source) else { throw UpdateError.badBundle }
            guard newVersion == release.version else {
                throw UpdateError.versionMismatch(expected: release.version, actual: newVersion)
            }
            try Self.verifySignature(source)
            if cancelRequested { throw UpdateError.cancelled }

            phase = .installing
            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app" else {
                throw UpdateError.command("只能从安装包运行更新（当前 \(target.path)）")
            }
            let parent = target.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parent.path) else {
                throw UpdateError.noPermission(parent.path)
            }

            let staging = parent.appendingPathComponent(".Carapace.update-\(UUID().uuidString)")
            let backup = parent.appendingPathComponent(".Carapace.old-\(UUID().uuidString)")
            try Self.ditto(source, to: staging)
            Self.stripQuarantine(staging)
            if cancelRequested { throw UpdateError.cancelled }

            Self.detach(mount)
            mountPoint = nil

            let helper = try Self.writeHelper(target: target, staging: staging,
                                              backup: backup,
                                              relaunch: relaunchAfterUpdate)
            try launchHelper(helper)

            NotificationService.shared.send(
                id: "update-\(release.version)",
                title: "Carapace 正在更新到 \(release.version)",
                body: relaunchAfterUpdate ? "安装完成后会自动重启。" : "安装完成后请手动打开。",
                enabled: CarapaceDefaults.notifyEnabled(.update)
                    && (CarapaceDefaults.store.object(forKey: "systemNotifications") as? Bool ?? false))
            CarapaceDefaults.store.set(release.version, forKey: "updatedToVersion")

            try await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)
        } catch {
            if let mountPoint { Self.detach(mountPoint) }
            if let updateError = error as? UpdateError, case .cancelled = updateError {
                cancelRequested = false
                pending = nil
                phase = .idle
                return
            }
            cancelRequested = false
            phase = .failed(error.localizedDescription)
            if manual { inform("更新失败", error.localizedDescription) }
        }
    }

    // MARK: - Helpers

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(manual: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func inform(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func launchHelper(_ url: URL) throws {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Carapace", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("update.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        logHandle = handle

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
    }

    private static func writeHelper(target: URL, staging: URL, backup: URL,
                                    relaunch: Bool) throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("carapace-update-\(UUID().uuidString).sh")
        let reopen = relaunch ? "open \(quote(target.path))" : "true"
        let body = """
        #!/bin/sh
        set -u
        unset CARAPACE_UPDATE_FORCE CARAPACE_UPDATE_CHECK
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        if [ -d \(quote(target.path)) ]; then
          mv \(quote(target.path)) \(quote(backup.path)) || exit 1
        fi
        if mv \(quote(staging.path)) \(quote(target.path)); then
          xattr -dr com.apple.quarantine \(quote(target.path)) >/dev/null 2>&1 || true
          rm -rf \(quote(backup.path))
          \(reopen)
        else
          [ -d \(quote(backup.path)) ] && mv \(quote(backup.path)) \(quote(target.path))
          exit 1
        fi
        rm -f \(quote(script.path))
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func bundleVersion(_ app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func mount(_ dmg: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil",
                             ["attach", "-nobrowse", "-readonly", "-plist", dmg.path])
        guard let object = try? PropertyListSerialization.propertyList(from: output, format: nil),
              let dict = object as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else {
            throw UpdateError.mount
        }
        for entity in entities {
            if let path = entity["mount-point"] as? String, !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }
        throw UpdateError.mount
    }

    private static func detach(_ mount: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
    }

    private static func ditto(_ source: URL, to destination: URL) throws {
        _ = try run("/usr/bin/ditto", [source.path, destination.path])
    }

    private static func stripQuarantine(_ app: URL) {
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
    }

    private static func verifySignature(_ app: URL) throws {
        do {
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError.signature
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.command("\(tool) \(arguments.joined(separator: " "))")
        }
        return data
    }
}
private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private let completion: (Result<Void, Error>) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var finished = false

    init(destination: URL,
         onProgress: @escaping (Double) -> Void,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.completion = completion
    }

    func attach(_ session: URLSession) { self.session = session }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(UpdateError.download(http.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(())) }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        completion(result)
    }
}
