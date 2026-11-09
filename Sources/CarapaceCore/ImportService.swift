import Foundation
import CryptoKit

public struct ImportField: Identifiable, Sendable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var required: Bool

    public init(key: String, label: String, required: Bool = false) {
        self.key = key
        self.label = label
        self.required = required
    }
}

public struct ImportPreview: Sendable {
    public var rows: [ImportPreviewRow]
    public var summary: ImportSummary
    public var mapping: [String: String]
    public var fileHash: String
    public var headers: [String]

    public init(rows: [ImportPreviewRow], summary: ImportSummary,
                mapping: [String: String], fileHash: String, headers: [String]) {
        self.rows = rows
        self.summary = summary
        self.mapping = mapping
        self.fileHash = fileHash
        self.headers = headers
    }
}

public enum ImportError: LocalizedError {
    case unreadable
    case missingMapping(String)
    case noRows
    case commit(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取文件：请使用 UTF-8 或 GBK 编码的 CSV"
        case .missingMapping(let f): return "缺少必填映射：\(f)"
        case .noRows: return "文件里没有可导入的成交行"
        case .commit(let m): return "导入失败：\(m)"
        }
    }
}

public enum ImportService {
    public static let fields: [ImportField] = [
        ImportField(key: "trade_time", label: "成交日期", required: true),
        ImportField(key: "code", label: "证券代码", required: true),
        ImportField(key: "name", label: "证券名称"),
        ImportField(key: "side", label: "买卖方向", required: true),
        ImportField(key: "quantity", label: "成交数量", required: true),
        ImportField(key: "price", label: "成交价格", required: true),
        ImportField(key: "amount", label: "成交金额"),
        ImportField(key: "fee_commission", label: "佣金"),
        ImportField(key: "fee_stamp", label: "印花税"),
        ImportField(key: "fee_transfer", label: "过户费"),
        ImportField(key: "fee_other", label: "其他费用"),
        ImportField(key: "broker_trade_id", label: "成交编号"),
        ImportField(key: "order_id", label: "委托编号"),
        ImportField(key: "currency", label: "币种"),
        ImportField(key: "note", label: "备注")
    ]

    static let aliases: [String: [String]] = [
        "trade_time": ["成交日期", "发生日期", "交易日期", "日期", "成交时间", "trade_time", "date", "trade date"],
        "code": ["证券代码", "股票代码", "代码", "基金代码", "code", "symbol"],
        "name": ["证券名称", "股票名称", "名称", "基金名称", "name"],
        "side": ["买卖方向", "买卖标志", "操作", "方向", "side", "买卖"],
        "quantity": ["成交数量", "成交股数", "数量", "份额", "quantity", "qty"],
        "price": ["成交价格", "成交均价", "价格", "price"],
        "amount": ["成交金额", "发生金额", "金额", "amount"],
        "fee_commission": ["佣金", "手续费", "commission"],
        "fee_stamp": ["印花税", "stamp"],
        "fee_transfer": ["过户费", "transfer fee"],
        "fee_other": ["其他费用", "杂费", "other fee"],
        "broker_trade_id": ["成交编号", "合同编号", "流水号", "成交序号", "trade id"],
        "order_id": ["委托编号", "订单编号", "order id"],
        "currency": ["币种", "货币", "currency"],
        "note": ["备注", "摘要", "note", "memo"]
    ]

    public static func autoMapping(headers: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for field in fields {
            let candidates = aliases[field.key] ?? [field.key]
            if let match = headers.first(where: { header in
                let h = header.lowercased().replacingOccurrences(of: " ", with: "")
                return candidates.contains { alias in
                    let a = alias.lowercased().replacingOccurrences(of: " ", with: "")
                    return h == a || h.contains(a)
                }
            }) {
                out[field.key] = match
            }
        }
        return out
    }

