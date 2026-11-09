import Foundation
import CoreFoundation

public enum QuoteError: LocalizedError {
    case badURL
    case blocked(String)
    case http(Int)
    case decode
    case empty(String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "行情地址无效"
        case .blocked(let host): return "已阻止非行情域名：\(host)"
        case .http(let code): return "行情接口返回 \(code)"
        case .decode: return "行情解码失败"
        case .empty(let code): return "没有拿到 \(code) 的行情"
        }
    }
}

final class AllowlistProtocol: URLProtocol {
    static let hosts: Set<String> = ["push2.eastmoney.com", "hq.sinajs.cn", "suggest3.sinajs.cn"]
    private static let forward = URLSession(configuration: .default)
    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, Self.hosts.contains(host) else {
            client?.urlProtocol(self, didFailWithError: QuoteError.blocked(request.url?.host ?? "?"))
            return
        }
        dataTask = Self.forward.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}

public final class QuoteService: @unchecked Sendable {
    public static let shared = QuoteService()

    private let session: URLSession
    private let lock = NSLock()
    private var cache: [String: (quote: Quote, at: Date)] = [:]

    /// 招行积存金买卖点差（元/克），赎回价 = 沪金99 − 点差/2。
    /// 2026-03-23 起 5 元/克（买入端 +2、卖出端不变），2026-06-29 起两端各 2.5。
    /// 招行不定期调整，默认 5，可在设置里改。
    private var _cmbSpread: Double = 5

    public var cmbSpread: Double {
        get { lock.lock(); defer { lock.unlock() }; return _cmbSpread }
        set { lock.lock(); _cmbSpread = max(0, newValue); lock.unlock() }
    }

