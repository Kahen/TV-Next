import Foundation

/// Only navigate within the server-advertised bounded page sequence.
enum NativeCloudPageNavigation {
    static func previous(_ page: Int) -> Int? {
        guard page > 1 else { return nil }
        return page - 1
    }

    static func next(_ page: Int, hasMore: Bool) -> Int? {
        guard hasMore, page >= 1, page < Int.max else { return nil }
        return page + 1
    }
}
