import Foundation
import CoreGraphics

enum SystemBridge {
    @discardableResult
    static func copyText(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do {
            try process.run()
            if let data = text.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    @discardableResult
    static func openURLExternally(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    static var isCommandPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskCommand) ?? false
    }

    static var isShiftPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskShift) ?? false
    }

    static var isOptionPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskAlternate) ?? false
    }
}
