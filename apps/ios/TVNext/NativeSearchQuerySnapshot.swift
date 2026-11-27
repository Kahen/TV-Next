import Foundation

/// Separates an edited search draft from the keyword that produced the visible results.
enum NativeSearchQuerySnapshot {
    static func resolve(draft: String, committed: String?, reuseCommitted: Bool) -> String {
        if reuseCommitted, let committed { return committed }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
