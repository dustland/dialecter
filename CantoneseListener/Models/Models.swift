import Foundation
import SwiftData

/// Time-synced transcript line representing a single spoke segment.
public struct TranscriptLine: Codable, Identifiable {
    public var id: UUID
    public var startTimestamp: TimeInterval
    public var endTimestamp: TimeInterval
    public var cantoneseText: String
    public var translationText: String
    
    public init(id: UUID = UUID(), startTimestamp: TimeInterval, endTimestamp: TimeInterval, cantoneseText: String, translationText: String) {
        self.id = id
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.cantoneseText = cantoneseText
        self.translationText = translationText
    }
}

/// SwiftData model representing a recorded listening session.
@Model
public final class Session {
    @Attribute(.unique) public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var duration: TimeInterval
    public var audioFilePath: String // Relative path to session audio file in document directory
    public var isProcessed: Bool
    
    // Serialized array of transcript lines representing the dialogue
    public var transcript: [TranscriptLine]
    
    // Relationship: deletes bookmarks cascade when session is deleted
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.session)
    public var bookmarks: [Bookmark]
    
    public init(id: UUID = UUID(), startTime: Date = Date(), audioFilePath: String) {
        self.id = id
        self.startTime = startTime
        self.audioFilePath = audioFilePath
        self.duration = 0.0
        self.isProcessed = false
        self.transcript = []
        self.bookmarks = []
    }
}

/// SwiftData model representing a timestamped bookmark within a listening session.
@Model
public final class Bookmark {
    @Attribute(.unique) public var id: UUID
    public var timestamp: TimeInterval // Time offset in seconds from session start
    public var note: String?
    
    // Back-reference to the parent Session
    public var session: Session?
    
    public init(id: UUID = UUID(), timestamp: TimeInterval, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.note = note
    }
}
