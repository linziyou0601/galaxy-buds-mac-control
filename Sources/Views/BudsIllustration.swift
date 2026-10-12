import AppKit
import SwiftUI

/// 依機型配置的可見矩形呈現官方產品圖，透明留白不參與版面縮放。
@MainActor
struct BudsIllustration: View {
    /// 以解碼後像素估算快取成本，限制為 64 MiB。
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    var model: BudsModel?
    var variant: ProductVariant?
    var showCase = false
    var body: some View {
        Group {
            // 已配置圖片優先，缺圖以原生耳機符號表達，不推測顏色。
            if let image = productImage {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                // 缺少產品圖片時使用明確替代呈現，避免載入失敗留下空白。
                Image(systemName: "earbuds").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }.accessibilityLabel(Text(LocalizedStringKey(showCase ? "Samsung charging case" : "Samsung Galaxy Buds Pro")))
    }

    /// 原始 PNG 保持完整，顯示時取配置指定的可見內容。
    private var productImage: NSImage? {
        // 無機型配置時不能選擇產品素材。
        guard let profile = model?.profile else { return nil }
        let selected = variant ?? profile.variant(reportedID: nil, overrideID: nil)
        let asset = showCase ? selected.chargingCase : selected.earbuds
        let name = asset.name
        let bounds = asset.bounds
        let key = (name + ":" + bounds.map { String($0) }.joined(separator: ",")) as NSString
        // 共用 NSCache 避免重複解碼同一素材與可見範圍。
        if let image = Self.images.object(forKey: key) { return image }
        // 外部素材必須能讀取及解碼，失敗回到原生圖示。
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Products"),
            let original = NSImage(contentsOf: url),
            let pixels = original.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rect = CGRect(x: bounds[0], y: bounds[1], width: bounds[2], height: bounds[3])
        // 無效裁切不讀取圖片外部範圍，保留完整原始影像。
        guard CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height).contains(rect),
            let cropped = pixels.cropping(to: rect)
        else { return original }
        let image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        Self.images.setObject(image, forKey: key, cost: pixels.width * pixels.height * 4)
        return image
    }
}
