import Foundation

/// 裝置驅動的 FOTA 交握、重傳、逾時及重新連線後的版本確認。
@Observable
@MainActor
final class FirmwareUpdater {
    /// 傳輸、安裝與重啟驗證各有獨立終態，成功須取得裝置版本回報。
    enum Phase: Equatable {
        case idle
        case preparing
        case sending(fraction: Double)
        case installing(percent: Int)
        case awaitingRestart
        case finished
        case failed(String)
    }

    // MARK: - 傳輸限制、相依與作業狀態

    private static let maxMTU = 650
    private static let sessionTimeout: TimeInterval = 20
    private static let stallTimeout: TimeInterval = 60

    var send: ((SppMessage) -> Bool)?
    private var binary: FirmwareBinary?
    private var mtu = 0
    private var mtuCeiling = FirmwareUpdater.maxMTU
    private var currentSegmentID = 0
    private var watchdog: Task<Void, Never>?

    private(set) var phase: Phase = .idle

    var isRunning: Bool {
        // 只有準備、傳輸、安裝與重啟等待階段持有更新作業。
        switch phase {
        // 準備、傳輸、安裝或重啟等待都屬於進行中的更新。
        case .preparing, .sending, .installing, .awaitingRestart: true
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .idle, .finished, .failed: false
        }
    }

    var canCancel: Bool {
        // 僅準備與傳輸階段允許取消，避免中斷裝置安裝。
        switch phase {
        // 準備或傳輸期間允許取消，裝置安裝期間維持等待。
        case .preparing, .sending: true
        // 未定義的控制或進度通知不改變更新狀態。
        default: false
        }
    }

    var isTransferring: Bool {
        isRunning && phase != .awaitingRestart
    }

    // MARK: - 更新生命週期

    /// 只在確認安裝後啟動，chunk 上限扣除封包與片段標頭。
    ///
    /// - Parameters:
    ///   - binary: 已通過機型、版本與區段校驗的完整韌體映像。
    ///   - channelMtu: RFCOMM 最大傳輸單位，單位為 bytes，資料片段再扣除封包開銷。
    func start(binary: FirmwareBinary, channelMtu: Int) {
        // 重入不覆寫已在執行的映像與協商狀態。
        guard !isRunning else { return }
        self.binary = binary
        // 原生 RFCOMM MTU 必須容納 11-byte 封包與片段標頭。
        guard channelMtu > 11 else {
            finish(success: false, message: String(localized: "The update failed."))
            return
        }
        // 資料片段上限同時受協定上限與原生通道 MTU 約束。
        mtuCeiling = min(Self.maxMTU, channelMtu - 11)
        mtu = 0
        currentSegmentID = 0
        // 保存待更新映像與協商快照後，才送出開啟工作階段。
        phase = .preparing
        DiagnosticsLog.shared.log(
            "fota: opening session for \(binary.buildName), \(binary.segments.count) segments, \(binary.totalSize) bytes, mtu ceiling \(mtuCeiling)"
        )
        // FOTA 開啟命令成功排入後，才等待裝置接受工作階段。
        guard send?(SppMessage(messageID: .fotaOpen, payload: binary.serializeTable())) == true else {
            finish(success: false, message: String(localized: "The update failed."))
            return
        }
        armWatchdog(
            Self.sessionTimeout,
            reason: String(
                localized: "The earbuds didn't start the update."))
    }

    /// 取消準備或傳輸並釋放本機作業，安裝與重啟階段保持等待。
    func cancel() {
        // 寫入安裝階段的中斷會影響裝置，取消限制在安全的傳輸階段。
        guard canCancel else { return }
        finish(success: false, message: String(localized: "The update was cancelled."))
    }

    /// 傳輸或安裝中斷線回報失敗，預期重啟保留版本確認狀態。
    func connectionLost() {
        // 重啟斷線是預期流程，其餘執行中的斷線屬於失敗。
        guard isRunning, phase != .awaitingRestart else { return }
        finish(
            success: false,
            message: String(
                localized: "The earbuds disconnected during the update."))
    }

