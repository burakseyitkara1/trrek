/// A release version `major.minor.patch`, as in the release tags (`v0.3.0`) and `TrrekVersion.string`.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `X.Y.Z` with an optional leading `v` or `V`. Anything else (a missing or extra component, a sign, a
    /// suffix such as `-beta`, surrounding spaces) is `nil`.
    public init?(_ text: String) {
        var body = Substring(text)
        if let first = body.first, first == "v" || first == "V" {
            body = body.dropFirst()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            // Digits only, so `+1` and ` 1` are refused; at most nine keep the value within `Int`.
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// `X.Y.Z`, without the `v`.
    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Stored as its `X.Y.Z` text.
extension SemanticVersion: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let version = SemanticVersion(text) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "not a version: \(text)")
            )
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
