import AVFoundation
import CoreAudio
import Foundation
import simd

/// Apple 音訊 tap 擷取其他程序的播放，原生耳機音場依頭部方向渲染，停止時恢復原播放。
@Observable @MainActor
final class SpatialAudioController {
    // MARK: - 原生相依與作業快照

    // 音訊引擎、音場與兩個單聲道播放器共用同一生命週期。
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let captureQueue = DispatchQueue(label: "BudsControl.spatialCapture")
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var monoFormat: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?
    private var inputStartupTask: Task<Void, Never>?
    private var reportedEmptyInput = false
    private var queuedBuffers = 0
    private var queuedFrames = 0
    private var playersStarted = false
    private var activateMute: (() throws -> Void)?
    // 啟動世代隔離過期 callback，停止後不再接收舊緩衝。
    private var generation = 0
    private var reference: simd_quatd?
    private var processedFrames = 0
    private(set) var headTrackingEnabled = UserDefaults.standard.object(forKey: "spatialHeadTracking") as? Bool ?? true
    private(set) var speakerAngleDegrees = min(
        75, max(15, UserDefaults.standard.object(forKey: "spatialSpeakerAngle") as? Double ?? 30))
    // 擷取啟動與實際渲染分開記錄，接收音訊不代表已完成交接。
    private(set) var isProcessing = false
    private(set) var hasAudioInput = false
    private(set) var isRunning = false
    private(set) var errorText: String?

    /// 將原生 environment 與左右單聲道播放器交給同一 AVAudioEngine。
    init() {
        engine.attach(environment)
        // 左右單聲道播放器都附加到同一原生引擎。
        for player in players { engine.attach(player) }
    }

    // MARK: - 音訊生命週期

