import Dispatch
import Foundation

/// Turns termination signals into an orderly quit.
///
/// A plain SIGTERM or SIGINT (`kill`, Ctrl-C in a terminal, a logout that does not go through the app) would end
/// the process at once, with Command possibly still held down for the app switcher. Each signal's default action is
/// ignored and a dispatch source calls `handler` on `queue` instead, where the app releases everything it holds and
/// exits.
public final class TerminationSignals {
    /// The signals the app handles: SIGTERM and SIGINT.
    public static let defaultSignals: [Int32] = [SIGTERM, SIGINT]

    private let signals: [Int32]
    private var sources: [any DispatchSourceSignal]

    /// Ignores the default action of each signal in `signals` and calls `handler` with the signal's number on
    /// `queue` whenever it arrives.
    public init(
        signals: [Int32] = TerminationSignals.defaultSignals,
        queue: DispatchQueue = .main,
        handler: @escaping @Sendable (Int32) -> Void
    ) {
        self.signals = signals
        sources = signals.map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { handler(number) }
            source.resume()
            return source
        }
    }

    deinit {
        cancel()
    }

    /// Stops handling the signals and restores their default actions.
    public func cancel() {
        for source in sources {
            source.cancel()
        }
        sources = []
        for number in signals {
            signal(number, SIG_DFL)
        }
    }
}
