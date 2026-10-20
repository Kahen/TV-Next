import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Export existing authorized streams; includes URLs verbatim (including query tokens).
enum M3UEncoder {
    static func serialize(_ channels: [TVChannel]) -> String {
        func cleaned(_ value: String) -> String {
            String(value.replacingOccurrences(of: #"[\r\n"]"#, with: " ", options: .regularExpression).prefix(200))
        }
        var text = "#EXTM3U\n"
        for channel in channels where MediaAddress.valid(channel.url) {
            let group = cleaned(channel.group)
            let title = cleaned(channel.name)
            let id = channel.tvgId.map { #" tvg-id=""# + cleaned($0) + #"""# } ?? ""
            text += #"#EXTINF:-1 group-title=""# + group + #"""# + id + "," + title + "\n"
            text += channel.url + "\n"
        }
        return text
    }
}

extension UTType {
    static var m3uPlaylist: UTType { UTType(filenameExtension: "m3u") ?? .plainText }
}

struct M3UExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.m3uPlaylist] }
    var content: String

    init(channels: [TVChannel]) {
        content = M3UEncoder.serialize(channels)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
