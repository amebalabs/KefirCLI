import Foundation
import SwiftKEF
import AsyncHTTPClient

enum InteractiveCommand {
    case volumeUp
    case volumeDown
    case volumeUpPrecise
    case volumeDownPrecise
    case toggleMute
    case playPause
    case nextTrack
    case previousTrack
    case changeSource
    case powerToggle
    case showStatus
    case quit
    case help
    case refresh
}

@MainActor
class InteractiveMode {
    private let speaker: KEFSpeaker
    private let speakerName: String
    private var isRunning = true
    private var currentVolume: Int = 0
    private var isMuted = false
    private var currentSource: KEFSource = .wifi
    private var isPlaying = false
    private var currentTrack: SongInfo?
    
    // State tracking for intelligent refresh
    private struct UIState: Equatable {
        let volume: Int
        let isMuted: Bool
        let source: KEFSource
        let isPlaying: Bool
        let trackInfo: SongInfo?
    }
    
    private var previousState: UIState?
    
    init(speaker: KEFSpeaker, speakerName: String) {
        self.speaker = speaker
        self.speakerName = speakerName
    }
    
    func run() async throws {
        // Setup terminal
        enableRawMode()
        defer { disableRawMode() }
        
        UI.clearScreen()
        UI.hideCursor()
        defer { UI.showCursor() }
        
        // Initial status fetch
        await updateStatus()
        
        // Start refresh timer
        Task {
            while isRunning {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if isRunning {
                    await updateStatus()
                    // Only redraw if state has changed
                    if hasStateChanged() {
                        await redrawInterface()
                    }
                }
            }
        }
        
        // Draw initial interface
        await redrawInterface()
        
        // Main input loop
        while isRunning {
            if let char = readChar() {
                if let command = parseCommand(char) {
                    await handleCommand(command)
                }
            } else {
                // No input available, sleep briefly to avoid busy-waiting
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }
    
    private func updateStatus() async {
        do {
            currentVolume = try await speaker.getVolume()
            currentSource = try await speaker.getSource()
            isPlaying = try await speaker.isPlaying()
            if isPlaying {
                currentTrack = try await speaker.getSongInformation()
            } else {
                currentTrack = nil
            }
        } catch {
            // Silently ignore errors during refresh
        }
    }
    
    private func getCurrentState() -> UIState {
        return UIState(
            volume: currentVolume,
            isMuted: isMuted,
            source: currentSource,
            isPlaying: isPlaying,
            trackInfo: currentTrack
        )
    }
    
    private func hasStateChanged() -> Bool {
        let currentState = getCurrentState()
        return previousState != currentState
    }
    
    private func redrawInterface() async {
        // Save current state
        previousState = getCurrentState()
        
        UI.clearScreen()
        UI.moveCursor(row: 1, column: 1)
        
        // Header
        let title = "🎵 KefirCLI - \(speakerName)"
        print(UI.bold(UI.color(title, .cyan)))
        print(UI.dim(String(repeating: "─", count: 60)))
        print()
        
        // Volume progress bar (width 60 to match tables)
        UI.drawProgressBar(value: currentVolume, max: 100, width: 60)
        
        // ASCII logo for Kefir - tall glass with drink
        let logo = [
            "   ╭─╮   ",
            "  ╱   ╲  ",
            " │ ≈≈≈ │ ",
            " │     │ ",
            " │     │ ",
            " │KEFIR│ ",
            " ╰─────╯ "
        ]
        
        // Status Box with logo
        var statusContent: [String] = []
        
        // Power status
        statusContent.append("Power: \(UI.color("ON", .green))")
        
        // Source
        statusContent.append("Source: \(UI.color(currentSource.rawValue.capitalized, .blue))")
        
        // Now Playing
        if isPlaying, let track = currentTrack {
            statusContent.append("")
            statusContent.append(UI.bold("Now Playing:"))
            if let title = track.title {
                statusContent.append("  Title: \(title)")
            }
            if let artist = track.artist {
                statusContent.append("  Artist: \(artist)")
            }
            if let album = track.album {
                statusContent.append("  Album: \(album)")
            }
        } else {
            statusContent.append("")
            statusContent.append(UI.dim("Not playing"))
        }
        
        // Draw custom box with logo on the right
        let horizontalLine = String(repeating: "─", count: 58)
        print("┌\(horizontalLine)┐")
        
        // Title
        let paddedTitle = " Status "
        let titleLength = paddedTitle.count
        let leftPadding = (60 - titleLength) / 2
        let rightPadding = 60 - titleLength - leftPadding
        print("│\(String(repeating: " ", count: leftPadding - 1))\(UI.bold(paddedTitle))\(String(repeating: " ", count: rightPadding - 1))│")
        print("├\(horizontalLine)┤")
        
        // Content with logo
        for i in 0..<max(statusContent.count, logo.count) {
            var leftContent = ""
            var rightContent = ""
            
            if i < statusContent.count {
                leftContent = statusContent[i]
                // Remove ANSI codes to calculate actual length
                let strippedLine = leftContent.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
                let padding = 42 - strippedLine.count // Leave space for logo
                leftContent = leftContent + String(repeating: " ", count: max(0, padding))
            } else {
                leftContent = String(repeating: " ", count: 42)
            }
            
            if i < logo.count {
                rightContent = UI.color(logo[i], .cyan)
            } else {
                rightContent = String(repeating: " ", count: 13) // Logo width
            }
            
            // Ensure proper spacing
            let totalVisible = leftContent.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression).count + 
                              rightContent.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression).count
            let extraPadding = max(0, 56 - totalVisible) // 60 - 4 (borders and spaces)
            
            print("│ \(leftContent)\(String(repeating: " ", count: extraPadding))\(rightContent) │")
        }
        
        print("└\(horizontalLine)┘")
        
        // Controls tip - centered to table width (60)
        let tip = "↑/↓ volume • space play/pause • →/← tracks • h help"
        let padding = (60 - tip.count) / 2
        print(String(repeating: " ", count: padding) + UI.dim(tip))
    }
    
