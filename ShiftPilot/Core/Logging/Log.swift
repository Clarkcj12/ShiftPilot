import OSLog

enum Log {
    private static let subsystem = "com.shiftpilot"

    static let autodrive = Logger(subsystem: subsystem, category: "autodrive")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let ble = Logger(subsystem: subsystem, category: "ble")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
