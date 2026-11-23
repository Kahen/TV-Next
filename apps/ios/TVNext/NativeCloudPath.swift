import Foundation

/// AList/OpenList paths are opaque server paths, not local filesystem paths.
enum NativeCloudPath {
    static func parent(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > 1 else { return "/" }
        return "/" + parts.dropLast().joined(separator: "/")
    }

    static func child(named name: String, in directory: String) -> String? {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029
              }) else { return nil }
        let base = directory == "/" ? "" : directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.isEmpty ? "/" + name : "/" + base + "/" + name
    }
}