    public static func missingRequired(_ mapping: [String: String]) -> [ImportField] {
        fields.filter { $0.required && mapping[$0.key] == nil }
    }

    public static func preview(data: Data, accountId: Int64,
                               store: Store,
                               mapping supplied: [String: String]? = nil,
                               allowMissing: Bool = false) throws -> ImportPreview {
        guard let text = CSVParser.decode(data) else { throw ImportError.unreadable }
        let table = CSVParser.parse(text)
        guard !table.rows.isEmpty else { throw ImportError.noRows }
        let mapping = supplied ?? autoMapping(headers: table.headers)
        if !allowMissing, let missing = missingRequired(mapping).first {
            throw ImportError.missingMapping(missing.label)
        }
        let fileHash = sha256(data)

        var rows: [ImportPreviewRow] = []
        for (i, rawRow) in table.rows.enumerated() {
            var dict: [String: String] = [:]
            for (j, header) in table.headers.enumerated() where j < rawRow.count {
                dict[header] = rawRow[j]
            }
            func value(_ key: String) -> String {
                guard let header = mapping[key] else { return "" }
                return dict[header]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            let code = normalizeCode(value("code"))
            let tradeTime = normalizeDate(value("trade_time"))
            let side = parseSide(value("side"))
            let quantity = parseNumber(value("quantity"))
            let price = parseNumber(value("price"))
            let amount = parseNumber(value("amount"))
            let commission = parseNumber(value("fee_commission"))
            let stamp = parseNumber(value("fee_stamp"))
            let transfer = parseNumber(value("fee_transfer"))
            let other = parseNumber(value("fee_other"))
            let feeTotal = commission + stamp + transfer + other
            let brokerTradeId = value("broker_trade_id")
            let currency = value("currency").isEmpty ? "CNY" : value("currency").uppercased()
            let name = value("name")
            let note = value("note")

            var status: ImportRowStatus = .ready
            var message = ""
            if code.isEmpty || tradeTime.isEmpty || side == nil || quantity <= 0 || price <= 0 {
                status = .error
                message = "缺少代码/日期/方向/数量/价格"
            } else if currency != "CNY" {
                status = .error
                message = "当前只支持 CNY 估值"
            } else if amount > 0 && abs(amount - quantity * price) > 0.02 {
                status = .needsReview
                message = "金额与数量×价格相差 \(String(format: "%.2f", abs(amount - quantity * price)))"
            }
            let dedupe = dedupeKey(accountId: accountId, brokerTradeId: brokerTradeId,
                                   tradeTime: tradeTime, code: code,
                                   side: side?.rawValue ?? "", quantity: quantity,
                                   price: price, amount: amount)
            if status == .ready, try store.executionExists(dedupeKey: dedupe) {
                status = .duplicate
                message = "已导入过，跳过"
            }
            rows.append(ImportPreviewRow(
                rowNumber: i + 2,
                tradeTime: tradeTime,
                code: code,
                name: name,
                side: side ?? .buy,
                quantity: quantity,
                price: price,
                amount: amount > 0 ? amount : quantity * price,
                feeTotal: feeTotal,
                currency: currency,
                brokerTradeId: brokerTradeId.isEmpty ? nil : brokerTradeId,
                dedupeKey: dedupe,
                status: status,
                message: message.isEmpty ? note : message,
                raw: dict
            ))
        }
        let summary = ImportSummary(
            total: rows.count,
            ready: rows.filter { $0.status == .ready }.count,
            duplicate: rows.filter { $0.status == .duplicate }.count,
            needsReview: rows.filter { $0.status == .needsReview }.count,
            errors: rows.filter { $0.status == .error }.count
        )
        return ImportPreview(rows: rows, summary: summary, mapping: mapping,
                             fileHash: fileHash, headers: table.headers)
    }

    public static func commit(preview: ImportPreview, accountId: Int64,
                              broker: String, fileName: String,
                              store: Store, mappingId: Int64? = nil,
                              includeNeedsReview: Bool = false) throws -> ImportResult {
        let ready = preview.rows.filter { $0.status == .ready }
        // 金额与数量×价格不一致的行：用户确认后按数量×价格修正导入。
        let reviewed = includeNeedsReview
            ? preview.rows.filter { $0.status == .needsReview && $0.currency == "CNY" }
            : []
        let importing = ready + reviewed
        guard !importing.isEmpty else { throw ImportError.noRows }
        let batch = try store.createImportBatch(
            accountId: accountId, broker: broker, fileName: fileName,
            fileHash: preview.fileHash, mappingId: mappingId, rowsTotal: preview.rows.count)

        do {
            var executions: [Execution] = []
            for row in importing {
                let correctedAmount = row.status == .needsReview
                    ? row.quantity * row.price : row.amount
                var e = Execution(
                    accountId: accountId,
                    batchId: batch.id,
                    brokerTradeId: row.brokerTradeId,
                    code: row.code,
                    name: row.name,
                    side: row.side,
                    quantity: row.quantity,
                    price: row.price,
                    amount: correctedAmount,
                    feeTotal: row.feeTotal,
                    currency: row.currency,
                    tradeTime: row.tradeTime,
                    source: "import",
                    dedupeKey: row.dedupeKey
                )
                e.id = try store.insertExecution(e, batchId: batch.id)
                executions.append(e)
            }
            let applied = try store.applyImportedTrades(executions, batchId: batch.id)
            let imported = applied.values.filter { $0 != nil }.count
            let skipped = applied.values.filter { $0 == nil }.count
                + preview.summary.duplicate
                + (includeNeedsReview ? 0 : preview.summary.needsReview)
            try store.updateImportBatch(id: batch.id, status: .committed,
                                        imported: imported, skipped: skipped,
                                        errors: preview.summary.errors, error: nil)
            let final = try store.importBatches(limit: 1).first ?? batch
            return ImportResult(batch: final, imported: imported, skipped: skipped,
                                needsReview: includeNeedsReview ? 0 : preview.summary.needsReview,
                                errors: preview.summary.errors)
        } catch {
            try? store.updateImportBatch(id: batch.id, status: .failed,
                                         imported: 0, skipped: 0, errors: preview.summary.errors,
                                         error: String(describing: error))
            throw ImportError.commit(String(describing: error))
        }
    }

    public static func rollback(batchId: Int64, store: Store) throws -> Int {
        try store.voidImportBatch(id: batchId)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func dedupeKey(accountId: Int64, brokerTradeId: String,
                          tradeTime: String, code: String, side: String,
                          quantity: Double, price: Double, amount: Double) -> String {
        let base: String
        if !brokerTradeId.isEmpty {
            base = "\(accountId)|id|\(brokerTradeId)"
        } else {
            base = "\(accountId)|\(tradeTime)|\(code)|\(side)|\(quantity)|\(price)|\(amount)"
        }
        return sha256(Data(base.utf8))
    }

    static func parseNumber(_ raw: String) -> Double {
        var s = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        guard let v = Double(s) else { return 0 }
        return negative ? -v : v
    }

    static func parseSide(_ raw: String) -> TradeSide? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("买") || s == "b" || s.contains("buy") || s.contains("证券买入") {
            return .buy
        }
        if s.contains("卖") || s == "s" || s.contains("sell") || s.contains("证券卖出") {
            return .sell
        }
        return nil
    }

    static func normalizeDate(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        if s.isEmpty { return "" }
        if s.count >= 10 { return String(s.prefix(10)) }
        return s
    }

    static func normalizeCode(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .uppercased()
        if let dot = s.firstIndex(of: ".") {
            let suffix = String(s[s.index(after: dot)...])
            if ["SH", "SZ", "BJ"].contains(suffix) {
                s = String(s[..<dot])
            }
        }
        return s
    }
}
