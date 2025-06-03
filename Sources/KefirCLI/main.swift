import ArgumentParser
import AsyncHTTPClient
import Foundation
import SwiftKEF

@main
@available(macOS 10.15, *)
struct KefirCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kefir",
        abstract: "🎵 A rich CLI for controlling KEF wireless speakers",
        version: "2.0.0",
        subcommands: [
            // Speaker Management
            Speaker.self,
            
            // Direct Control Commands
            Power.self,
            Volume.self,
            Source.self,
            Play.self,
            
            // Info Commands
            Info.self,
            Status.self,
            
            // Interactive Mode
            Interactive.self,
            
            // Configuration
            Config.self
        ]
    )
    
    static func main() async {
        // If no arguments provided, check for first-time setup or show help
        if CommandLine.arguments.count == 1 {
            do {
                let config = try ConfigurationManager()
                let speakers = await config.getSpeakers()
                
                if speakers.isEmpty {
                    // First time setup
                    await runFirstTimeSetup()
                    return
                }
            } catch {
                // Config doesn't exist yet, run first time setup
                await runFirstTimeSetup()
                return
            }
            
            // Has speakers but no command specified - show help by parsing empty args
            do {
                var command = try parseAsRoot([])
                try await command.run()
            } catch {
                exit(withError: error)
            }
            return
        }
        
        // Normal execution with arguments
        do {
            var command = try parseAsRoot()
            try await command.run()
        } catch {
            exit(withError: error)
        }
    }
    
    @available(macOS 10.15, *)
    static func runFirstTimeSetup() async {
        print(UI.bold("Welcome to KefirCLI! 🎵"))
        print()
        print("It looks like this is your first time using KefirCLI.")
        print("Let's set up your first KEF speaker.")
        print()
        
        // Get speaker name
        print("What would you like to name this speaker? (e.g., \"Living Room\", \"Office\")")
        print(UI.dim("Speaker name: "), terminator: "")
        
        guard let name = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            print(UI.error("Speaker name cannot be empty"))
            return
        }
        
        // Get speaker IP
        print()
        print("What is the IP address or hostname of your KEF speaker?")
        print(UI.dim("IP address: "), terminator: "")
        
        guard let host = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            print(UI.error("IP address cannot be empty"))
            return
        }
        
        print()
        
        // Test connection and add speaker
        let spinner = UI.spinner(message: "Testing connection to \(host)...")
        
        Task {
            spinner.start()
        }
        
        do {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            // Test connection
            _ = try await speaker.getStatus()
            spinner.stop(success: true, message: "Connection successful!")
            
            // Add speaker
            _ = try await config.addSpeaker(name: name, host: host, setAsDefault: true)
            
            print()
            print(UI.success("Successfully added '\(name)' as your default speaker!"))
            print()
            print("You can now use commands like:")
            print(UI.dim("  kefir status              # Check speaker status"))
            print(UI.dim("  kefir volume set 50       # Set volume to 50%"))
            print(UI.dim("  kefir interactive         # Enter interactive mode"))
            print()
            print("To see all available commands, run: \(UI.bold("kefir --help"))")
            
            try await httpClient.shutdown()
        } catch {
            spinner.stop(success: false, message: "Failed to connect")
            print()
            print(UI.error("Could not connect to speaker at \(host)"))
            print(UI.dim("Please check the IP address and ensure the speaker is powered on."))
            print()
            print("You can manually add a speaker later with:")
            print(UI.dim("  kefir speaker add \"<name>\" <ip-address>"))
        }
    }
}

// MARK: - Speaker Management

