import Foundation

/// CRC-16/CCITT 使用多項式 0x1021 與初始值 0。
enum CRC16 {
    /// 計算 CRC-16/CCITT 校驗值。
    ///
    /// - Parameter data: 要校驗的位元組，SPP 封包使用命令 ID 與 payload。
    /// - Returns: 初始值為 0 的 16-bit 校驗值，空資料回傳 0。傳輸端另以 little-endian 編碼。
    static func ccitt(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
        // 輸入依原始位元組順序加入校驗。
        for byte in data {
            crc = crc ^ UInt16(byte) << 8
            // 每個位元組依八次左移處理其全部位元。
            for _ in 0..<8 {
                // 最高位元為 1 時，左移後以 CCITT 多項式修正餘數。
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    // 最高位元為 0 時，只左移即可處理下一個位元。
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}
