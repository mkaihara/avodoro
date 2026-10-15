import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.avodoro"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let log = Logger(subsystem: subsystem, category: "log")
}
