import Foundation
import Testing
import TrrekAppCore

struct OpenedFileQueueTests {
    private static func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    @Test func filesOpenedBeforeLaunchWaitAndTheLastIsOffered() {
        var queue = OpenedFileQueue()

        #expect(queue.receive([Self.url("First.trrek")]) == nil)
        #expect(queue.receive([Self.url("Second.trrek"), Self.url("Notes.txt")]) == nil)

        #expect(queue.finishLaunching() == Self.url("Second.trrek"))
        // Offered once.
        #expect(queue.finishLaunching() == nil)
    }

    @Test func nothingOpenedBeforeLaunchOffersNothing() {
        var queue = OpenedFileQueue()
        #expect(queue.receive([Self.url("Notes.txt")]) == nil)
        #expect(queue.finishLaunching() == nil)
    }

    @Test func afterLaunchFilesAreOfferedAtOnce() {
        var queue = OpenedFileQueue()
        _ = queue.finishLaunching()

        #expect(queue.receive([Self.url("A.trrek"), Self.url("B.TRREK")]) == Self.url("B.TRREK"))
        #expect(queue.receive([Self.url("Notes.txt")]) == nil)
        #expect(queue.receive([]) == nil)
    }
}
