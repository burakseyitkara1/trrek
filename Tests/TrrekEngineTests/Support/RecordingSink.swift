@testable import TrrekEngine

/// Records every command an engine emits, together with the originating device.
final class RecordingSink: CommandSink {
    private(set) var recorded: [(command: GestureCommand, device: UInt64)] = []

    var commands: [GestureCommand] {
        recorded.map(\.command)
    }

    func handle(_ command: GestureCommand, device: UInt64) {
        recorded.append((command, device))
    }

    func count(_ command: GestureCommand) -> Int {
        commands.filter { $0 == command }.count
    }

    func contains(_ command: GestureCommand) -> Bool {
        commands.contains(command)
    }

    func removeAll() {
        recorded.removeAll()
    }
}
