import Foundation
import os

/// NSLock 保護記憶體紀錄與時間格式器，供背景探索與 MainActor 共用。
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()

    private let capacity = 400

    private let lock = NSLock()
    private let started = ProcessInfo.processInfo.systemUptime

    private let logger = Logger(subsystem: "dev.local.galaxybudscontrol", category: "connection")

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var lines: [String] = []

    /// 寫入 private 系統日誌與有界記憶體，診斷模式另輸出至 stderr。
    ///
    /// - Parameters:
    ///   - message: 延後建立的診斷文字，寫入 private 日誌與本機記憶體。
    func log(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .private)")
        lock.lock()
        let line = "[\(formatter.string(from: Date()))] \(text)"
        // stderr 輸出限定使用者明確啟動的診斷模式，通常使用保留 private 系統日誌。
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            fputs(line + "\n", stderr)
        }
        lines.append(line)
        // 固定容量限制本機記憶體，較舊事件從頭移除。
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        lock.unlock()
    }

    /// 產出包含環境與裝置摘要的本機診斷文字。
    ///
    /// - Parameters:
    ///   - deviceSummary: 由呼叫端提供的裝置資料摘要，匯出前應檢查識別與序號。
    /// - Returns: App 環境、裝置摘要與記憶體日誌組成的診斷文字。
    func export(deviceSummary: String) -> String {
        lock.lock()
        let body = lines.joined(separator: "\n")
        lock.unlock()

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        return """
            \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galaxy Buds") \(version) (\(build))
            macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
            Uptime \(Int(ProcessInfo.processInfo.systemUptime - started))s
            \(deviceSummary)

            \(body)
            """
    }

}