    private static let gbk = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [AllowlistProtocol.self]
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 12
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Carapace/\(CarapaceBuild.version) (macOS; personal use)",
            "Accept": "*/*"
        ]
        session = URLSession(configuration: cfg)
    }

    public func lastQuote(for code: String) -> Quote? {
        lock.lock(); defer { lock.unlock() }
        return cache[code.uppercased()]?.quote
    }

    /// 刷新节奏由 AppState 控制，这里不再做 TTL 判断。
    public func quote(for code: String) -> Quote? {
        lastQuote(for: code)
    }

    public func fetch(codes: [(code: String, source: QuoteSource)],
                      force: Bool = false) async throws -> [String: Quote] {
        let grouped = Dictionary(grouping: codes, by: { $0.source })
        var result: [String: Quote] = [:]

        for source in QuoteSource.allCases {
            guard let items = grouped[source], !items.isEmpty else { continue }
            var keys = items.map { $0.code.uppercased() }
            // 场外基金一天一个净值，同一天只用缓存，不重复请求；跨日再拉一次。
            if source == .fund {
                result.merge(fundCache(for: keys)) { _, new in new }
                keys = keys.filter { result[$0] == nil }
                if keys.isEmpty { continue }
            }
            let primary: [String: Quote]
            do {
                primary = try await fetch(keys: keys, source: source)
            } catch {
                primary = [:]
            }
            result.merge(primary) { _, new in new }
            let missing = keys.filter { result[$0] == nil }
            // 招行折算依赖沪金99、基金净值只有新浪有，都不能退到别家源。
            if !missing.isEmpty, source != .cmb, source != .fund {
                if let fallback = try? await fetch(keys: missing, source: source == .eastmoney ? .sina : .eastmoney) {
                    result.merge(fallback) { _, new in new }
                }
            }
            if keys.allSatisfy({ result[$0] == nil }) {
                throw QuoteError.empty(keys.joined(separator: ","))
            }
        }

        storeInCache(result)
        return result
    }

    public func fetch(positions: [Position], force: Bool = false) async throws -> [String: Quote] {
        try await fetch(codes: positions.map { ($0.quoteCode, $0.source) }, force: force)
    }

    public func lookupName(code: String, source: QuoteSource) async -> String? {
        guard let q = try? await fetch(codes: [(code, source)])[code.uppercased()] else {
            return nil
        }
        return q.name.isEmpty ? nil : q.name
    }

    /// 按代码、名称或拼音搜索标的；只保留 A股、场内基金和场外基金。
    /// 用新浪 suggest（无需 token），返回顺序即相关度。
    public func searchSymbols(_ keyword: String) async throws -> [SymbolSearchResult] {
        let input = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        var components = URLComponents(string: "https://suggest3.sinajs.cn/suggest/")
        components?.queryItems = [
            URLQueryItem(name: "type", value: ""),
            URLQueryItem(name: "key", value: input)
        ]
        guard let url = components?.url else { throw QuoteError.badURL }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        try check(response)
        return try Self.parseSymbolSearch(data)
    }

    /// 解析新浪 suggest：`name,type,code,symbol,name,...`，按 ";" 分行。
    /// 只保留 A股、场内 ETF/LOF 和场外基金；同代码优先场内。
    public static func parseSymbolSearch(_ data: Data) throws -> [SymbolSearchResult] {
        // 新浪 suggest 正常返回 GBK；单元测试用 UTF-8。先试 UTF-8，GBK 一般不是合法 UTF-8。
        guard let body = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: Self.gbk) else {
            throw QuoteError.decode
        }
        guard let first = body.firstIndex(of: "\""),
              let last = body.lastIndex(of: "\""), first < last else { return [] }
        let payload = String(body[body.index(after: first)..<last])
        guard !payload.isEmpty else { return [] }

        struct Entry {
            let result: SymbolSearchResult
            let exchangeTraded: Bool
        }
        var entries: [Entry] = []

        for raw in payload.split(separator: ";") {
            let f = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4 else { continue }
            let code = f[2]
            let symbol = f[3].lowercased()
            let name = (f.count > 4 && !f[4].isEmpty) ? f[4] : f[0]
            guard !code.isEmpty, !name.isEmpty else { continue }

            let source: QuoteSource
            let unit: UnitKind
            let market: String
            let instrumentMarket: InstrumentMarket
            let quoteKey: String?
            let exchangeTraded: Bool
            switch f[1] {
            case "11":
                if Self.isStockSymbol(symbol, code: code) {
                    source = .eastmoney
                    unit = .share
                    instrumentMarket = .cn
                    quoteKey = nil
                    exchangeTraded = true
                    market = symbol.hasPrefix("sh") ? "沪A" : symbol.hasPrefix("bj") ? "京A" : "深A"
                } else if let indexKey = Self.indexQuoteKey(symbol: symbol, code: code) {
                    source = .eastmoney
                    unit = .share
                    instrumentMarket = .index
                    quoteKey = indexKey
                    exchangeTraded = false
                    market = "指数"
                } else {
                    continue
                }
            case "203", "204":
                guard symbol.hasPrefix("sh") || symbol.hasPrefix("sz") else { continue }
                source = .eastmoney
                unit = .share
                instrumentMarket = .cn
                quoteKey = nil
                exchangeTraded = true
                market = "ETF / LOF"
            case "201":
                guard symbol.hasPrefix("of") else { continue }
                source = .fund
                unit = .fund
                instrumentMarket = .cn
                quoteKey = nil
                exchangeTraded = false
                market = "场外基金"
            case "25":
                guard symbol.hasPrefix("of") else { continue }
                source = .fund
                unit = .fund
                instrumentMarket = .cn
                quoteKey = nil
                exchangeTraded = false
                market = "QDII 基金"
            case "31":
                guard code.count == 5, code.allSatisfy(\.isNumber) else { continue }
                source = .eastmoney
                unit = .share
                instrumentMarket = .hk
                quoteKey = "116.\(code)"
                exchangeTraded = false
                market = "港股"
            case "41":
                let symbolUpper = symbol.uppercased()
                guard !symbolUpper.contains("."), !symbolUpper.isEmpty,
                      symbolUpper.allSatisfy({ $0.isLetter }) else { continue }
                source = .eastmoney
                unit = .share
                instrumentMarket = .us
                quoteKey = nil          // 保存前用 resolveUSQuoteKey 探测交易所
                exchangeTraded = false
                market = "美股"
            default:
                continue
            }
            entries.append(Entry(result: SymbolSearchResult(code: code, name: name,
                                                            market: market,
                                                            source: source, unit: unit,
                                                            instrumentMarket: instrumentMarket,
                                                            quoteKey: quoteKey),
                                 exchangeTraded: exchangeTraded))
        }

        // 同代码如果既有场内又有场外基金，优先场内（例如 510300 / 161725）。
        // 只对场外基金去重，指数和股票共用 000001 时必须都保留。
        let exchangeCodes = Set(entries.filter(\.exchangeTraded).map(\.result.code))
        var seen = Set<String>()
        var out: [SymbolSearchResult] = []
        for entry in entries {
            if entry.result.source == .fund && exchangeCodes.contains(entry.result.code) { continue }
            guard seen.insert(entry.result.id).inserted else { continue }
            out.append(entry.result)
        }
        return Array(out.prefix(12))
    }

    /// 上证指数 000xxx / 深证指数 399xxx；返回东方财富 secid。
    static func indexQuoteKey(symbol: String, code: String) -> String? {
        if symbol.hasPrefix("sh"), !(code.hasPrefix("6") || code.hasPrefix("9")) {
            return "1.\(code)"
        }
        if symbol.hasPrefix("sz"), code.hasPrefix("399") {
            return "0.\(code)"
        }
        return nil
    }

    /// 剔除指数、B 股等：沪市只认 6/9 开头，深市只认 000/001/002/003/300/301。
    static func isStockSymbol(_ symbol: String, code: String) -> Bool {
        if symbol.hasPrefix("sh") { return code.hasPrefix("6") || code.hasPrefix("9") }
        if symbol.hasPrefix("sz") {
            return ["000", "001", "002", "003", "300", "301"].contains { code.hasPrefix($0) }
        }
        if symbol.hasPrefix("bj") { return code.hasPrefix("4") || code.hasPrefix("8") }
        return false
    }

    /// 当天已经取过的基金净值，直接复用缓存（场外基金一天一个净值）。
    private func fundCache(for keys: [String]) -> [String: Quote] {
        let day = Self.cmbDayKey(Date())
        lock.lock(); defer { lock.unlock() }
        var out: [String: Quote] = [:]
        for key in keys {
            if let entry = cache[key], Self.cmbDayKey(entry.at) == day {
                out[key] = entry.quote
            }
        }
        return out
    }

    private func storeInCache(_ result: [String: Quote]) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        for (key, quote) in result { cache[key] = (quote, now) }
    }

    // MARK: - 东方财富

    private func fetch(keys: [String], source: QuoteSource) async throws -> [String: Quote] {
        switch source {
        case .eastmoney: return try await fetchEastmoney(codes: keys)
        case .sina: return try await fetchSina(codes: keys)
        case .cmb: return try await fetchCMB(codes: keys)
        case .fund: return try await fetchSinaFund(codes: keys)
        }
    }

    /// 场外基金净值：新浪 `list=f_<代码>`，字段为
    /// 名称, 单位净值, 累计净值, 前一日单位净值, 净值日期, 规模。
    private func fetchSinaFund(codes: [String]) async throws -> [String: Quote] {
        let symbols = codes.map { "f_\($0.lowercased())" }.joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(symbols)") else {
            throw QuoteError.badURL
        }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        try check(response)

        guard let body = String(data: data, encoding: Self.gbk)
            ?? String(data: data, encoding: .utf8) else {
            throw QuoteError.decode
        }

        let wanted = Set(codes.map { $0.uppercased() })
        var out: [String: Quote] = [:]
        for raw in body.split(separator: ";") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("var hq_str_f_"),
                  let eq = line.firstIndex(of: "="),
                  let first = line.firstIndex(of: "\""),
                  let last = line.lastIndex(of: "\""), first < last else { continue }
            let code = String(line[line.index(line.startIndex, offsetBy: 11)..<eq].dropFirst(2))
            let f = String(line[line.index(after: first)..<last]).components(separatedBy: ",")
            guard f.count >= 5,
                  let nav = Double(f[1]), nav > 0 else { continue }
            let prev = Double(f[3]) ?? nav
            guard wanted.contains(code.uppercased()) else { continue }
            out[code.uppercased()] = Quote(code: code.uppercased(), name: f[0],
                                           price: nav, prevClose: prev > 0 ? prev : nav,
                                           time: f[4], source: .fund)
        }
        if out.isEmpty { throw QuoteError.empty(symbols) }
        return out
    }

    /// 招行积存金不对外提供实时接口（官方接口需鉴权），按协议以 Au99.99 为基准加减点差折算。
    /// 实时买入价（客户买入，招行 App 主展示的价）= 基准 + 点差/2；
    /// 实时卖出价（客户卖出/赎回，持仓金额和收益按它算）= 基准 − 点差/2。
    /// 招行的「今日收益」从当日 00:00 起算，所以昨收不能用新浪的日盘收盘价，
    /// 这里用本地记录的跨日收盘价（夜盘连续交易，约等于 00:00 价）当基准。
    private func fetchCMB(codes: [String]) async throws -> [String: Quote] {
        let base = try await fetchSina(codes: ["AU9999"])
        guard let gold = base["AU9999"] else { throw QuoteError.empty("AU9999") }
        let half = cmbSpread / 2
        let buy = gold.price + half
        let sell = max(0, gold.price - half)
        let prevSell = cmbDayBaseline(current: sell)
        var out: [String: Quote] = [:]
        // 只有黄金标的能套折算价，别的代码一律不返回。
        for code in codes where code.uppercased().contains("AU") {
            out[code.uppercased()] = Quote(code: code.uppercased(), name: "\(gold.name)（招行）",
                                           price: buy, prevClose: prevSell + half,
                                           time: gold.time, source: .cmb,
                                           sellPrice: sell, prevSellPrice: prevSell)
        }
        if out.isEmpty { throw QuoteError.empty(codes.joined(separator: ",")) }
        return out
    }

    /// 招行口径的当日基准：跨日时沿用上一段行情的最后一笔（夜盘连续到 02:00，约等于 00:00 价）。
    /// 当天首次取价前没有任何记录时，退化用当前价，今日收益从 0 开始。
    private func cmbDayBaseline(current: Double) -> Double {
        let defaults = CarapaceDefaults.store
        let day = Self.cmbDayKey(Date())
        var baseline = defaults.object(forKey: "cmbDayOpen:\(day)") as? Double
        if baseline == nil {
            baseline = defaults.object(forKey: "cmbLastPrice") as? Double
        }
        defaults.set(current, forKey: "cmbLastPrice")
        if defaults.object(forKey: "cmbDayOpen:\(day)") == nil, let baseline {
            defaults.set(baseline, forKey: "cmbDayOpen:\(day)")
        }
        // 只保留最近 7 天的基准，避免键无限累积。
        let prefix = "cmbDayOpen:"
        let cutoff = Self.cmbDayKey(Date().addingTimeInterval(-7 * 86_400))
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let value = String(key.dropFirst(prefix.count))
            if value < cutoff { defaults.removeObject(forKey: key) }
        }
        return baseline ?? current
    }

    private static func cmbDayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = MarketHours.zone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func fetchEastmoney(codes: [String]) async throws -> [String: Quote] {
        let pairs = codes.map { (key: $0.uppercased(), secid: Self.eastmoneySecid($0)) }
        let keyBySecid = Dictionary(uniqueKeysWithValues: pairs.map { ($0.secid, $0.key) })
        return try await fetchEastmoney(keys: pairs.map(\.secid), keyFor: { keyBySecid[$0] })
    }

    /// 指数条用 secid 直接取数：上证 000001 和股票 000001 代码相同，不能按代码做 key。
    public func fetchIndices(_ indices: [MarketIndex] = MarketIndex.panel) async throws -> [String: Quote] {
        let result = try await fetchEastmoney(keys: indices.map(\.secid), keyFor: { $0 })
        storeInCache(result)
        return result
    }

    /// 探测美股交易所：105 = 纳斯达克，106 = 纽交所，107 = 美交所。
    public func resolveUSQuoteKey(symbol: String) async -> String? {
        let code = symbol.uppercased()
        let secids = ["105", "106", "107"].map { "\($0).\(code)" }
        guard let result = try? await fetchEastmoney(keys: secids, keyFor: { $0 }),
              !result.isEmpty else { return nil }
        return result.keys.sorted().first
    }

    private func fetchEastmoney(keys list: [String],
                                keyFor: @escaping (String) -> String?) async throws -> [String: Quote] {
        let secids = list.joined(separator: ",")
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")
        components?.queryItems = [
            URLQueryItem(name: "secids", value: secids),
            URLQueryItem(name: "fields", value: "f1,f2,f3,f12,f13,f14,f18,f124")
        ]
        guard let url = components?.url else { throw QuoteError.badURL }

        var req = URLRequest(url: url)
        req.setValue("https://quote.eastmoney.com", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        try check(response)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let diff = body["diff"] as? [[String: Any]] else {
            throw QuoteError.decode
        }

        var out: [String: Quote] = [:]
        for item in diff {
            guard let code = item["f12"] as? String,
                  let raw = Self.number(item["f2"]), raw > 0 else { continue }
            let decimals = Int(Self.number(item["f1"]) ?? 2)
            let scale = pow(10, Double(decimals))
            let price = raw / scale
            let prev = (Self.number(item["f18"]) ?? 0) / scale
            let name = item["f14"] as? String ?? code
            let stamp = Self.number(item["f124"])
                .map { Date(timeIntervalSince1970: $0) }
                .map(Self.timeString) ?? ""
            let market = Int(Self.number(item["f13"]) ?? 0)
            let secid = "\(market).\(code.uppercased())"
            let key = keyFor(secid) ?? code.uppercased()
            out[key] = Quote(code: code, name: name, price: price,
                             prevClose: prev, time: stamp, source: .eastmoney)
        }

        if out.isEmpty { throw QuoteError.empty(secids) }
        return out
    }

    private static func eastmoneySecid(_ code: String) -> String {
        let c = code.uppercased()
        if c.contains(".") { return c }
        if c == "AU9999" { return "118.AU9999" }
        if c.hasPrefix("6") || c.hasPrefix("5") || c.hasPrefix("9") { return "1.\(c)" }
        return "0.\(c)"
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = MarketHours.zone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - 新浪

    private func fetchSina(codes: [String]) async throws -> [String: Quote] {
        let symbols = codes.map(Self.sinaSymbol).joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(symbols)") else {
            throw QuoteError.badURL
        }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        try check(response)

        guard let body = String(data: data, encoding: Self.gbk)
            ?? String(data: data, encoding: .utf8) else {
            throw QuoteError.decode
        }

        var out: [String: Quote] = [:]
        for raw in body.split(separator: ";") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = line.firstIndex(of: "="), line.hasPrefix("var hq_str_"),
                  let first = line.firstIndex(of: "\""),
                  let last = line.lastIndex(of: "\""), first < last else { continue }

            let symbol = String(line[line.index(line.startIndex, offsetBy: 11)..<eq])
            let payload = String(line[line.index(after: first)..<last])
            if payload.isEmpty { continue }
            let f = payload.components(separatedBy: ",")

            let isGold = symbol.hasPrefix("gds_")
            let code = isGold
                ? String(symbol.dropFirst(4))
                : String(symbol.dropFirst(2))

            let quote: Quote?
            if isGold {
                guard f.count >= 14,
                      let price = Double(f[0]), price > 0,
                      let prev = Double(f[7]) else { continue }
                let stamp = f[12].isEmpty ? f[6] : "\(f[12]) \(f[6])"
                quote = Quote(code: code, name: f[13], price: price, prevClose: prev,
                              time: stamp, source: .sina)
            } else {
                guard f.count >= 32,
                      let price = Double(f[3]), price > 0,
                      let prev = Double(f[2]) else { continue }
                quote = Quote(code: code, name: f[0], price: price, prevClose: prev,
                              time: "\(f[30]) \(f[31])", source: .sina)
            }
            if let quote { out[code.uppercased()] = quote }
        }

        if out.isEmpty { throw QuoteError.empty(symbols) }
        return out
    }

    private static func sinaSymbol(_ code: String) -> String {
        let c = code.uppercased()
        if c == "AU9999" { return "gds_AU9999" }
        if c.hasPrefix("5") || c.hasPrefix("6") || c.hasPrefix("9") { return "sh\(c)" }
        if c.hasPrefix("4") || c.hasPrefix("8") { return "bj\(c)" }
        return "sz\(c)"
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw QuoteError.http(http.statusCode)
        }
    }
}
