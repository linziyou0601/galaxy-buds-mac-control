import AVFoundation
import CoreAudio
import Foundation
import simd

struct AudioTests {
    /// 配戴方向不應把左右轉頭映射成點頭或側傾，重新置中保持正前方。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testSensorWorldCoordinates() throws {
        let reference = simd_quatd(angle: .pi / 2, axis: SIMD3<Double>(1, 0, 0))
        // 左右轉頭分別驗證，確保映射不受配戴方向影響。
        for sign in [-1.0, 1.0] {
            let turn = simd_quatd(angle: sign * .pi / 2, axis: SIMD3<Double>(0, 0, 1))
            let orientation = SpatialAudioController.listenerOrientation(
                current: turn * reference, reference: reference)
            try check(abs(Double(orientation.forward.x) + sign) < 0.000001)
            try check(abs(orientation.forward.y) < 0.000001 && abs(orientation.forward.z) < 0.000001)
            try check(abs(orientation.up.y - 1) < 0.000001)
        }
        let centered = SpatialAudioController.listenerOrientation(current: reference, reference: reference)
        try check(abs(centered.forward.x) < 0.000001 && abs(centered.forward.y) < 0.000001)
        try check(abs(centered.forward.z + 1) < 0.000001 && abs(centered.up.y - 1) < 0.000001)
    }

    /// AudioBufferList 的實際聲道布局優先於 stream format 的推測。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testStereoPCMLayouts() throws {
        // 交錯與平面兩種緩衝布局都應解碼成同一組左右樣本。
        for interleaved in [true, false] {
            let format = try require(
                AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: interleaved)
            )
            let buffer = try require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
            buffer.frameLength = 3
            let left: [Float] = [0.1, 0.2, 0.3]
            let right: [Float] = [0.9, 0.8, 0.7]
            let channels = try require(buffer.floatChannelData)
            // 逐個 frame 填入辨識值，避免左右聲道被交換仍誤通過。
            for i in 0..<3 {
                // 交錯 PCM 依左右樣本交替寫入同一聲道緩衝。
                if interleaved {
                    channels[0][i * 2] = left[i]
                    channels[0][i * 2 + 1] = right[i]
                } else {
                    // 平面 PCM 分別填入左右聲道，驗證相同解碼輸出。
                    channels[0][i] = left[i]
                    channels[1][i] = right[i]
                }
            }
            let decoded = try require(SpatialAudioController.decodeStereo(buffer.audioBufferList))
            try check(decoded.0 == left && decoded.1 == right)
        }
    }

    /// 空白前置 buffer 不應阻斷後續兩個有效聲道。
    ///
    /// - Throws: 斷言、必要解析或被測試方法不符合預期時傳遞測試錯誤。
    func testEmptyLeadingPCMBuffer() throws {
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<AudioBufferList>.size + 2 * MemoryLayout<AudioBuffer>.size,
            alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        memory.initializeMemory(
            as: UInt8.self, repeating: 0, count: MemoryLayout<AudioBufferList>.size + 2 * MemoryLayout<AudioBuffer>.size
        )
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.pointee.mNumberBuffers = 3
        let left: [Float] = [0.2, 0.4]
        let right: [Float] = [0.3, 0.5]
        try left.withUnsafeBufferPointer { l in
            try right.withUnsafeBufferPointer { r in
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[0] = AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
                buffers[1] = AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(mutating: l.baseAddress))
                buffers[2] = AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(mutating: r.baseAddress))
                let decoded = try require(SpatialAudioController.decodeStereo(UnsafePointer(list)))
                try check(decoded.0 == left && decoded.1 == right)
            }
        }
    }
}
