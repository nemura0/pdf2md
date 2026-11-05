import Foundation

/// Generates synthetic test PDFs. Usage: `FixtureGen --output DIR [--bench]`.
@main
struct FixtureGenCommand {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let outputFlag = arguments.firstIndex(of: "--output"),
            arguments.indices.contains(outputFlag + 1)
        else {
            FileHandle.standardError.write(Data("usage: FixtureGen --output DIR [--bench]\n".utf8))
            Foundation.exit(2)
        }
        let output = URL(fileURLWithPath: arguments[outputFlag + 1], isDirectory: true)

        try FixtureCatalog.writeCore(to: output)
        try FixtureCatalog.writeLarge(to: output)
        if arguments.contains("--bench") {
            try FixtureCatalog.writeBench(to: output)
        }
        print("fixtures: \(output.path)")
    }
}
