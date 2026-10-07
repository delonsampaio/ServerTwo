public enum ScoringFormat: Sendable, Equatable {
    case sideOut
    case rally(freeze: Bool)
}

extension ScoringFormat: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case freeze
    }

    private enum Kind: String, Codable {
        case sideOut
        case rally
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sideOut:
            self = .sideOut
        case .rally:
            let freeze = try container.decode(Bool.self, forKey: .freeze)
            self = .rally(freeze: freeze)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sideOut:
            try container.encode(Kind.sideOut, forKey: .kind)
        case .rally(let freeze):
            try container.encode(Kind.rally, forKey: .kind)
            try container.encode(freeze, forKey: .freeze)
        }
    }
}
