import Foundation

enum CacheJanitor {
    static func prepareForLaunch() {
        disableSharedURLCache()
    }

    static func cleanupTransientCaches(reason _: String) {
        disableSharedURLCache()
    }

    private static func disableSharedURLCache() {
        let emptyCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = emptyCache
    }
}
