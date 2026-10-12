import Foundation

/// 多個畫面共用的產品版面尺寸，單位為 macOS point。
enum InterfaceMetrics {
    static let sidebarInset: CGFloat = 10
    static let popoverWidth: CGFloat = 310
    static let modeDiameter: CGFloat = 40
    static let productSize = CGSize(width: 120, height: 80)
    static let minimumSettingsSize = CGSize(width: 700, height: 520)
}
