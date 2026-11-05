/// Why a file couldn't be converted. `reason` is short enough for a notification.
public struct ConversionFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var description: String { reason }
}
