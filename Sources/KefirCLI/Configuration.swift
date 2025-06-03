import Foundation

struct SpeakerProfile: Codable {
    let id: UUID
    let name: String
    let host: String
    let isDefault: Bool
    var lastSeen: Date
    
    init(name: String, host: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.isDefault = isDefault
        self.lastSeen = Date()
    }
}

struct KefirConfiguration: Codable {
    var speakers: [SpeakerProfile]
    var lastUsedSpeakerId: UUID?
    var theme: Theme
    
    struct Theme: Codable {
        var useColors: Bool
        var useEmojis: Bool
        
        static let `default` = Theme(useColors: true, useEmojis: true)
    }
    
    static let `default` = KefirConfiguration(speakers: [], lastUsedSpeakerId: nil, theme: .default)
}

actor ConfigurationManager {
    private let configURL: URL
    private var configuration: KefirConfiguration
    
    init() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let configDirectory = homeDirectory.appendingPathComponent(".config/kefir")
        
        // Create config directory if it doesn't exist
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        
        self.configURL = configDirectory.appendingPathComponent("config.json")
        
        // Load existing configuration or create default
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            self.configuration = try JSONDecoder().decode(KefirConfiguration.self, from: data)
        } else {
            self.configuration = .default
            Task {
                try await save()
            }
        }
    }
    
    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configURL)
    }
    
    // MARK: - Speaker Management
    
    func addSpeaker(name: String, host: String, setAsDefault: Bool = false) async throws -> SpeakerProfile {
        // Check if speaker with same host already exists
        if let existingIndex = configuration.speakers.firstIndex(where: { $0.host == host }) {
            // Update existing speaker
            configuration.speakers[existingIndex].lastSeen = Date()
            if setAsDefault {
                // Remove default from all other speakers
                for i in 0..<configuration.speakers.count {
                    configuration.speakers[i] = SpeakerProfile(
                        name: configuration.speakers[i].name,
                        host: configuration.speakers[i].host,
                        isDefault: i == existingIndex
                    )
                }
            }
            try save()
            return configuration.speakers[existingIndex]
        }
        
        // Add new speaker
        let newSpeaker = SpeakerProfile(name: name, host: host, isDefault: setAsDefault)
        
        if setAsDefault {
            // Remove default from all other speakers
            for i in 0..<configuration.speakers.count {
                configuration.speakers[i] = SpeakerProfile(
                    name: configuration.speakers[i].name,
                    host: configuration.speakers[i].host,
                    isDefault: false
                )
            }
        }
        
        configuration.speakers.append(newSpeaker)
        try save()
        return newSpeaker
    }
    
    func removeSpeaker(id: UUID) async throws {
        configuration.speakers.removeAll { $0.id == id }
        if configuration.lastUsedSpeakerId == id {
            configuration.lastUsedSpeakerId = nil
        }
        try save()
    }
    
    func getSpeakers() async -> [SpeakerProfile] {
        return configuration.speakers
    }
    
    func getSpeaker(byName name: String) async -> SpeakerProfile? {
        return configuration.speakers.first { $0.name.lowercased() == name.lowercased() }
    }
    
    func getSpeaker(byId id: UUID) async -> SpeakerProfile? {
        return configuration.speakers.first { $0.id == id }
    }
    
    func getDefaultSpeaker() async -> SpeakerProfile? {
        return configuration.speakers.first { $0.isDefault }
    }
    
    func setDefaultSpeaker(id: UUID) async throws {
        for i in 0..<configuration.speakers.count {
            configuration.speakers[i] = SpeakerProfile(
                name: configuration.speakers[i].name,
                host: configuration.speakers[i].host,
                isDefault: configuration.speakers[i].id == id
            )
        }
        try save()
    }
    
    func updateLastUsed(speakerId: UUID) async throws {
        configuration.lastUsedSpeakerId = speakerId
        if let index = configuration.speakers.firstIndex(where: { $0.id == speakerId }) {
            configuration.speakers[index].lastSeen = Date()
        }
        try save()
    }
    
    // MARK: - Theme Management
    
    func getTheme() async -> KefirConfiguration.Theme {
        return configuration.theme
    }
    
    func updateTheme(useColors: Bool? = nil, useEmojis: Bool? = nil) async throws {
        if let useColors = useColors {
            configuration.theme.useColors = useColors
        }
        if let useEmojis = useEmojis {
            configuration.theme.useEmojis = useEmojis
        }
        try save()
    }
}