import CoreGraphics
import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine

/// The trackpad diagram's edge zones, to scale with the trackpad, and where its size comes from.
@MainActor
struct DiagramZonesTests {
    private static let pad = TrackpadSize(widthMM: 120, heightMM: 80)

    private static func zones(
        _ width: EdgeWidth = .standard,
        trackpad: TrackpadSize = pad,
        bottomQuarterOnly: Bool = false,
        maxHeight: CGFloat = 180
    ) -> DiagramZones {
        DiagramZones(
            trackpad: trackpad,
            edgeWidthMM: CGFloat(width.millimetres),
            bottomQuarterOnly: bottomQuarterOnly,
            width: 270,
            maxHeight: maxHeight
        )
    }

    // MARK: - Size and thickness

    @Test func diagramTakesTheTrackpadsAspectRatioWhenItFits() {
        #expect(Self.zones().size == CGSize(width: 270, height: 180))
        let wide = TrackpadSize(widthMM: 160, heightMM: 100)
        #expect(Self.zones(trackpad: wide).size == CGSize(width: 270, height: 169))
    }

    @Test func diagramKeepsItsFrameWhenTheRatioDoesNotFit() {
        #expect(Self.zones(maxHeight: 150).size == CGSize(width: 270, height: 150))
    }

    @Test func zoneThicknessIsTheEdgeWidthToScale() {
        for width in EdgeWidth.allCases {
            let millimetres = CGFloat(width.millimetres)
            let zones = Self.zones(width)
            #expect(zones.sideThickness == millimetres / 120 * 270)
            #expect(zones.endThickness == millimetres / 80 * 180)
        }
        let narrow = Self.zones(.narrow)
        let standard = Self.zones(.standard)
        let wide = Self.zones(.wide)
        #expect(narrow.sideThickness < standard.sideThickness && standard.sideThickness < wide.sideThickness)
        // 10 mm across a 120 mm trackpad drawn 270 pt wide.
        #expect(abs(standard.sideThickness - 22.5) < 0.001)
    }

    @Test func eachAxisKeepsItsOwnScaleInAFlatterFrame() {
        let zones = Self.zones(.wide, maxHeight: 150)
        #expect(zones.sideThickness == 14.0 / 120 * 270)
        #expect(zones.endThickness == 14.0 / 80 * 150)
    }

    @Test func cornerIsWhereTwoZonesMeet() {
        let zones = Self.zones(.wide)
        #expect(zones.cornerSize == CGSize(width: zones.sideThickness, height: zones.endThickness))
        #expect(abs(zones.endLength + 2 * zones.cornerSize.width - zones.size.width) < 0.001)
        #expect(abs(zones.sideLength + 2 * zones.cornerSize.height - zones.size.height) < 0.001)
    }

    @Test func unknownOrInvalidTrackpadFallsBackToTypicalSize() {
        #expect(TrackpadSize.typical == TrackpadSize(widthMM: 140, heightMM: 90))
        let invalid = Self.zones(trackpad: TrackpadSize(widthMM: 0, heightMM: 0))
        #expect(invalid == Self.zones(trackpad: .typical))
        #expect(invalid.size == CGSize(width: 270, height: 174))
        #expect(invalid.sideThickness == 10.0 / 140 * 270)
    }

    @Test func zonesLeaveRoomOnATinyTrackpad() {
        let zones = Self.zones(.wide, trackpad: TrackpadSize(widthMM: 20, heightMM: 15))
        #expect(zones.sideThickness == 270 * DiagramZones.maximumShare)
        #expect(zones.endThickness == zones.size.height * DiagramZones.maximumShare)
    }

    // MARK: - Bottom Quarter Only

    @Test func sideZoneIsWholeWithoutBottomQuarterOnly() {
        let zones = Self.zones()
        #expect(zones.activeSideLength == zones.sideLength)
        #expect(zones.inactiveSideLength == 0)
    }

    @Test func bottomQuarterOnlyFillsTheSideZoneBelowTheQuarter() {
        for width in EdgeWidth.allCases {
            let zones = Self.zones(width, bottomQuarterOnly: true)
            // The active part and the bottom corner below it reach up to a quarter of the height, as in the engine.
            let quarter = zones.size.height * CGFloat(Geometry.bottomQuarter)
            #expect(abs(zones.activeSideLength + zones.endThickness - quarter) < 0.001)
            #expect(abs(zones.activeSideLength + zones.inactiveSideLength - zones.sideLength) < 0.001)
            #expect(zones.inactiveSideLength > zones.activeSideLength)
        }
    }

    @Test func sideLabelsNeverMeet() {
        for width in EdgeWidth.allCases {
            for maxHeight in [150, 180] as [CGFloat] {
                let zones = Self.zones(width, trackpad: .typical, maxHeight: maxHeight)
                let reach = zones.sideThickness + DiagramZones.labelGap + zones.sideLabelWidth
                #expect(2 * reach < zones.size.width)
            }
        }
    }

    // MARK: - Trackpad size source

    @Test func builtInTrackpadComesFirst() {
        let external = DeviceGeometry(widthMM: 160, heightMM: 115, isBuiltIn: false)
        let builtIn = DeviceGeometry(widthMM: 122, heightMM: 74, isBuiltIn: true)
        #expect(TrackpadSize.preferred(among: [external, builtIn]) == TrackpadSize(widthMM: 122, heightMM: 74))
        #expect(TrackpadSize.preferred(among: [external]) == TrackpadSize(widthMM: 160, heightMM: 115))
    }

    @Test func noSizedTrackpadIsUnknown() {
        #expect(TrackpadSize.preferred(among: []) == nil)
        let sizeless = DeviceGeometry(widthMM: 0, heightMM: 0, isBuiltIn: true)
        #expect(TrackpadSize.preferred(among: [sizeless]) == nil)
        let external = DeviceGeometry(widthMM: 160, heightMM: 115, isBuiltIn: false)
        #expect(TrackpadSize.preferred(among: [sizeless, external]) == TrackpadSize(widthMM: 160, heightMM: 115))
    }

    @Test func modelDrawsTheKnownTrackpadOrATypicalOne() {
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }
        #expect(model.trackpadSize == nil)
        #expect(model.diagramTrackpad == .typical)
        let known = TrackpadSize(widthMM: 122, heightMM: 74)
        model.trackpadSize = known
        #expect(model.diagramTrackpad == known)
        let given = SettingsModel(settings: AppSettings(), backlightAvailable: true, trackpadSize: known) { _ in }
        #expect(given.diagramTrackpad == known)
    }

    @Test func openWindowsFollowTheTrackpadFound() {
        let registry = WindowRegistry()
        let settingsModel = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }
        let welcomeModel = WelcomeModel(settings: AppSettings(), backlightAvailable: true, accessibilityGranted: true)
        registry.settingsModel = settingsModel
        registry.welcomeModel = welcomeModel
        let known = TrackpadSize(widthMM: 122, heightMM: 74)
        registry.trackpadSize = known
        #expect(settingsModel.diagramTrackpad == known)
        #expect(welcomeModel.trackpadSize == known)
    }

    @Test func zonesFollowTheSettings() {
        var settings = AppSettings()
        settings.edgeWidth = .wide
        settings.bottomQuarterOnly = true
        let diagram = TrackpadDiagram(
            settings: settings,
            backlightAvailable: true,
            accessibilityGranted: true,
            maxHeight: TrackpadDiagram.compactHeight,
            trackpad: Self.pad
        )
        #expect(diagram.zones == Self.zones(.wide, bottomQuarterOnly: true, maxHeight: TrackpadDiagram.compactHeight))
    }
}
