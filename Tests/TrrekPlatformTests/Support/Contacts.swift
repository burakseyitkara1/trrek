import CMultitouch
import TrrekEngine

/// A raw contact as the multitouch framework delivers it.
func contact(id: Int32, state: Int32, nx: Float = 0.5, ny: Float = 0.5, majorAxis: Float = 9) -> MTTouch {
    var touch = MTTouch()
    touch.identifier = id
    touch.state = state
    touch.nx = nx
    touch.ny = ny
    touch.majorAxis = majorAxis
    return touch
}

/// Records every command an engine emits.
final class CollectingSink: CommandSink, @unchecked Sendable {
    private(set) var commands: [GestureCommand] = []

    func handle(_ command: GestureCommand, device _: UInt64) {
        commands.append(command)
    }
}
