import Foundation

/// Separates a search currently being edited from the query that produced the visible page.
enum NativeSearchQuerySnapshot {
    static func resolve(draft: String, committed: String?, page: Int, sameSite: Bool) -> String {
        if page > 1, sameSite, let committed {
            return committed
        }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