@available(macOS 10.15, *)
struct Speaker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage speaker profiles",
        subcommands: [Add.self, List.self, Remove.self, SetDefault.self]
    )
    
    @available(macOS 10.15, *)
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a new speaker profile"
        )
        
        @Argument(help: "Name for the speaker profile")
        var name: String
        
        @Argument(help: "IP address or hostname of the speaker")
        var host: String
        
        @Flag(name: .shortAndLong, help: "Set as default speaker")
        var setDefault = false
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            // Test connection first
            let spinner = UI.spinner(message: "Testing connection to \(host)...")
            
            Task {
                spinner.start()
            }
            
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            do {
                _ = try await speaker.getStatus()
                spinner.stop(success: true, message: "Connection successful!")
                
                _ = try await config.addSpeaker(name: name, host: host, setAsDefault: setDefault)
                print(UI.success("Added speaker '\(name)' at \(host)"))
                
                if setDefault {
                    print(UI.info("Set as default speaker"))
                }
                
                try await httpClient.shutdown()
            } catch {
                spinner.stop(success: false, message: "Failed to connect")
                try await httpClient.shutdown()
                throw error
            }
        }
    }
    
    @available(macOS 10.15, *)
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all configured speakers"
        )
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let speakers = await config.getSpeakers()
            
            if speakers.isEmpty {
                print(UI.warning("No speakers configured"))
                print(UI.dim("Use 'kefir speaker add <name> <host>' to add a speaker"))
                return
            }
            
            print(UI.bold("Configured Speakers:"))
            print()
            
            let headers = ["Name", "Host", "Default", "Last Seen"]
            var rows: [[String]] = []
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            for speaker in speakers {
                let defaultMarker = speaker.isDefault ? "✓" : ""
                let lastSeen = dateFormatter.string(from: speaker.lastSeen)
                rows.append([speaker.name, speaker.host, defaultMarker, lastSeen])
            }
            
            let table = UI.formatTable(headers: headers, rows: rows)
            for line in table {
                print(line)
            }
        }
    }
    
    @available(macOS 10.15, *)
    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a speaker profile"
        )
        
        @Argument(help: "Name of the speaker to remove")
        var name: String
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            guard let speaker = await config.getSpeaker(byName: name) else {
                throw ValidationError("Speaker '\(name)' not found")
            }
            
            try await config.removeSpeaker(id: speaker.id)
            print(UI.success("Removed speaker '\(name)'"))
        }
    }
    
    @available(macOS 10.15, *)
    struct SetDefault: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-default",
            abstract: "Set the default speaker"
        )
        
        @Argument(help: "Name of the speaker to set as default")
        var name: String
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            guard let speaker = await config.getSpeaker(byName: name) else {
                throw ValidationError("Speaker '\(name)' not found")
            }
            
            try await config.setDefaultSpeaker(id: speaker.id)
            print(UI.success("Set '\(name)' as default speaker"))
        }
    }
}

// MARK: - Common Options

struct SpeakerOptions: ParsableArguments {
    @Argument(help: ArgumentHelp("Speaker name or IP address", valueName: "speaker"))
    var speaker: String?
    
    func resolveSpeaker() async throws -> (host: String, name: String) {
        let config = try ConfigurationManager()
        
        // If no speaker specified, use default
        if let speakerArg = speaker {
            // Check if it's a configured speaker name
            if let profile = await config.getSpeaker(byName: speakerArg) {
                return (profile.host, profile.name)
            }
            // Otherwise treat as IP/hostname
            return (speakerArg, speakerArg)
        } else {
            // Try to use default speaker
            if let defaultSpeaker = await config.getDefaultSpeaker() {
                return (defaultSpeaker.host, defaultSpeaker.name)
            }
            throw ValidationError("No speaker specified and no default configured. Use 'kefir speaker add' to configure a speaker.")
        }
    }
}

// MARK: - Power Commands

@available(macOS 10.15, *)
struct Power: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control speaker power",
        subcommands: [PowerOn.self, PowerOff.self]
    )
    
    @available(macOS 10.15, *)
    struct PowerOn: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "on",
            abstract: "Turn the speaker on"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, name) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            print("Turning on \(name)...")
            try await speaker.powerOn()
            print(UI.success("Speaker powered on"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct PowerOff: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "off",
            abstract: "Turn the speaker off"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, name) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            print("Turning off \(name)...")
            try await speaker.shutdown()
            print(UI.success("Speaker powered off"))
            try await httpClient.shutdown()
        }
    }
}

