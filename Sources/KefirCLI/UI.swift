import Foundation

enum ANSIColor: String {
    case black = "\u{001B}[30m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"
    case brightBlack = "\u{001B}[90m"
    case brightRed = "\u{001B}[91m"
    case brightGreen = "\u{001B}[92m"
    case brightYellow = "\u{001B}[93m"
    case brightBlue = "\u{001B}[94m"
    case brightMagenta = "\u{001B}[95m"
    case brightCyan = "\u{001B}[96m"
    case brightWhite = "\u{001B}[97m"
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case underline = "\u{001B}[4m"
}

struct UI {
    nonisolated(unsafe) static var useColors = true
    nonisolated(unsafe) static var useEmojis = true
    
    static func color(_ text: String, _ color: ANSIColor) -> String {
        guard useColors else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    static func bold(_ text: String) -> String {
        guard useColors else { return text }
        return "\(ANSIColor.bold.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    static func dim(_ text: String) -> String {
        guard useColors else { return text }
        return "\(ANSIColor.dim.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    static func underline(_ text: String) -> String {
        guard useColors else { return text }
        return "\(ANSIColor.underline.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    static func success(_ text: String) -> String {
        let emoji = useEmojis ? "✅ " : ""
        return "\(emoji)\(color(text, .green))"
    }
    
    static func error(_ text: String) -> String {
        let emoji = useEmojis ? "❌ " : ""
        return "\(emoji)\(color(text, .red))"
    }
    
    static func warning(_ text: String) -> String {
        let emoji = useEmojis ? "⚠️  " : ""
        return "\(emoji)\(color(text, .yellow))"
    }
    
    static func info(_ text: String) -> String {
        let emoji = useEmojis ? "ℹ️  " : ""
        return "\(emoji)\(color(text, .cyan))"
    }
    
    static func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    static func moveCursor(row: Int, column: Int) {
        print("\u{001B}[\(row);\(column)H", terminator: "")
    }
    
    static func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
    }
    
    static func showCursor() {
        print("\u{001B}[?25h", terminator: "")
    }
    
    static func drawBox(title: String, content: [String], width: Int = 60) {
        let horizontalLine = String(repeating: "─", count: width - 2)
        
        print("┌\(horizontalLine)┐")
        
        if !title.isEmpty {
            let paddedTitle = " \(title) "
            let titleLength = paddedTitle.count
            let leftPadding = (width - titleLength) / 2
            let rightPadding = width - titleLength - leftPadding
            print("│\(String(repeating: " ", count: leftPadding - 1))\(bold(paddedTitle))\(String(repeating: " ", count: rightPadding - 1))│")
            print("├\(horizontalLine)┤")
        }
        
        for line in content {
            let visibleLength = line.replacingOccurrences(of: #"\u{001B}\[[0-9;]*m"#, with: "", options: .regularExpression).count
            let padding = width - visibleLength - 2
            print("│ \(line)\(String(repeating: " ", count: max(0, padding))) │")
        }
        
        print("└\(horizontalLine)┘")
    }
    
    static func drawProgressBar(value: Int, max: Int = 100, width: Int = 30, label: String = "") {
        let percentage = Double(value) / Double(max)
        let filled = Int(Double(width) * percentage)
        let empty = width - filled
        
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let percentageText = String(format: "%3d%%", Int(percentage * 100))
        
        if !label.isEmpty {
            print("\(label): [\(color(bar, .cyan))] \(percentageText)")
        } else {
            print("[\(color(bar, .cyan))] \(percentageText)")
        }
    }
    
    static func formatTable(headers: [String], rows: [[String]]) -> [String] {
        guard !headers.isEmpty else { return [] }
        
        var columnWidths = headers.map { $0.count }
        
        for row in rows {
            for (index, cell) in row.enumerated() where index < columnWidths.count {
                columnWidths[index] = max(columnWidths[index], cell.count)
            }
        }
        
        var result: [String] = []
        
        // Header
        let header = headers.enumerated().map { index, header in
            header.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
        }.joined(separator: " │ ")
        result.append(bold(header))
        
        // Separator
        let separator = columnWidths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")
        result.append(separator)
        
        // Rows
        for row in rows {
            let formattedRow = row.enumerated().map { index, cell in
                if index < columnWidths.count {
                    return cell.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
                } else {
                    return cell
                }
            }.joined(separator: " │ ")
            result.append(formattedRow)
        }
        
        return result
    }
    
    static func spinner(message: String) -> Spinner {
        return Spinner(message: message)
    }
}

final class Spinner: @unchecked Sendable {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var currentFrame = 0
    private let message: String
    private var timer: Timer?
    private let queue = DispatchQueue(label: "spinner")
    
    init(message: String) {
        self.message = message
    }
    
    func start() {
        UI.hideCursor()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.queue.sync {
                print("\r\(UI.color(self.frames[self.currentFrame], .cyan)) \(self.message)", terminator: "")
                fflush(stdout)
                self.currentFrame = (self.currentFrame + 1) % self.frames.count
            }
        }
        RunLoop.current.run()
    }
    
    func stop(success: Bool = true, message: String? = nil) {
        timer?.invalidate()
        timer = nil
        
        let finalMessage = message ?? self.message
        if success {
            print("\r\(UI.success(finalMessage))\(String(repeating: " ", count: 20))")
        } else {
            print("\r\(UI.error(finalMessage))\(String(repeating: " ", count: 20))")
        }
        UI.showCursor()
    }
}