    private func parseCommand(_ char: Character) -> InteractiveCommand? {
        switch char {
        case "\u{1B}": // ESC sequence
            if let next1 = readChar(), next1 == "[" {
                if let next2 = readChar() {
                    switch next2 {
                    case "1": // Check for Shift+Arrow sequences
                        if let next3 = readChar(), next3 == ";" {
                            if let next4 = readChar(), next4 == "2" {
                                if let next5 = readChar() {
                                    switch next5 {
                                    case "A": return .volumeUpPrecise // Shift+Up
                                    case "B": return .volumeDownPrecise // Shift+Down
                                    default: break
                                    }
                                }
                            }
                        }
                        return nil
                    case "A": return .volumeUp // Up arrow
                    case "B": return .volumeDown // Down arrow
                    case "C": return .nextTrack // Right arrow
                    case "D": return .previousTrack // Left arrow
                    default: break
                    }
                }
            }
            return nil
        case " ": return .playPause
        case "m", "M": return .toggleMute
        case "s", "S": return .changeSource
        case "p", "P": return .powerToggle
        case "r", "R": return .refresh
        case "h", "H", "?": return .help
        case "q", "Q", "\u{03}": return .quit // q, Q, or Ctrl+C
        case "+", "=": return .volumeUp
        case "-", "_": return .volumeDown
        default: return nil
        }
    }
    
    private func handleCommand(_ command: InteractiveCommand) async {
        switch command {
        case .volumeUp:
            await adjustVolume(by: 5)
        case .volumeDown:
            await adjustVolume(by: -5)
        case .volumeUpPrecise:
            await adjustVolume(by: 1)
        case .volumeDownPrecise:
            await adjustVolume(by: -1)
        case .toggleMute:
            await toggleMute()
        case .playPause:
            await togglePlayPause()
        case .nextTrack:
            await nextTrack()
        case .previousTrack:
            await previousTrack()
        case .changeSource:
            await changeSource()
        case .powerToggle:
            await togglePower()
        case .showStatus, .refresh:
            await updateStatus()
            await redrawInterface()
        case .help:
            await showHelp()
        case .quit:
            isRunning = false
        }
    }
    
