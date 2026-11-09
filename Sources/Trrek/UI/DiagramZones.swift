import CoreGraphics
import TrrekEngine

/// A trackpad's surface size in millimetres, which the diagram draws to scale.
struct TrackpadSize: Equatable {
    var widthMM: CGFloat
    var heightMM: CGFloat

    /// The size drawn while trrek knows no trackpad (none found, or the multitouch stream is stopped): a typical
    /// laptop trackpad.
    static let typical = TrackpadSize(widthMM: 140, heightMM: 90)

    var isValid: Bool {
        widthMM > 0 && heightMM > 0
    }

    /// The trackpad the diagram draws: the built-in one, else the first with a surface size; `nil` when none has one.
    static func preferred(among devices: [DeviceGeometry]) -> TrackpadSize? {
        let sized = devices.filter(\.isValid)
        guard let device = sized.first(where: \.isBuiltIn) ?? sized.first else { return nil }
        return TrackpadSize(widthMM: CGFloat(device.widthMM), heightMM: CGFloat(device.heightMM))
    }
}

/// The edge touch zones of the trackpad diagram, to scale with the trackpad.
///
/// The diagram is `width` wide and takes the trackpad's aspect ratio when that fits under `maxHeight`; otherwise it
/// is `maxHeight` high and each axis keeps its own scale. A zone reaches in from its edge by the edge width, scaled
/// along the axis it crosses: the side zones by the trackpad's width, the top and bottom ones by its height, as the
/// engine measures them (`Geometry.zone`). Where two zones meet is a corner. With Bottom Quarter Only a side zone
/// starts slides only below the bottom quarter of the trackpad's height; the rest of it is drawn faint.
struct DiagramZones: Equatable {
    /// The diagram's size in points.
    let size: CGSize
    /// How far the left and right zones reach in from their edge, in points.
    let sideThickness: CGFloat
    /// How far the top and bottom zones reach in from their edge, in points.
    let endThickness: CGFloat
    let bottomQuarterOnly: Bool

    /// Space between a zone and its edge's label.
    static let labelGap: CGFloat = 4
    /// The most of the diagram's width or height a zone may take, so labels keep room on a trackpad far smaller
    /// than any real one.
    static let maximumShare: CGFloat = 0.25
    /// The coloured line along each zone.
    static let stripThickness: CGFloat = 5
    /// Kept clear at each end of a zone's line.
    private static let stripMargin: CGFloat = 3

    init(
        trackpad: TrackpadSize,
        edgeWidthMM: CGFloat,
        bottomQuarterOnly: Bool,
        width: CGFloat,
        maxHeight: CGFloat
    ) {
        let pad = trackpad.isValid ? trackpad : .typical
        size = Self.diagramSize(for: pad, width: width, maxHeight: maxHeight)
        sideThickness = min(edgeWidthMM / pad.widthMM * size.width, size.width * Self.maximumShare)
        endThickness = min(edgeWidthMM / pad.heightMM * size.height, size.height * Self.maximumShare)
        self.bottomQuarterOnly = bottomQuarterOnly
    }

    /// `width` wide with the trackpad's aspect ratio, or `maxHeight` high when that ratio would not fit.
    static func diagramSize(for trackpad: TrackpadSize, width: CGFloat, maxHeight: CGFloat) -> CGSize {
        let pad = trackpad.isValid ? trackpad : .typical
        return CGSize(width: width, height: min(maxHeight, (width * pad.heightMM / pad.widthMM).rounded()))
    }

    /// A corner zone: where a side zone and a top or bottom zone meet.
    var cornerSize: CGSize {
        CGSize(width: sideThickness, height: endThickness)
    }

    /// The length of the top and bottom zones between their corners.
    var endLength: CGFloat {
        size.width - 2 * sideThickness
    }

    /// The length of the left and right zones between their corners.
    var sideLength: CGFloat {
        size.height - 2 * endThickness
    }

    /// The part of a side zone, from its bottom corner up, where a touch starts a slide: all of it, or with Bottom
    /// Quarter Only the part below the bottom quarter of the trackpad's height. The bottom corner below it also
    /// starts slides along the side edge.
    var activeSideLength: CGFloat {
        guard bottomQuarterOnly else { return sideLength }
        let quarter = size.height * CGFloat(Geometry.bottomQuarter)
        return min(max(quarter - endThickness, 0), sideLength)
    }

    /// The part of a side zone above `activeSideLength`, drawn faint.
    var inactiveSideLength: CGFloat {
        sideLength - activeSideLength
    }

    /// The length of the top and bottom zones' line.
    var endStripLength: CGFloat {
        max(min(size.width * 0.5, endLength - 2 * Self.stripMargin), 0)
    }

    /// The length of a side zone's line, which runs along its active part; at least a dot while that part has room
    /// for one.
    var sideStripLength: CGFloat {
        let room = max(activeSideLength - 2 * Self.stripMargin, min(Self.stripThickness, activeSideLength))
        return bottomQuarterOnly ? room : min(size.height * 0.45, room)
    }

    /// The widest a side edge's label gets: up to the middle of the diagram, less a margin, so the left and right
    /// labels never meet; a longer one wraps onto a second line.
    var sideLabelWidth: CGFloat {
        max(size.width / 2 - sideThickness - Self.labelGap - 4, 0)
    }
}
