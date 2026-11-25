import CoreGraphics
import Foundation

/// How window clearance changes one window under the bar. A window found again at the frame it was changed from
/// didn't keep the change: macOS puts back a window it has just filled from its title bar for about a third of a
/// second. So the change is tried again after a wait, a few times, and then the window is left alone until it moves or
/// becomes clear, so clearance doesn't fight an app that refuses the change.
struct WindowAdjustment: StateMachine {
    enum Event {
        /// A pass found the window at `frame`; `target` is its frame clear of the bar, nil when it already is.
        case seen(frame: CGRect, target: CGRect?, at: Date)
    }

    enum Effect: Equatable {
        /// Resizes the window in place; the owner then looks at it again.
        case resize(CGSize)
        case move(CGPoint)
        /// Looks at the window again at this time.
        case checkAgain(at: Date)
    }

    /// The waits before each new try at a change the window didn't keep.
    static let retryDelays: [TimeInterval] = [0.5, 1, 2]

    private enum Mode {
        case clear
        /// Changed the window from `from`, after `retries` waits since it was last clear.
        case changed(from: CGRect, retries: Int)
        case waiting(from: CGRect, until: Date, retries: Int)

        var retries: Int {
            switch self {
            case .clear: 0
            case .changed(_, let retries), .waiting(_, _, let retries): retries
            }
        }
    }

    private var mode = Mode.clear

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .seen(let frame, let target, let now):
            guard let target else {
                mode = .clear
                return []
            }
            switch mode {
            case .changed(frame, let retries):
                guard retries < Self.retryDelays.count else { return [] }
                let retry = now.addingTimeInterval(Self.retryDelays[retries])
                mode = .waiting(from: frame, until: retry, retries: retries + 1)
                return [.checkAgain(at: retry)]
            case .waiting(frame, let retry, _) where now < retry:
                return [.checkAgain(at: retry)]
            default:
                mode = .changed(from: frame, retries: mode.retries)
                return [target.size == frame.size ? .move(target.origin) : .resize(target.size)]
            }
        }
    }
}