// MARK: - Volume Commands

@available(macOS 10.15, *)
struct Volume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control speaker volume",
        subcommands: [VolumeSet.self, VolumeGet.self, VolumeMute.self, VolumeUnmute.self]
    )
    
    @available(macOS 10.15, *)
    struct VolumeSet: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set speaker volume (0-100)"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        @Argument(help: "Volume level (0-100)")
        var level: Int
        
        func validate() throws {
            guard (0...100).contains(level) else {
                throw ValidationError("Volume must be between 0 and 100")
            }
        }
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.setVolume(level)
            print(UI.success("Volume set to \(level)"))
            
            // Show visual representation
            UI.drawProgressBar(value: level, max: 100, width: 40)
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct VolumeGet: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get current volume level"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            let volume = try await speaker.getVolume()
            print("Current volume: \(volume)")
            UI.drawProgressBar(value: volume, max: 100, width: 40)
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct VolumeMute: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mute",
            abstract: "Mute the speaker"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.mute()
            print(UI.success("Speaker muted 🔇"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct VolumeUnmute: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unmute",
            abstract: "Unmute the speaker"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.unmute()
            print(UI.success("Speaker unmuted 🔊"))
            try await httpClient.shutdown()
        }
    }
}

// MARK: - Source Commands

@available(macOS 10.15, *)
struct Source: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control input source",
        subcommands: [SourceSet.self, SourceGet.self, SourceList.self]
    )
    
    @available(macOS 10.15, *)
    struct SourceSet: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set input source"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        @Argument(help: "Source name (wifi, bluetooth, tv, optic, coaxial, analog, usb)")
        var source: String
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            guard let kefSource = KEFSource(rawValue: source.lowercased()) else {
                throw ValidationError("Invalid source. Available sources: \(KEFSource.allCases.map { $0.rawValue }.joined(separator: ", "))")
            }
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.setSource(kefSource)
            
            let sourceEmoji: String = {
                switch kefSource {
                case .wifi: return "📶"
                case .bluetooth: return "🔷"
                case .tv: return "📺"
                case .optic: return "💿"
                case .usb: return "🔌"
                default: return "🔊"
                }
            }()
            
            print(UI.success("Source set to \(source) \(sourceEmoji)"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct SourceGet: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get current input source"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            let source = try await speaker.getSource()
            print("Current source: \(UI.color(source.rawValue, .blue))")
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct SourceList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List available input sources"
        )
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            print(UI.bold("Available sources:"))
            for source in KEFSource.allCases {
                let emoji: String = {
                    switch source {
                    case .wifi: return "📶"
                    case .bluetooth: return "🔷"
                    case .tv: return "📺"
                    case .optic: return "💿"
                    case .coaxial: return "🔌"
                    case .analog: return "🎚️"
                    case .usb: return "🔌"
                    }
                }()
                print("  \(emoji) \(source.rawValue)")
            }
        }
    }
}

// MARK: - Playback Commands

