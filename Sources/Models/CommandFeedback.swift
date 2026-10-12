import Foundation

/// 使用者操作的資訊或錯誤，訊息由服務層完成翻譯。
enum CommandFeedback: Sendable {
    case info(String)
    case error(String)

    var message: String {
        // 只有錯誤回饋使用錯誤樣式，等待與完成保留一般提示。
        switch self {
        // 一般與錯誤回饋共用原始文字，樣式另依類型決定。
        case .info(let text), .error(let text): text
        }
    }

    var isError: Bool {
        // 錯誤與一般資訊依回饋型別判斷，文字內容不參與分類。
        if case .error = self { true } else { false }
    }
}
