import Foundation

/// Slash-delimited AList/OpenList paths sent in JSON.
enum NativeCloudPath {
    static func normalizedDirectory(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/")
        guard parts.allSatisfy({ validComponent(String($0)) }) else { return nil }
        return "/" + parts.joined(separator: "/")
    }

    static func parent(of path: String) -> String {
        guard let path = normalizedDirectory(path) else { return "/" }
        let parts = path.split(separator: "/")
        return "/" + parts.dropLast().joined(separator: "/")
    }

    static func child(named name: String, in directory: String) -> String? {
        guard validComponent(name), let base = normalizedDirectory(directory) else { return nil }
        return (base == "/" ? "" : base) + "/" + name
    }

    private static func validComponent(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else { return false }
        return !name.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) ||
                $0.properties.generalCategory == .format ||
                $0.properties.generalCategory == .lineSeparator ||
                $0.properties.generalCategory == .paragraphSeparator
        }
    }
}