@available(macOS 10.15, *)
struct Play: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control playback",
        subcommands: [PlayPause.self, PlayNext.self, PlayPrevious.self, PlayInfo.self]
    )
    
    @available(macOS 10.15, *)
    struct PlayPause: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pause",
            abstract: "Toggle play/pause"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.togglePlayPause()
            print(UI.success("Play/pause toggled ⏯️"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct PlayNext: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "next",
            abstract: "Skip to next track"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.nextTrack()
            print(UI.success("Skipped to next track ⏭️"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct PlayPrevious: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "previous",
            abstract: "Go to previous track"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            try await speaker.previousTrack()
            print(UI.success("Went to previous track ⏮️"))
            try await httpClient.shutdown()
        }
    }
    
    @available(macOS 10.15, *)
    struct PlayInfo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Get current track information"
        )
        
        @OptionGroup var options: SpeakerOptions
        
        func run() async throws {
            let config = try ConfigurationManager()
            let theme = await config.getTheme()
            UI.useColors = theme.useColors
            UI.useEmojis = theme.useEmojis
            
            let (host, _) = try await options.resolveSpeaker()
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            
            let speaker = KEFSpeaker(host: host, httpClient: httpClient)
            
            let isPlaying = try await speaker.isPlaying()
            
            if isPlaying {
                let songInfo = try await speaker.getSongInformation()
                
                var content: [String] = []
                if let title = songInfo.title {
                    content.append("\(UI.bold("Title:")) \(title)")
                }
                if let artist = songInfo.artist {
                    content.append("\(UI.bold("Artist:")) \(artist)")
                }
                if let album = songInfo.album {
                    content.append("\(UI.bold("Album:")) \(album)")
                }
                
                if content.isEmpty {
                    content.append(UI.dim("No track information available"))
                }
                
                UI.drawBox(title: "🎵 Now Playing", content: content)
            } else {
                print(UI.info("Nothing is currently playing"))
            }
            try await httpClient.shutdown()
        }
    }
}

// MARK: - Info Commands

@available(macOS 10.15, *)
struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get speaker information"
    )
    
    @OptionGroup var options: SpeakerOptions
    
    func run() async throws {
        let config = try ConfigurationManager()
        let theme = await config.getTheme()
        UI.useColors = theme.useColors
        UI.useEmojis = theme.useEmojis
        
        let (host, name) = try await options.resolveSpeaker()
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        
        let speaker = KEFSpeaker(host: host, httpClient: httpClient)
        
        var content: [String] = []
        
        content.append("\(UI.bold("Profile:")) \(name)")
        content.append("\(UI.bold("IP Address:")) \(host)")
        
        do {
            let speakerName = try await speaker.getSpeakerName()
            content.append("\(UI.bold("Device Name:")) \(speakerName)")
        } catch {
            content.append("\(UI.bold("Device Name:")) \(UI.dim("(unavailable)"))")
        }
        
        do {
            let mac = try await speaker.getMacAddress()
            content.append("\(UI.bold("MAC Address:")) \(mac)")
        } catch {
            content.append("\(UI.bold("MAC Address:")) \(UI.dim("(unavailable)"))")
        }
        
        do {
            let firmware = try await speaker.getFirmwareVersion()
            content.append("\(UI.bold("Model:")) \(firmware.model)")
            content.append("\(UI.bold("Firmware:")) \(firmware.version)")
        } catch {
            content.append("\(UI.bold("Model/Firmware:")) \(UI.dim("(unavailable)"))")
        }
        
        UI.drawBox(title: "Speaker Information", content: content)
        try await httpClient.shutdown()    }
}

// MARK: - Status Command

@available(macOS 10.15, *)
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get speaker status"
    )
    
    @OptionGroup var options: SpeakerOptions
    
    func run() async throws {
        let config = try ConfigurationManager()
        let theme = await config.getTheme()
        UI.useColors = theme.useColors
        UI.useEmojis = theme.useEmojis
        
        let (host, name) = try await options.resolveSpeaker()
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        
        let speaker = KEFSpeaker(host: host, httpClient: httpClient)
        
        var content: [String] = []
        
        content.append("\(UI.bold("Speaker:")) \(name)")
        
        do {
            let status = try await speaker.getStatus()
            let statusText = status == .powerOn ? UI.color("ON", .green) : UI.color("OFF", .red)
            content.append("\(UI.bold("Power:")) \(statusText)")
        } catch {
            content.append("\(UI.bold("Power:")) \(UI.dim("(unavailable)"))")
        }
        
        do {
            let source = try await speaker.getSource()
            content.append("\(UI.bold("Source:")) \(UI.color(source.rawValue, .blue))")
        } catch {
            content.append("\(UI.bold("Source:")) \(UI.dim("(unavailable)"))")
        }
        
        do {
            let volume = try await speaker.getVolume()
            content.append("\(UI.bold("Volume:")) \(volume)%")
            content.append("")
            UI.drawProgressBar(value: volume, max: 100, width: 40)
        } catch {
            content.append("\(UI.bold("Volume:")) \(UI.dim("(unavailable)"))")
        }
        
        do {
            let isPlaying = try await speaker.isPlaying()
            content.append("")
            if isPlaying {
                content.append("\(UI.bold("Playing:")) \(UI.color("Yes", .green))")
                
                if let songInfo = try? await speaker.getSongInformation() {
                    content.append("")
                    if let title = songInfo.title {
                        content.append("  \(UI.dim("Title:")) \(title)")
                    }
                    if let artist = songInfo.artist {
                        content.append("  \(UI.dim("Artist:")) \(artist)")
                    }
                }
            } else {
                content.append("\(UI.bold("Playing:")) No")
            }
        } catch {
            content.append("\(UI.bold("Playing:")) \(UI.dim("(unavailable)"))")
        }
        
        UI.drawBox(title: "Speaker Status", content: content)
        try await httpClient.shutdown()    }
}

