import Foundation

/// Real Vision requests fail on the hosted CI image, so tests that need them can't run there
/// (ADR-0008). Only the CI workflow sets this. Everywhere else they run.
enum CIEnvironment {
    static let hasVision = ProcessInfo.processInfo.environment["PDF2MD_CI_NO_VISION"] == nil
}
