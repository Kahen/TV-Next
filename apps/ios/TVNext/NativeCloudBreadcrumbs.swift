import Foundation

/// Builds navigable ancestors from a server-returned cloud directory path.
/// Invalid paths deliberately expose only root, never an untrusted navigation target.
enum NativeCloudBreadcrumbs {
    struct Crumb: Identifiable, Equatable {
        let title: String
        let path: String
        var id: String { path }
    }

    static func make(_ path: String) -> [Crumb] {
        let root = Crumb(title: "根目录", path: "/")
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains("\\"), !path.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
              }) else { return [root] }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) || path == "/" else {
            return [root]
        }
        var result = [root]
        var prefix = ""
        for component in components where !component.isEmpty {
            prefix += "/" + component
            result.append(Crumb(title: String(component), path: prefix))
        }
        return result
    }
}
