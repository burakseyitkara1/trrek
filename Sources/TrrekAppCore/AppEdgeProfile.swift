import TrrekEngine

/// The edge actions for one app, used while it is in front. An edge set to `nil` runs the All Apps action.
public struct AppEdgeProfile: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var left: EdgeAction?
    public var right: EdgeAction?
    public var top: EdgeAction?
    public var bottom: EdgeAction?

    public init(
        bundleID: String,
        left: EdgeAction? = nil,
        right: EdgeAction? = nil,
        top: EdgeAction? = nil,
        bottom: EdgeAction? = nil
    ) {
        self.bundleID = bundleID
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    /// Decodes forgivingly: an edge whose value cannot be read (such as an action this build does not know) is
    /// `nil`, the same as All Apps. A missing, unreadable or empty bundle ID throws, and the profile is dropped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        guard !bundleID.isEmpty else { throw EmptyBundleID() }
        left = Self.edge(container, .left)
        right = Self.edge(container, .right)
        top = Self.edge(container, .top)
        bottom = Self.edge(container, .bottom)
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, left, right, top, bottom
    }

    /// Thrown for a profile with an empty bundle ID.
    private struct EmptyBundleID: Error {}

    private static func edge(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> EdgeAction? {
        guard let value = try? container.decodeIfPresent(EdgeAction.self, forKey: key) else { return nil }
        return value
    }

    /// One edge's own action, or `nil` for the All Apps action.
    public subscript(edge edge: Edge) -> EdgeAction? {
        get {
            switch edge {
            case .left: left
            case .right: right
            case .top: top
            case .bottom: bottom
            }
        }
        set {
            switch edge {
            case .left: left = newValue
            case .right: right = newValue
            case .top: top = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    /// Whether at least one edge has its own action.
    public var hasOverrides: Bool {
        left != nil || right != nil || top != nil || bottom != nil
    }
}

/// The action of each of the four edges.
public struct EdgeActions: Equatable, Sendable {
    public var left: EdgeAction
    public var right: EdgeAction
    public var top: EdgeAction
    public var bottom: EdgeAction

    public init(left: EdgeAction, right: EdgeAction, top: EdgeAction, bottom: EdgeAction) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public subscript(edge: Edge) -> EdgeAction {
        switch edge {
        case .left: left
        case .right: right
        case .top: top
        case .bottom: bottom
        }
    }
}

/// Reads a list element by element, so one element that cannot be read is skipped instead of failing the list.
struct ForgivingElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: any Decoder) throws {
        value = try? Element(from: decoder)
    }
}

public extension Settings {
    /// The most apps with their own edges; a longer stored list keeps its first ones.
    static let maximumEdgeProfiles = 50

    /// The profile of the app with `bundleID`, if it has one.
    func edgeProfile(for bundleID: String?) -> AppEdgeProfile? {
        guard let bundleID else { return nil }
        return appEdgeProfiles.first { $0.bundleID == bundleID }
    }

    /// The edge actions while the app with `bundleID` is in front: its profile's own actions over the All Apps ones.
    /// `nil`, or an app without a profile, gets the All Apps actions.
    func edgeActions(for bundleID: String?) -> EdgeActions {
        let profile = edgeProfile(for: bundleID)
        return EdgeActions(
            left: profile?.left ?? leftEdge,
            right: profile?.right ?? rightEdge,
            top: profile?.top ?? topEdge,
            bottom: profile?.bottom ?? bottomEdge
        )
    }

    /// Changes the profile of the app with `bundleID`; does nothing when it has none.
    mutating func updateEdgeProfile(for bundleID: String, _ change: (inout AppEdgeProfile) -> Void) {
        guard let index = appEdgeProfiles.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        change(&appEdgeProfiles[index])
    }

    /// `profiles` without trrek itself, empty or repeated bundle IDs (the first one is kept), and at most
    /// `maximumEdgeProfiles` of them.
    static func sanitized(_ profiles: [AppEdgeProfile]) -> [AppEdgeProfile] {
        var seen = Set<String>()
        var result: [AppEdgeProfile] = []
        for profile in profiles where result.count < maximumEdgeProfiles {
            guard !profile.bundleID.isEmpty, profile.bundleID != AppIdentity.bundleID,
                  seen.insert(profile.bundleID).inserted
            else { continue }
            result.append(profile)
        }
        return result
    }
}
