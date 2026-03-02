import Foundation
import os

enum CacheJanitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "Cache"
    )

    static func prepareForLaunch() {
        disableSharedURLCache(reason: "launch")
    }

    static func cleanupTransientCaches(reason: String) {
        disableSharedURLCache(reason: reason)
    }

    private static func disableSharedURLCache(reason: String) {
        let emptyCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = emptyCache
        logger.notice("Disabled shared URL cache for \(reason, privacy: .public)")
    }
}
