import Foundation

/// A finished Watch match as it travels to the iPhone: plain values only (no
/// SwiftData objects), so it is `Sendable`, can be decoded on the
/// WatchConnectivity delegate queue and is the single wire format both devices
/// agree on. Raw values (not enums) are kept as received so a newer app's
/// payload still decodes far enough to be rejected or acknowledged cleanly.
///
/// `schemaVersion` is bumped only when an older phone could not make sense of
/// the new shape; the phone refuses (without acknowledging) a version it does
/// not know, so the Watch keeps the match queued until the phone app updates.
public struct SyncedMatchPayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public struct Point: Codable, Sendable, Equatable {
        public var sequenceNumber: Int
        public var scoringTeamRawValue: String
        public var teamAScoreAfter: Int
        public var teamBScoreAfter: Int

        public init(sequenceNumber: Int, scoringTeamRawValue: String, teamAScoreAfter: Int, teamBScoreAfter: Int) {
            self.sequenceNumber = sequenceNumber
            self.scoringTeamRawValue = scoringTeamRawValue
            self.teamAScoreAfter = teamAScoreAfter
            self.teamBScoreAfter = teamBScoreAfter
        }
    }

    public struct Game: Codable, Sendable, Equatable {
        public var number: Int
        public var teamAFinalScore: Int
        public var teamBFinalScore: Int
        public var winningTeamRawValue: String
        public var completedAt: Date?
        public var points: [Point]

        public init(
            number: Int,
            teamAFinalScore: Int,
            teamBFinalScore: Int,
            winningTeamRawValue: String,
            completedAt: Date?,
            points: [Point]
        ) {
            self.number = number
            self.teamAFinalScore = teamAFinalScore
            self.teamBFinalScore = teamBFinalScore
            self.winningTeamRawValue = winningTeamRawValue
            self.completedAt = completedAt
            self.points = points
        }
    }

    public var schemaVersion: Int
    public var id: UUID
    public var startedAt: Date
    public var completedAt: Date
    public var matchFormatRawValue: Int
    public var configurationData: Data
    public var winningTeamRawValue: String
    public var teamAName: String
    public var teamBName: String
    public var games: [Game]

    public init(
        schemaVersion: Int = SyncedMatchPayload.currentSchemaVersion,
        id: UUID,
        startedAt: Date,
        completedAt: Date,
        matchFormatRawValue: Int,
        configurationData: Data,
        winningTeamRawValue: String,
        teamAName: String,
        teamBName: String,
        games: [Game]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.matchFormatRawValue = matchFormatRawValue
        self.configurationData = configurationData
        self.winningTeamRawValue = winningTeamRawValue
        self.teamAName = teamAName
        self.teamBName = teamBName
        self.games = games
    }

    /// Builds the payload from a saved match. Games and points are written in
    /// order (SwiftData's to-many arrays are unordered). Must be called where
    /// the record's context lives (the main actor on the Watch).
    public init(record: MatchRecord) {
        let sides = record.teamSides ?? []
        let games = (record.games ?? []).sorted { $0.gameNumber < $1.gameNumber }.map { game in
            Game(
                number: game.gameNumber,
                teamAFinalScore: game.teamAFinalScore,
                teamBFinalScore: game.teamBFinalScore,
                winningTeamRawValue: game.winningTeamRawValue,
                completedAt: game.completedAt,
                points: game.orderedPoints.map {
                    Point(
                        sequenceNumber: $0.sequenceNumber,
                        scoringTeamRawValue: $0.scoringTeamRawValue,
                        teamAScoreAfter: $0.teamAScoreAfter,
                        teamBScoreAfter: $0.teamBScoreAfter
                    )
                }
            )
        }
        self.init(
            id: record.id,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            matchFormatRawValue: record.matchFormatRawValue,
            configurationData: record.configurationData,
            winningTeamRawValue: record.winningTeamRawValue,
            teamAName: sides.first { $0.team == .teamA }?.displayName ?? TeamNaming.placeholderName(for: .teamA),
            teamBName: sides.first { $0.team == .teamB }?.displayName ?? TeamNaming.placeholderName(for: .teamB),
            games: games
        )
    }

    // MARK: JSON

    /// Stable bytes for the same payload (sorted keys, dates as numbers), so a
    /// resend of the same match is byte-identical and tests can compare.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> SyncedMatchPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(SyncedMatchPayload.self, from: data)
    }
}

/// The WatchConnectivity `userInfo` dictionaries, in one place so the Watch's
/// sender, the phone's receiver and the tests cannot drift apart.
public enum SyncedMatchWire {
    public static let matchIDKey = "matchID"
    public static let schemaKey = "schema"
    public static let payloadKey = "payload"
    /// The phone's acknowledgement back to the Watch.
    public static let acknowledgementKey = "syncedMatchID"

    public static func acknowledgementUserInfo(for matchID: UUID) -> [String: Any] {
        [acknowledgementKey: matchID.uuidString]
    }

    public static func acknowledgedMatchID(in userInfo: [String: Any]) -> UUID? {
        (userInfo[acknowledgementKey] as? String).flatMap(UUID.init(uuidString:))
    }

    /// The id of the match a (Watch to phone) transfer carries, for the
    /// Watch's check of its outstanding transfers.
    public static func matchID(in userInfo: [String: Any]) -> UUID? {
        (userInfo[matchIDKey] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// What the Watch hands to `transferUserInfo`.
public struct SyncedMatchMessage: Sendable, Equatable {
    public let matchID: UUID
    public let schema: Int
    public let payload: Data

    public init(matchID: UUID, schema: Int = SyncedMatchPayload.currentSchemaVersion, payload: Data) {
        self.matchID = matchID
        self.schema = schema
        self.payload = payload
    }

    public var userInfo: [String: Any] {
        [
            SyncedMatchWire.matchIDKey: matchID.uuidString,
            SyncedMatchWire.schemaKey: schema,
            SyncedMatchWire.payloadKey: payload
        ]
    }
}

/// A received transfer, already pulled out of the untyped dictionary and
/// decoded, so it is `Sendable` and can hop to the main actor. Built on the
/// WatchConnectivity delegate queue.
public struct IncomingSyncedMatch: Sendable, Equatable {
    /// The id the Watch labelled the transfer with; the only thing that can be
    /// acknowledged when the payload itself is unusable.
    public let matchID: UUID?
    public let schema: Int?
    /// `nil` when missing or undecodable, and deliberately not even attempted
    /// for a newer schema (its shape may differ).
    public let payload: SyncedMatchPayload?

    public init(matchID: UUID?, schema: Int?, payload: SyncedMatchPayload?) {
        self.matchID = matchID
        self.schema = schema
        self.payload = payload
    }

    /// `nil` when the dictionary is not a match transfer at all.
    public init?(userInfo: [String: Any]) {
        let matchID = SyncedMatchWire.matchID(in: userInfo)
        let schema = userInfo[SyncedMatchWire.schemaKey] as? Int
        let data = userInfo[SyncedMatchWire.payloadKey] as? Data
        guard matchID != nil || data != nil else { return nil }
        self.matchID = matchID
        self.schema = schema
        if let data, (schema ?? SyncedMatchPayload.currentSchemaVersion) <= SyncedMatchPayload.currentSchemaVersion {
            self.payload = try? SyncedMatchPayload.decode(from: data)
        } else {
            self.payload = nil
        }
    }
}
