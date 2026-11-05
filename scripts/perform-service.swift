// Asks macOS to run a Service on a file, the way Finder's menu does, through the real service runner
// rather than `automator`. Usage: perform-service <service name> <file>
import AppKit

let waitSeconds = 10.0
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: perform-service <service name> <file>\n".utf8))
    exit(2)
}
let pasteboard = NSPasteboard.withUniqueName()
pasteboard.clearContents()
let url = URL(fileURLWithPath: arguments[2]) as NSURL
guard pasteboard.writeObjects([url]) else {
    FileHandle.standardError.write(Data("couldn't write the file to the pasteboard\n".utf8))
    exit(1)
}
// Finder also offers the legacy list of paths, which is what a Service's file input reads.
pasteboard.addTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType")], owner: nil)
pasteboard.setPropertyList(
    [arguments[2]],
    forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
)
_ = NSApplication.shared
let didRun = NSPerformService(arguments[1], pasteboard)
// The request can be served after the call returns, and the runner reads this pasteboard, so both
// have to stay around for it.
RunLoop.current.run(until: Date().addingTimeInterval(waitSeconds))
pasteboard.releaseGlobally()
exit(didRun ? 0 : 1)
