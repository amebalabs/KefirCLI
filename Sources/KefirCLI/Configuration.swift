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

struct Theme: Codable {
    let useColors: Bool
    let useEmojis: Bool
    
    init(useColors: Bool = true, useEmojis: Bool = true) {
        self.useColors = useColors
        self.useEmojis = useEmojis
    }
}

struct Configuration: Codable {
    var speakers: [SpeakerProfile]
    var theme: Theme
    
    init(speakers: [SpeakerProfile] = [], theme: Theme = Theme()) {
        self.speakers = speakers
        self.theme = theme
    }
}

actor ConfigurationManager {
    private let configURL: URL
    private var configuration: Configuration
    
    init() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let configDirectory = homeDirectory.appendingPathComponent(".config/kefir")
        
        // Create config directory if it doesn't exist
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        
        self.configURL = configDirectory.appendingPathComponent("config.json")
        
        // Load existing configuration or create default
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.configuration = try decoder.decode(Configuration.self, from: data)
        } else {
            self.configuration = Configuration()
            Task {
                try await save()
            }
        }
    }
    
    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
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
        if let index = configuration.speakers.firstIndex(where: { $0.id == speakerId }) {
            configuration.speakers[index].lastSeen = Date()
        }
        try save()
    }
    
    // MARK: - Theme Management
    
    func getTheme() async -> Theme {
        return configuration.theme
    }
    
    func updateTheme(useColors: Bool? = nil, useEmojis: Bool? = nil) async throws {
        configuration.theme = Theme(
            useColors: useColors ?? configuration.theme.useColors,
            useEmojis: useEmojis ?? configuration.theme.useEmojis
        )
        try save()
    }
}