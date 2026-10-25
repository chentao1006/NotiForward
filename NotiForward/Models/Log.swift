import os

/// Unified logging. View with:
/// log stream --level debug --predicate 'subsystem == "com.ct106.notiforward"'
enum Log {
    static let capture = Logger(subsystem: "com.ct106.notiforward", category: "capture")
    static let forward = Logger(subsystem: "com.ct106.notiforward", category: "forward")
}
