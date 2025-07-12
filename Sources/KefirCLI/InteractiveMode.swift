import Foundation
import SwiftKEF
import AsyncHTTPClient
#if os(Linux)
import Glibc
#else
import Darwin
#endif

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
    private var currentSongPosition: Int64?
    private var currentSongDuration: Int?
    private var pollingTask: Task<Void, Error>?
    private var lastUpdateTime: Date = Date()
    private var updateCount: Int = 0
    private var isHandlingCommand: Bool = false
    private var showingHelp: Bool = false
    private var showingSourceMenu: Bool = false
    
    // State tracking for intelligent refresh
    private struct UIState: Equatable {
        let volume: Int
        let isMuted: Bool
        let source: KEFSource
        let isPlaying: Bool
        let trackInfo: SongInfo?
        let songPosition: Int64?
        let songDuration: Int?
    }
    
    private var previousState: UIState?
    
    init(speaker: KEFSpeaker, speakerName: String) {
        self.speaker = speaker
        self.speakerName = speakerName
    }
    
    func run() async throws {
        // Setup terminal
        enableRawMode()
        defer { 
            disableRawMode()
            pollingTask?.cancel()
        }
        
        UI.clearScreen()
        UI.hideCursor()
        defer { UI.showCursor() }
        
        // Initial status fetch
        await updateStatus()
        
        // Get initial song position if playing
        if isPlaying {
            do {
                currentSongPosition = try await speaker.getSongPosition()
                currentSongDuration = try await speaker.getSongDuration()
                // Initial position fetched
            } catch {
                // Ignore errors
            }
        }
        
        // Start polling for real-time updates
        pollingTask = Task {
            do {
                // Use longer timeout for true real-time updates (speaker will respond immediately on changes)
                let eventStream = await speaker.startPolling(pollInterval: 10, pollSongStatus: true)
                
                for try await event in eventStream {
                    guard isRunning else { break }
                    
                    // Update state from event
                    var hasChanges = false
                    
                    if let volume = event.volume {
                        currentVolume = volume
                        isMuted = volume == 0
                        hasChanges = true
                    }
                    if let source = event.source {
                        currentSource = source
                        hasChanges = true
                    }
                    if let state = event.playbackState {
                        isPlaying = state == .playing
                        // Clear track info when stopped
                        if state != .playing {
                            currentTrack = nil
                            currentSongPosition = nil
                            currentSongDuration = nil
                        }
                        hasChanges = true
                    }
                    if let songInfo = event.songInfo {
                        currentTrack = songInfo
                        hasChanges = true
                    }
                    if let position = event.songPosition {
                        currentSongPosition = position
                        hasChanges = true
                        // Song position updated
                    }
                    if let duration = event.songDuration {
                        currentSongDuration = duration
                        hasChanges = true
                        // Song duration updated
                    }
                    
                    // Track update for debugging
                    if hasChanges {
                        updateCount += 1
                        lastUpdateTime = Date()
                    }
                    
                    // Only redraw if state has changed or we're not showing menus
                    if hasStateChanged() && !showingHelp && !showingSourceMenu {
                        await redrawInterface()
                    }
                }
            } catch {
                // Polling failed - show error in UI
                if isRunning {
                    await showError("Polling error: \(error.localizedDescription)")
                    // Try to continue with manual updates as fallback
                    while isRunning {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        await updateStatus()
                        if hasStateChanged() {
                            await redrawInterface()
                        }
                    }
                }
            }
        }
        
        // Draw initial interface
        await redrawInterface()
        
        // Start a timer to refresh the UI periodically to show update status
        let uiRefreshTask = Task {
            while isRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                // Don't redraw if we're showing help or a menu
                if isRunning && !isHandlingCommand && !showingHelp && !showingSourceMenu {
                    // Skip refresh if only position changed recently
                    let timeSinceLastEvent = Date().timeIntervalSince(lastUpdateTime)
                    if timeSinceLastEvent > 2.0 || !isPlaying {
                        await redrawInterface()
                    }
                }
            }
        }
        
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
        
        uiRefreshTask.cancel()
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
            trackInfo: currentTrack,
            songPosition: currentSongPosition,
            songDuration: currentSongDuration
        )
    }
    
    private func hasStateChanged() -> Bool {
        let currentState = getCurrentState()
        return previousState != currentState
    }
    
    private func wrapText(_ text: String, width: Int, indent: Int = 0) -> [String] {
        guard text.count > width else { return [text] }
        
        var lines: [String] = []
        var currentLine = ""
        let words = text.split(separator: " ")
        let indentString = String(repeating: " ", count: indent)
        
        for word in words {
            let wordStr = String(word)
            if currentLine.isEmpty {
                currentLine = wordStr
            } else if currentLine.count + 1 + wordStr.count <= width {
                currentLine += " " + wordStr
            } else {
                lines.append(currentLine)
                currentLine = indentString + wordStr
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.isEmpty ? [""] : lines
    }
    
    private func redrawInterface() async {
        // Save current state
        previousState = getCurrentState()
        
        UI.clearScreen()
        UI.moveCursor(row: 1, column: 1)
        
        // Header
        let title = "🎵 KefirCLI - \(speakerName)"
        print(UI.bold(UI.color(title, .cyan)))
        print(UI.dim(String(repeating: "─", count: 80)))
        print()
        
        // Volume progress bar (width 80 to match tables)
        UI.drawProgressBar(value: currentVolume, max: 100, width: 80)
        
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
                let titleLines = wrapText(title, width: 50, indent: 2)
                statusContent.append("  Title: \(titleLines[0])")
                for i in 1..<titleLines.count {
                    statusContent.append("         \(titleLines[i])")
                }
            }
            if let artist = track.artist {
                let artistLines = wrapText(artist, width: 50, indent: 2)
                statusContent.append("  Artist: \(artistLines[0])")
                for i in 1..<artistLines.count {
                    statusContent.append("          \(artistLines[i])")
                }
            }
            if let album = track.album {
                let albumLines = wrapText(album, width: 50, indent: 2)
                statusContent.append("  Album: \(albumLines[0])")
                for i in 1..<albumLines.count {
                    statusContent.append("         \(albumLines[i])")
                }
            }
            
            // Add song progress if available
            if let position = currentSongPosition, let duration = currentSongDuration, duration > 0 {
                let positionSec = Int(position) / 1000
                let durationSec = duration / 1000
                let progress = Double(position) / Double(duration)
                
                let positionMin = positionSec / 60
                let positionSecRem = positionSec % 60
                let durationMin = durationSec / 60
                let durationSecRem = durationSec % 60
                
                statusContent.append("")
                statusContent.append("  Progress: \(String(format: "%d:%02d / %d:%02d", positionMin, positionSecRem, durationMin, durationSecRem))")
                
                // Progress bar (30 chars wide, more compact)
                let barWidth = 30
                let filledWidth = Int(Double(barWidth) * progress)
                let emptyWidth = barWidth - filledWidth
                let progressBar = String(repeating: "█", count: filledWidth) + String(repeating: "░", count: emptyWidth)
                statusContent.append("  " + UI.color(progressBar, .cyan))
            }
        } else {
            statusContent.append("")
            statusContent.append(UI.dim("Not playing"))
        }
        
        // Draw custom box with logo on the right
        let horizontalLine = String(repeating: "─", count: 78)
        print("┌\(horizontalLine)┐")
        
        // Title
        let paddedTitle = " Status "
        let titleLength = paddedTitle.count
        let leftPadding = (80 - titleLength) / 2
        let rightPadding = 80 - titleLength - leftPadding
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
                let padding = 62 - strippedLine.count // Leave space for logo (increased from 42)
                leftContent = leftContent + String(repeating: " ", count: max(0, padding))
            } else {
                leftContent = String(repeating: " ", count: 62)
            }
            
            if i < logo.count {
                rightContent = UI.color(logo[i], .cyan)
            } else {
                rightContent = String(repeating: " ", count: 13) // Logo width
            }
            
            // Ensure proper spacing
            let totalVisible = leftContent.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression).count + 
                              rightContent.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression).count
            let extraPadding = max(0, 76 - totalVisible) // 80 - 4 (borders and spaces)
            
            print("│ \(leftContent)\(String(repeating: " ", count: extraPadding))\(rightContent) │")
        }
        
        print("└\(horizontalLine)┘")
        
        // Controls tip - centered to table width (80)
        let tip = "↑/↓ volume • space play/pause • →/← tracks • h help"
        let padding = (80 - tip.count) / 2
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
        isHandlingCommand = true
        defer { isHandlingCommand = false }
        
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
            // Force immediate status update and redraw
            await updateStatus()
            updateCount += 1
            lastUpdateTime = Date()
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
            // Polling will update the state automatically
            await redrawInterface()
        } catch {
            await showError("Failed to toggle mute")
        }
    }
    
    private func togglePlayPause() async {
        do {
            try await speaker.togglePlayPause()
            isPlaying.toggle()
            // Polling will update the state automatically
            await redrawInterface()
        } catch {
            await showError("Failed to toggle playback")
        }
    }
    
    private func nextTrack() async {
        do {
            try await speaker.nextTrack()
            // Polling will update the state automatically
            await redrawInterface()
        } catch {
            await showError("Failed to skip track")
        }
    }
    
    private func previousTrack() async {
        do {
            try await speaker.previousTrack()
            // Polling will update the state automatically
            await redrawInterface()
        } catch {
            await showError("Failed to go to previous track")
        }
    }
    
    private func changeSource() async {
        isHandlingCommand = true  // Prevent UI refresh while showing menu
        showingSourceMenu = true
        defer { showingSourceMenu = false }
        
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
        
        isHandlingCommand = false
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
        isHandlingCommand = true  // Prevent UI refresh while showing help
        showingHelp = true
        defer { showingHelp = false }
        
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
            "  r           : Force refresh display",
            "  h or ?      : Show this help",
            "  q or Ctrl+C : Quit interactive mode",
            "",
            UI.dim("Press any key to return...")
        ]
        
        for line in helpContent {
            print(line)
        }
        
        // Wait for keypress - use blocking read
        while readChar() == nil {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        isHandlingCommand = false
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
        
        raw.c_lflag &= ~UInt32(ICANON | ECHO)
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