    /// 重連後只有與選定映像相同的版本才能進入成功終態。
    ///
    /// - Parameters:
    ///   - version: 重新連線後從耳機讀取的完整韌體版本。
    func confirmInstalledVersion(_ version: String) {
        // 來源版本、送出完成及安裝回覆都不足以取代裝置版本確認。
        guard phase == .awaitingRestart, let binary, version == binary.buildName else { return }
        finish(success: true, message: nil)
    }

    // MARK: - 裝置事件與協商

    /// 已通過 SPP CRC 的 FOTA 訊息依命令分派，其他訊息保留給狀態服務。
    ///
    /// - Parameters:
    ///   - message: 有效且已通過 SPP CRC 的訊息，依命令解析或分派。
    func handle(_ message: SppMessage) {
        // 未啟動的 FOTA 事件不更動任何更新狀態。
        guard isRunning, let binary else { return }
        // 命令 ID 是穩定協定定義，機型與 MTU 差異已由注入配置提供。
        switch message.messageID {
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .fotaOpen:
            handleSession(message.payload)
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .fotaControl:
            handleControl(message.payload)
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .fotaDownloadData:
            handleDataRequest(message.payload, binary: binary)
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .fotaUpdate:
            handleUpdate(message.payload)
        // 閒置與完成或失敗狀態不持有進行中的更新。
        case .fotaResult:
            handleResult(message.payload)
        // 未定義的控制或進度通知不改變更新狀態。
        default:
            break
        }
    }