// MARK: - Interactive Mode

@available(macOS 10.15, *)
struct Interactive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enter interactive control mode"
    )
    
    @OptionGroup var options: SpeakerOptions
    
    func run() async throws {
        let config = try ConfigurationManager()
        let theme = await config.getTheme()
        UI.useColors = theme.useColors
        UI.useEmojis = theme.useEmojis
        
        let (host, name) = try await options.resolveSpeaker()
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        
        let speaker = KEFSpeaker(host: host, httpClient: httpClient)
        
        // Update last used speaker
        if let profile = await config.getSpeaker(byName: name) {
            try await config.updateLastUsed(speakerId: profile.id)
        }
        
        print(UI.info("Entering interactive mode for \(name)..."))
        print(UI.dim("Press 'h' for help, 'q' to quit"))
        print()
        
        let interactive = await InteractiveMode(speaker: speaker, speakerName: name)
        try await interactive.run()
        
        print()
        print(UI.info("Exited interactive mode"))
        try await httpClient.shutdown()    }
}

// MARK: - Configuration Commands

@available(macOS 10.15, *)
struct Config: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure KefirCLI settings",
        subcommands: [Theme.self, Show.self]
    )
    
    @available(macOS 10.15, *)
    struct Theme: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Configure theme settings"
        )
        
        @Flag(name: .long, help: "Enable colors")
        var enableColors: Bool = false
        
        @Flag(name: .long, help: "Disable colors")
        var disableColors: Bool = false
        
        @Flag(name: .long, help: "Enable emojis")
        var enableEmojis: Bool = false
        
        @Flag(name: .long, help: "Disable emojis")
        var disableEmojis: Bool = false
        
        func run() async throws {
            let config = try ConfigurationManager()
            
            var useColors: Bool? = nil
            var useEmojis: Bool? = nil
            
            if enableColors {
                useColors = true
            } else if disableColors {
                useColors = false
            }
            
            if enableEmojis {
                useEmojis = true
            } else if disableEmojis {
                useEmojis = false
            }
            
            if useColors == nil && useEmojis == nil {
                // Show current settings
                let theme = await config.getTheme()
                print("Current theme settings:")
                print("  Colors: \(theme.useColors ? "enabled" : "disabled")")
                print("  Emojis: \(theme.useEmojis ? "enabled" : "disabled")")
            } else {
                try await config.updateTheme(useColors: useColors, useEmojis: useEmojis)
                
                let theme = await config.getTheme()
                UI.useColors = theme.useColors
                UI.useEmojis = theme.useEmojis
                
                print(UI.success("Theme updated"))
            }
        }
    }
    
    @available(macOS 10.15, *)
    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show configuration file location"
        )
        
        func run() async throws {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let configFile = homeDirectory.appendingPathComponent(".config/kefir/config.json")
            
            print("Configuration file: \(configFile.path)")
            
            if FileManager.default.fileExists(atPath: configFile.path) {
                print(UI.success("File exists"))
            } else {
                print(UI.warning("File does not exist yet"))
            }
        }
    }
}