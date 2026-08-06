import Foundation
import os

/// Debug trail for Pin Next Step → Live Activity on Lock Screen.
enum PinNowLogger {
    private static let log = Logger(subsystem: "com.samaksh.flowos.app", category: "PinNow")

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
        print("[PinNow] \(message)")
    }

    static func error(_ message: String) {
        log.error("\(message, privacy: .public)")
        print("[PinNow] ERROR: \(message)")
    }
}

struct PinNowResult: Equatable {
    let success: Bool
    let message: String

    static func ok(_ message: String) -> PinNowResult {
        PinNowResult(success: true, message: message)
    }

    static func failed(_ message: String) -> PinNowResult {
        PinNowResult(success: false, message: message)
    }
}