    /// 解析 FOTA_OPEN 結果碼，0 為接受，其他值結束本機更新流程。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    private func handleSession(_ payload: Data) {
        // 短回覆留待下一個有效事件，watchdog 仍保留失敗邊界。
        guard let code = payload.first else { return }
        DiagnosticsLog.shared.log("fota: session result \(code)")
        // 非零結果保留耳機提供的拒絕碼。
        guard code == 0 else {
            finish(
                success: false,
                message: String(
                    localized: "The earbuds refused to start the update.") + " (\(code))")
            return
        }
        armWatchdog(
            Self.sessionTimeout,
            reason: String(
                localized: "The earbuds stopped responding while preparing."))
    }

    /// 解析裝置提出的 MTU 與區段 ID，限制大小並回覆協商結果。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    private func handleControl(_ payload: Data) {
        // 控制訊息至少包含 ID 與 2-byte little-endian 參數。
        guard payload.count >= 3 else { return }
        let controlID = payload[payload.startIndex]
        let parameter = Int(payload[payload.startIndex + 1]) | (Int(payload[payload.startIndex + 2]) << 8)

        // 0 協商 MTU，1 指定區段，未識別的控制保持原狀。
        switch controlID {
        // 控制碼 0 協商可用 MTU，無效參數會結束作業。
        case 0:
            // MTU 必須能容納傳輸資料，無效大小結束更新。
            guard parameter > 0 else {
                finish(success: false, message: String(localized: "The update failed."))
                return
            }
            mtu = min(parameter, mtuCeiling)
            DiagnosticsLog.shared.log("fota: mtu proposed \(parameter), using \(mtu)")
            // MTU 協商回覆排入成功後，才繼續處理裝置要求。
            guard reply(controlID: 0, parameter: mtu) else { return }
        // 控制碼 1 選擇映像區段並回覆裝置。
        case 1:
            // 裝置要求的區段 ID 必須存在於已驗證映像。
            guard binary?.segment(id: parameter) != nil else {
                finish(
                    success: false,
                    message: String(localized: "The earbuds asked for a part the firmware doesn't contain."))
                return
            }
            currentSegmentID = parameter
            DiagnosticsLog.shared.log("fota: ready for segment \(parameter)")
            // 區段選擇回覆排入成功後，才等待資料要求。
            guard reply(controlID: 1, parameter: parameter) else { return }
        // 未定義的控制或進度通知不改變更新狀態。
        default:
            DiagnosticsLog.shared.log("fota: unknown control id \(controlID)")
            return
        }
        armWatchdog(
            Self.stallTimeout,
            reason: String(
                localized: "The earbuds stopped responding during the update."))
    }

    /// 回傳 little-endian 控制參數，排入失敗時停止本機流程並回傳 false。
    ///
    /// - Parameters:
    ///   - controlID: 裝置 FOTA 控制命令識別。
    ///   - parameter: FOTA 控制命令的整數參數，使用 little-endian 傳送。
    /// - Returns: 控制回覆成功排入時為 true，失敗時結束更新並回傳 false。
    @discardableResult private func reply(controlID: Int, parameter: Int) -> Bool {
        var payload = Data([UInt8(controlID)])
        payload.append(littleEndian: UInt16(truncatingIfNeeded: parameter))
        // 控制回覆寫入失敗時結束本機更新，避免假裝協商成功。
        guard send?(SppMessage(messageID: .fotaControl, payload: payload, isResponse: true)) == true else {
            finish(success: false, message: String(localized: "The update failed."))
            return false
        }
        return true
    }

    /// 每個要求包含 offset、NAK 與 chunk 數，回傳裝置要求的資料範圍。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    ///   - binary: 已通過機型、版本與區段校驗的完整韌體映像。
    private func handleDataRequest(_ payload: Data, binary: FirmwareBinary) {
        // 資料要求至少含 offset 與控制欄位，且 MTU 已協商完成。
        guard payload.count >= 5, mtu > 0 else { return }
        let base = payload.startIndex
        let offset =
            Int(payload[base]) | (Int(payload[base + 1]) << 8)
            | (Int(payload[base + 2]) << 16) | (Int(payload[base + 3] & 0x7F) << 24)
        let isNAK = (payload[base + 3] & 0x80) != 0
        let count = Int(payload[base + 4])

        // 目前區段須仍存在於映像，未知 ID 結束更新。
        guard let segment = binary.segment(id: currentSegmentID) else {
            finish(
                success: false,
                message: String(
                    localized: "The earbuds asked for a part the firmware doesn't contain."))
            return
        }
        // NAK 使用同一區段與 offset 重傳，保持裝置驅動的要求。
        if isNAK {
            DiagnosticsLog.shared.log("fota: NAK, resending segment \(currentSegmentID) from \(offset)")
        }

        phase = .sending(fraction: fractionSent(segment: segment, offset: offset, binary: binary))

        // 依裝置要求的 chunk 數逐片回覆，每片仍需檢查 offset 與資料範圍。
        for index in 0..<count {
            let chunkOffset = offset + mtu * index
            // 裝置要求越過尾端時結束本輪，避免讀取映像範圍外的資料。
            guard chunkOffset < segment.size else { break }
            let isLast = chunkOffset + mtu >= segment.size
            let chunkSize = isLast ? segment.size - chunkOffset : mtu

            var header = UInt32(chunkOffset) & 0x7FFF_FFFF
            // 片段 offset 的最高位表示後續仍有區段內容。
            if !isLast { header |= 0x8000_0000 }

            var body = Data()
            body.append(littleEndian: header)
            let start = segment.data.startIndex + chunkOffset
            body.append(segment.data[start..<(start + chunkSize)])

            // 每片寫入必須成功排入，失敗時立即停止傳輸。
            guard
                send?(
                    SppMessage(
                        messageID: .fotaDownloadData, payload: body,
                        isResponse: true, isFragment: true)) == true
            else {
                finish(success: false, message: String(localized: "The update failed."))
                return
            }
        }
        armWatchdog(
            Self.stallTimeout,
            reason: String(
                localized: "The earbuds stopped responding during the update."))
    }

    /// 以前置區段長度加裝置要求 offset 計算 0...1 顯示進度。
    ///
    /// - Parameters:
    ///   - segment: 目前傳輸的已驗證區段。
    ///   - offset: 裝置要求的區段內位元組位置。
    ///   - binary: 已通過機型、版本與區段校驗的完整韌體映像。
    /// - Returns: 目前傳輸顯示進度，範圍為 0...1，總長無效時為 0。
    private func fractionSent(segment: FirmwareSegment, offset: Int, binary: FirmwareBinary) -> Double {
        let precedingBytes = binary.segments
            .prefix { $0.id != segment.id }
            .reduce(0) { $0 + $1.size }
        let total = max(binary.totalSize, precedingBytes + segment.size)
        // 空映像無法計算進度，以 0 表示未傳輸。
        guard total > 0 else { return 0 }
        return min(1, Double(precedingBytes + offset) / Double(total))
    }

    /// 解析百分比與安裝狀態通知，接受成功後仍等待重啟版本驗證。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    private func handleUpdate(_ payload: Data) {
        // 更新事件必須同時提供狀態 ID 與值。
        guard payload.count >= 2 else { return }
        let base = payload.startIndex
        let updateId = payload[base]
        let value = Int(payload[base + 1])
        let resultCode = payload.count >= 3 ? Int(payload[base + 2]) : 0

        // 進度百分比與狀態完成採不同事件，避免進度 100 誤示成功。
        switch updateId {
        // 狀態碼 0 讀取裝置安裝通知與百分比。
        case 0:
            phase = .installing(percent: min(100, max(0, value)))
            armWatchdog(
                Self.stallTimeout,
                reason: String(
                    localized: "The earbuds stopped responding while installing."))
        // 狀態碼 1 判斷安裝結果，成功後等待重啟確認。
        case 1:
            _ = send?(SppMessage(messageID: .fotaUpdate, payload: Data([1]), isResponse: true))
            DiagnosticsLog.shared.log("fota: state change \(value), result \(resultCode)")
            // 安裝狀態成功只進入重啟等待，錯誤保留裝置結果碼。
            if value == 0 {
                awaitRestart()
            } else {
                // 安裝結果不成功時結束更新，保留裝置錯誤碼。
                finish(
                    success: false,
                    message: String(
                        localized: "The earbuds couldn't install the firmware.") + " (\(resultCode))")
            }
        // 未定義的控制或進度通知不改變更新狀態。
        default:
            break
        }
    }

    /// 回覆映像驗證結果，0 為裝置接受，真正成功由重連版本判定。
    ///
    /// - Parameters:
    ///   - payload: 已接收的原始位元組，格式、長度與欄位有效性由此解析入口檢查。
    private func handleResult(_ payload: Data) {
        _ = send?(SppMessage(messageID: .fotaResult, payload: Data([1]), isResponse: true))
        let result = payload.first.map(Int.init) ?? -1
        let errorCode = payload.count >= 2 ? Int(payload[payload.startIndex + 1]) : 0
        DiagnosticsLog.shared.log("fota: result \(result), error \(errorCode)")
        // 映像被接受後等待耳機重啟及實際版本，失敗保持可見結果。
        if result == 0 {
            awaitRestart()
        } else {
            // 裝置拒絕映像時回報失敗，避免進入重啟確認。
            finish(
                success: false,
                message: String(
                    localized: "The earbuds couldn't verify the firmware.") + " (\(errorCode))")
        }
    }

    // MARK: - 重啟、逾時與終止

    /// 傳輸驗證與安裝成功分開，耳機重啟後的版本必須與映像一致。
    private func awaitRestart() {
        phase = .awaitingRestart
        armWatchdog(
            Self.stallTimeout,
            reason: String(
                localized:
                    "Firmware upload was verified, but the installed version was not confirmed. Reconnect to check it.")
        )
    }

    /// 以秒為單位重設單一 watchdog，取消或作業終止後不再修改狀態。
    ///
    /// - Parameters:
    ///   - seconds: 允許等待裝置回覆的秒數。
    ///   - reason: 逾時或略過時的診斷原因，nil 代表沒有原因。
    private func armWatchdog(_ seconds: TimeInterval, reason: String) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            // 被下一個事件取代的 watchdog 不能覆寫較新的狀態。
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.finish(success: false, message: reason)
        }
    }

    /// 清除 watchdog、映像與協商快照，保留可見成功或失敗終態。
    ///
    /// - Parameters:
    ///   - success: 更新是否已通過重啟後版本確認。
    ///   - message: 結束作業的可見錯誤，nil 表示沒有錯誤訊息。
    private func finish(success: Bool, message: String?) {
        watchdog?.cancel()
        watchdog = nil
        binary = nil
        mtu = 0
        phase = success ? .finished : .failed(message ?? String(localized: "The update failed."))
        DiagnosticsLog.shared.log("fota: finished, success=\(success) \(message ?? "")")
    }

}
