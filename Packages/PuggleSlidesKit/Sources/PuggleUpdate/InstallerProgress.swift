import Foundation

/// How far macOS's installer has got, read from what `installer -verboseR` prints:
///
///     installer:PHASE:Preparing for installation…
///     installer:%9.750000
///     installer:PHASE:Writing files…
///     installer:%62.181818
///     installer:PHASE:The software was successfully installed.
///     installer: The upgrade was successful.
public struct InstallerProgress: Equatable, Sendable {
    /// From 0 to 1, once the installer has said.
    public var fraction: Double?
    /// What it's doing now, in its words ("Writing files…").
    public var phase: String?
    /// It said the installation succeeded.
    public var succeeded = false
    /// Errors it reported.
    public var errors: [String] = []

    public init() {}

    /// Everything the installer printed so far.
    public static func parse(_ output: String) -> InstallerProgress {
        var progress = InstallerProgress()
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("installer:") else { continue }
            let message = line.dropFirst("installer:".count)
            if message.hasPrefix("%"), let percent = Double(message.dropFirst().trimmingCharacters(in: .whitespaces)) {
                progress.fraction = min(1, max(progress.fraction ?? 0, percent / 100))
            } else if message.hasPrefix("PHASE:") {
                let phase = message.dropFirst("PHASE:".count).trimmingCharacters(in: .whitespaces)
                if !phase.isEmpty { progress.phase = phase }
            } else if message.hasPrefix(" The upgrade was successful") || message.hasPrefix(" The install was successful") {
                progress.succeeded = true
                progress.fraction = 1
            } else if message.hasPrefix(" Error") || message.hasPrefix(" Cannot install") {
                progress.errors.append(message.trimmingCharacters(in: .whitespaces))
            }
        }
        return progress
    }
}
