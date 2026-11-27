import Foundation

/// Transport-independent, bounded representation of an SMB2/3 directory enumeration.
/// SMB client integration must supply decoded names and metadata from an authenticated share.
struct NativeSMBDirectoryEntry: Equatable, Identifiable {
    let name: String
    let isDirectory: Bool
    let size: Int64

    var id: String { name }

    init?(name: String, isDirectory: Bool, size: Int64) {
        guard Self.validName(name), size >= 0, (!isDirectory || size == 0) else { return nil }
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }

    static func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..",
              name.utf8.count <= 255, name.last != " ", name.last != "." else { return false }
        return !name.unicodeScalars.contains {
            $0.value < 32 || $0.value == 127 || $0.value == 47 ||
            $0.value == 92 || $0.value == 58 ||
            $0.properties.generalCategory == .format
        }
    }
}

enum NativeSMBDirectoryPage {
    static let maximumEntries = 512

    /// Returns nil on an invalid entry or a case-insensitive duplicate, rather than
    /// silently losing items in a remote directory listing.
    static func normalize(_ entries: [NativeSMBDirectoryEntry]) -> [NativeSMBDirectoryEntry]? {
        guard entries.count <= maximumEntries else { return nil }
        var seen = Set<String>()
        for entry in entries {
            guard seen.insert(entry.name.folding(options: [.caseInsensitive],
                                                locale: Locale(identifier: "en_US_POSIX"))).inserted else {
                return nil
            }
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
        }
    }
}