    private func adjustVolume(by amount: Int) async {
        let newVolume = min(100, max(0, currentVolume + amount))
        do {
            try await speaker.setVolume(newVolume)
            currentVolume = newVolume
            await redrawInterface()
        } catch {
            await showError("Failed to adjust volume")
        }
    }
    
    private func toggleMute() async {
        do {
            if isMuted {
                try await speaker.unmute()
            } else {
                try await speaker.mute()
            }
            isMuted.toggle()
            await updateStatus()
            await redrawInterface()
        } catch {
            await showError("Failed to toggle mute")
        }
    }
    
    private func togglePlayPause() async {
        do {
            try await speaker.togglePlayPause()
            isPlaying.toggle()
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait for state to update
            await updateStatus()
            await redrawInterface()
        } catch {
            await showError("Failed to toggle playback")
        }
    }
    
    private func nextTrack() async {
        do {
            try await speaker.nextTrack()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await updateStatus()
            await redrawInterface()
        } catch {
            await showError("Failed to skip track")
        }
    }
    
    private func previousTrack() async {
        do {
            try await speaker.previousTrack()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await updateStatus()
            await redrawInterface()
        } catch {
            await showError("Failed to go to previous track")
        }
    }
    
    private func changeSource() async {
        // Show source selection menu
        UI.clearScreen()
        UI.moveCursor(row: 1, column: 1)
        
        print(UI.bold("Select Input Source:"))
        print()
        
        let sources = KEFSource.allCases
        for (index, source) in sources.enumerated() {
            let marker = source == currentSource ? "▶" : " "
            print("\(marker) \(index + 1). \(source.rawValue.capitalized)")
        }
        
        print()
        print(UI.dim("Press number to select, or ESC to cancel"))
        
        while true {
            if let char = readChar() {
                if char == "\u{1B}" { // ESC
                    break
                }
                if let number = Int(String(char)), number > 0 && number <= sources.count {
                    do {
                        let selectedSource = sources[number - 1]
                        try await speaker.setSource(selectedSource)
                        currentSource = selectedSource
                    } catch {
                        await showError("Failed to change source")
                    }
                    break
                }
            }
        }
        
        await redrawInterface()
    }
    
    private func togglePower() async {
        do {
            let status = try await speaker.getStatus()
            if status == .powerOn {
                try await speaker.shutdown()
                isRunning = false // Exit interactive mode when powering off
            } else {
                try await speaker.powerOn()
            }
        } catch {
            await showError("Failed to toggle power")
        }
    }
    
    private func showHelp() async {
        UI.clearScreen()
        UI.moveCursor(row: 1, column: 1)
        
        let helpContent = [
            UI.bold("KefirCLI Interactive Mode Help"),
            "",
            UI.underline("Volume Control:"),
            "  ↑/↓ or +/-  : Adjust volume (5% steps)",
            "  Shift+↑/↓   : Adjust volume (1% steps)",
            "  m           : Mute/Unmute",
            "",
            UI.underline("Playback Control:"),
            "  SPACE       : Play/Pause",
            "  →/←         : Next/Previous track",
            "",
            UI.underline("Other Controls:"),
            "  s           : Change input source",
            "  p           : Toggle power",
            "  r           : Refresh status",
            "  h or ?      : Show this help",
            "  q or Ctrl+C : Quit interactive mode",
            "",
            UI.dim("Press any key to return...")
        ]
        
        for line in helpContent {
            print(line)
        }
        
        _ = readChar()
        await redrawInterface()
    }
    
    private func showError(_ message: String) async {
        UI.moveCursor(row: 20, column: 1)
        print(UI.error(message))
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await redrawInterface()
    }
    
    // MARK: - Terminal Helpers
    
    private var originalTermios: termios?
    
    private func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw
        
        raw.c_lflag &= ~(UInt(ICANON | ECHO))
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        
        // Make stdin non-blocking
        let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
    }
    
    private func disableRawMode() {
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
        
        // Restore blocking mode
        let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags & ~O_NONBLOCK)
    }
    
    private func readChar() -> Character? {
        var buffer = [UInt8](repeating: 0, count: 1)
        let bytesRead = read(STDIN_FILENO, &buffer, 1)
        
        if bytesRead > 0 {
            return Character(UnicodeScalar(buffer[0]))
        }
        return nil
    }
}