    /// 首次讀取 tap 時由 macOS 詢問系統音訊擷取權限，音訊只在本機處理。
    func start() {
        // 重複開啟不建立第二組 tap、aggregate 或播放器。
        guard !isRunning else { return }
        // 系統 process tap 的公開邊界是 macOS 14.2，較舊系統回報可見限制。
        guard #available(macOS 14.2, *) else {
            errorText = String(localized: "System spatial audio requires macOS 14.2 or later.")
            return
        }
        errorText = nil
        do {
            var pid = getpid()
            var process: AudioObjectID = 0
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: 0)
            try Self.check(
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size,
                    &process))
            // 擷取其他程序的立體聲，排除本 App，避免原生渲染輸出回授。
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [process])
            description.name =
                (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galaxy Buds")
                + " spatial audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try Self.check(AudioHardwareCreateProcessTap(description, &tapID))
            let ownedTap = tapID
            // 取得有效非零訊號後才靜音原播放，授權或輸入失敗時保持原音。
            activateMute = {
                description.muteBehavior = .mutedWhenTapped
                var object = Unmanaged.passUnretained(description)
                var property = AudioObjectPropertyAddress(
                    mSelector: kAudioTapPropertyDescription, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
                try Self.check(
                    AudioObjectSetPropertyData(
                        ownedTap, &property, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &object))
            }
            var uidObject: Unmanaged<CFString>?
            address.mSelector = kAudioTapPropertyUID
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            try Self.check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uidObject))
            // 缺少 tap UID 無法建立私有 aggregate，走統一停止邊界。
            guard let uid = uidObject?.takeRetainedValue() else {
                throw NSError(domain: NSOSStatusErrorDomain, code: -1)
            }
            var format = AudioStreamBasicDescription()
            address.mSelector = kAudioTapPropertyFormat
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
            // 私有 aggregate 只作為輸入，系統輸出裝置保持 macOS 的目前路由。
            // 私有 aggregate 連接 process tap，保持系統正常輸出與 App 處理分開。
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey:
                    (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Galaxy Buds")
                    + " spatial capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: uid as String, kAudioSubTapDriftCompensationKey: true]
                ],
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
            address.mSelector = kAudioDevicePropertyStreamFormat
            address.mScope = kAudioDevicePropertyScopeInput
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &format))
            // 解碼器接受 32-bit float stereo PCM，其他格式回報不支援而保留播放。
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2,
                let mono = AVAudioFormat(standardFormatWithSampleRate: format.mSampleRate, channels: 1)
            else {
                throw NSError(
                    domain: "BudsControl.Audio", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "The captured audio format is unsupported.")
                    ])
            }
            monoFormat = mono
            // 音場材質及最高品質演算法交給 AVFoundation，距離衰減保持關閉。
            environment.outputType = .headphones
            environment.distanceAttenuationParameters.rolloffFactor = 0
            // 兩個播放器各自連到音場的一個輸入 bus。
            for (index, player) in players.enumerated() {
                // macOS 27 的 throwing API 保留原生錯誤，舊版使用對應公開 API。
                if #available(macOS 27.0, *) {
                    try engine.connectNode(
                        player, to: environment, fromBus: 0, toBus: AVAudioNodeBus(index), format: mono)
                } else {
                    // 較舊系統使用原本的節點連接 API，保留相同單聲道音訊格式。
                    engine.connect(player, to: environment, fromBus: 0, toBus: AVAudioNodeBus(index), format: mono)
                }
                player.renderingAlgorithm = .auto
            }
            updateSpeakerPositions()
            // macOS 27 的 throwing API 保留原生錯誤，舊版使用對應公開 API。
            if #available(macOS 27.0, *) {
                try engine.connectNode(environment, to: engine.mainMixerNode, format: nil)
            } else {
                // 較舊系統透過既有連接 API 將音場輸出交給主混音器。
                engine.connect(environment, to: engine.mainMixerNode, format: nil)
            }
            // 原生節點都連接完成後，才準備並啟動音訊引擎。
            engine.prepare()
            try engine.start()
            DiagnosticsLog.shared.log(
                "Spatial native output presentation latency: \(engine.outputNode.outputPresentationLatency) seconds")
            let token = generation
            // 以專用佇列讀取音訊 callback，進入 MainActor 前複製有效 PCM。
            try Self.check(
                AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, captureQueue) {
                    [weak self] _, input, _, _, _ in
                    // 回呼先依實際 AudioBuffer 形狀複製樣本，不能持有原生暫存指標。
                    guard let (left, right) = Self.decodeStereo(input) else {
                        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                        let layout = buffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)bytes" }.joined(
                            separator: ", ")
                        Task { @MainActor in
                            // 過期世代與已記錄的空輸入不反覆修改可觀察狀態。
                            // 停止世代後的 completion 不扣減新一輪 queue。
                            guard let self, self.generation == token, !self.reportedEmptyInput else { return }
                            self.reportedEmptyInput = true
                            DiagnosticsLog.shared.log("Spatial capture empty input layout: " + layout)
                        }
                        return
                    }
                    Task { @MainActor in self?.enqueue(left: left, right: right, token: token) }
                })
            try Self.check(AudioDeviceStart(aggregateID, ioProc))
            isRunning = true
            inputStartupTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                // 十秒內仍未取得 PCM 才回報授權或播放狀態問題。
                guard !Task.isCancelled, let self, self.generation == token, !self.hasAudioInput else { return }
                self.stop()
                self.errorText = String(
                    localized: "No system audio data. Check the audio recording permission and restart playback.")
            }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    // 停止後的引擎配置通知不重新觸發清理。
                    guard let self, self.isRunning else { return }
                    self.stop()
                    self.errorText = String(localized: "Audio output changed. Restart spatial audio processing.")
                }
            }
        } catch {
            // 任一原生建立或啟動錯誤都釋放已建立的部分資源。
            stop()
            errorText = error.localizedDescription
        }
    }

    /// 所有 tap、aggregate、IO callback 與播放器都有同一停止邊界。
    func stop() {
        generation += 1
        inputStartupTask?.cancel()
        inputStartupTask = nil
        reportedEmptyInput = false
        // 先移除引擎通知，停止動作不再觸發新的配置處理。
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        // 先停止輸入回呼再釋放 aggregate，避免讀取已銷毀的音訊資源。
        if let ioProc, aggregateID != 0 {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        ioProc = nil
        // 只銷毀本服務成功建立的私有裝置。
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = 0
        // process tap 依其公開 API 的系統版本邊界釋放。
        if #available(macOS 14.2, *), tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        // 原生資源釋放後清除識別與播放器狀態，停止可安全重複呼叫。
        tapID = 0
        // 停止左右播放器後再停止引擎，避免仍在排程的緩衝。
        for player in players { player.stop() }
        engine.stop()
        isRunning = false
        isProcessing = false
        queuedBuffers = 0
        queuedFrames = 0
        playersStarted = false
        activateMute = nil
        processedFrames = 0
        hasAudioInput = false
        reference = nil
        DiagnosticsLog.shared.log("Spatial capture stopped")
    }

    // MARK: - 音場與姿態

    /// 清除參考姿態，下一筆有效四元數成為面向螢幕的置中方向。
    func recenter() { reference = nil }

    /// 頭部追蹤可獨立停用，靜態音場保持原生渲染。
    ///
    /// - Parameters:
    ///   - enabled: 是否啟用此方法所管理的功能，實機結果由系統或耳機回報確認。
    func setHeadTracking(_ enabled: Bool) {
        headTrackingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "spatialHeadTracking")
        reference = nil
        // 關閉追蹤後維持面向前方的靜態音場，播放處理持續。
        if !enabled {
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        }
    }

    /// 標準立體聲喇叭預設 ±30 度，範圍沿用參考播放器的 15...75 度。
    ///
    /// - Parameters:
    ///   - degrees: 單側虛擬喇叭角度，單位為度，限制於 15...75。
    func setSpeakerAngle(_ degrees: Double) {
        // 偏好輸入須為有限角度，再限制參考播放器的公開控制範圍。
        guard degrees.isFinite else { return }
        speakerAngleDegrees = min(75, max(15, degrees))
        UserDefaults.standard.set(speakerAngleDegrees, forKey: "spatialSpeakerAngle")
        updateSpeakerPositions()
    }

    /// 依共用角度將左右虛擬喇叭置於前方單位圓，單位為公尺。
    private func updateSpeakerPositions() {
        let angle = speakerAngleDegrees * .pi / 180
        // 喇叭角度或追蹤開關更新時，同步左右播放器位置。
        for (index, player) in players.enumerated() {
            player.position = AVAudio3DPoint(
                x: Float(sin(angle)) * (index == 0 ? -1 : 1), y: 0, z: -Float(cos(angle)))
        }
    }

    /// x、y、z、w 四元數經原生 simd 轉成 listener 的前方與上方向量。
    ///
    /// - Parameters:
    ///   - values: 依 x、y、z、w 排列的四元數，nil 或無效姿態保留目前方向。
    func updateOrientation(_ values: [Double]?) {
        // 未處理音訊、已停用追蹤或缺少姿態時不更動 listener。
        guard isProcessing, headTrackingEnabled, let values, values.count == 4 else { return }
        let rotation = simd_quatd(ix: values[0], iy: values[1], iz: values[2], r: values[3])
        // 開啟或重新置中後以第一筆有效資料建立參考方向。
        if reference == nil { reference = rotation }
        environment.listenerVectorOrientation = Self.listenerOrientation(current: rotation, reference: reference!)
    }

    /// GRV 的世界 Z 軸為垂直方向，轉成 Apple 音場的 Y 軸垂直座標。
    /// 世界相對旋轉採 current × inverse(reference)，排除耳機配戴方向對轉頭軸的影響。
    ///
    /// - Parameters:
    ///   - current: 耳機目前回報的世界座標姿態。
    ///   - reference: 重新置中時保存的世界座標參考姿態。
    /// - Returns: 轉換成 Apple Y 軸垂直座標的前方與上方向量。
    nonisolated static func listenerOrientation(current: simd_quatd, reference: simd_quatd)
        -> AVAudio3DVectorOrientation
    {
        // 先移除置中參考姿態，再將世界 Z 軸垂直座標轉成音場 Y 軸。
        let world = simd_normalize(current * reference.inverse)
        let basis = simd_quatd(angle: -.pi / 2, axis: SIMD3<Double>(1, 0, 0))
        let rotation = basis * world * basis.inverse
        let forward = rotation.act(SIMD3<Double>(0, 0, -1))
        let up = rotation.act(SIMD3<Double>(0, 1, 0))
        // 轉換後的前方與上方向量交給原生音場，保持座標一致。
        return AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: Float(forward.x), y: Float(forward.y), z: Float(forward.z)),
            up: AVAudio3DVector(x: Float(up.x), y: Float(up.y), z: Float(up.z)))
    }

    // MARK: - PCM 交接與解碼

    /// 排入左右 PCM 並限制待渲染 buffer，世代過期或原生錯誤時保留原播放。
    /// token 對應啟動世代；左右樣本由 decodeStereo 保證相同 frame 數。
    ///
    /// - Parameters:
    ///   - left: 左聲道 Float PCM 樣本，兩側長度必須一致。
    ///   - right: 右聲道 Float PCM 樣本，兩側長度必須一致。
    ///   - token: 音訊啟動世代，用於排除停止或重新啟動前的舊緩衝。
    private func enqueue(left: [Float], right: [Float], token: Int) {
        // 已停止或較舊 tap 的回呼不排入新一輪引擎。
        guard token == generation, isRunning, let monoFormat else { return }
        // 有界 queue 超限時恢復原播放，避免音訊延遲持續累積。
        guard queuedBuffers < 16 else {
            stop()
            errorText = String(
                localized: "Audio processing exceeded its buffer limit. Original audio has been restored.")
            return
        }
        // 首筆 PCM 記錄 frame 數與取樣率，後續回呼保持低頻日誌。
        if processedFrames == 0 {
            DiagnosticsLog.shared.log(
                "Spatial capture receiving PCM frames: \(left.count), sample rate: \(monoFormat.sampleRate)")
        }
        // 第一筆有效 PCM 取消啟動 watchdog，授權狀態仍由系統管理。
        if !hasAudioInput {
            hasAudioInput = true
            inputStartupTask?.cancel()
            inputStartupTask = nil
        }
        processedFrames += left.count
        // 左右 PCM 分別建立相同 frame 數的單聲道緩衝。
        for (index, samples) in [left, right].enumerated() {
            // 原生 buffer 或聲道配置失敗時不使用無效指標。
            guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                let channel = buffer.floatChannelData?[0]
            else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { pointer in
                // Swift 複製的樣本在此寫入 engine 持有的 PCM buffer。
                if let base = pointer.baseAddress { channel.update(from: base, count: samples.count) }
            }
            // rendered 計算播放器輸出前的待處理量，排除藍牙呈現延遲及提前讀取。
            players[index].scheduleBuffer(buffer, completionCallbackType: .dataRendered) { [weak self] _ in
                // 左右共用同一批 frame，右播放器回呼結算一次待處理量。
                if index == 1 {
                    Task { @MainActor in
                        // 停止世代後的 completion 不扣減新一輪 queue。
                        guard let self, self.generation == token else { return }
                        self.queuedBuffers -= 1
                        self.queuedFrames -= samples.count
                    }
                }
            }
        }
        queuedBuffers += 1
        queuedFrames += left.count
        do {
            // 累積 50 ms 後以同一 hostTime 啟動左右，避免聲道開始時間偏移。
            if !playersStarted && queuedFrames >= Int(monoFormat.sampleRate * 0.05) {
                let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.01))
                // 左右播放器以同一未來時點開始，保持立體聲同步。
                for player in players {
                    // macOS 27 的 throwing API 保留原生錯誤，舊版使用對應公開 API。
                    if #available(macOS 27.0, *) { try player.playAudio(at: start) } else { player.play(at: start) }
                }
                playersStarted = true
            }
            // 排定未來開始不代表已渲染，兩耳播放時間前進後才切換原播放。
            if playersStarted, activateMute != nil,
                players.allSatisfy({ player in
                    // 兩個播放器都必須提供有效播放時間，才可交接原始音訊。
                    guard let nodeTime = player.lastRenderTime,
                        let playerTime = player.playerTime(forNodeTime: nodeTime)
                    else { return false }
                    return playerTime.isSampleTimeValid && playerTime.sampleTime > 0
                }),
                left.contains(where: { $0.isFinite && $0 != 0 }) || right.contains(where: { $0.isFinite && $0 != 0 })
            {
                DiagnosticsLog.shared.log("Spatial players rendering; handing off original playback")
                // 確認兩耳播放器真正渲染後，才將原始系統音訊交接給空間處理。
                try activateMute?()
                activateMute = nil
                isProcessing = true
            }
        } catch {
            // 任一原生建立或啟動錯誤都釋放已建立的部分資源。
            stop()
            errorText = error.localizedDescription
        }
    }

    /// 依實際 AudioBuffer 的聲道數判讀平面或交錯 PCM，略過空白 buffer。
    ///
    /// - Parameters:
    ///   - input: CoreAudio 提供的 Float PCM 緩衝清單，指標僅在讀取期間有效。
    /// - Returns: 等長左右聲道樣本；空內容、非立體聲布局或無有效 frame 時回傳 nil。
    nonisolated static func decodeStereo(_ input: UnsafePointer<AudioBufferList>) -> ([Float], [Float])? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            .filter { $0.mData != nil && $0.mDataByteSize > 0 && $0.mNumberChannels > 0 }
        // 只保留有有效資料及聲道數的原生 buffer。
        guard let first = buffers.first, let raw = first.mData else { return nil }
        let source = raw.assumingMemoryBound(to: Float.self)
        // 交錯立體聲依偶數、奇數樣本拆成左右。
        if first.mNumberChannels == 2 {
            let count = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * 2)
            // 空 frame 不排入播放器，避免零容量及不完整樣本。
            guard count > 0 else { return nil }
            return ((0..<count).map { source[$0 * 2] }, (0..<count).map { source[$0 * 2 + 1] })
        }
        // 平面布局需要兩個單聲道 buffer，讀取範圍採兩者較小長度。
        guard first.mNumberChannels == 1, buffers.count >= 2, buffers[1].mNumberChannels == 1,
            let other = buffers[1].mData
        else { return nil }
        let count = min(first.mDataByteSize, buffers[1].mDataByteSize) / UInt32(MemoryLayout<Float>.size)
        // 空 frame 不排入播放器，避免零容量及不完整樣本。
        guard count > 0 else { return nil }
        return (
            Array(UnsafeBufferPointer(start: source, count: Int(count))),
            Array(UnsafeBufferPointer(start: other.assumingMemoryBound(to: Float.self), count: Int(count)))
        )
    }

    /// CoreAudio 非零 OSStatus 轉為 NSError，交給啟動或渲染流程統一清理。
    ///
    /// - Parameters:
    ///   - result: 原生 API 回報碼，0 表示成功，其餘保留為錯誤資訊。
    /// - Throws: 底層錯誤碼或 HTTP 回覆未通過檢查時拋出錯誤。
    private static func check(_ result: OSStatus) throws {
        // 公開 API 的原始錯誤碼保留於本機錯誤資訊。
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
}
