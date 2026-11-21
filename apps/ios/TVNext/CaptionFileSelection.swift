import Foundation

/// Ranks the caller's eligible subtitle files the way FongMi LocalSubtitleScanner does.
enum CaptionFileSelection {
    static func candidates<File>(for mediaName: String, in files: [File],
                                 filename: (File) -> String) -> [File] {
        func stem(_ name: String) -> String {
            guard let dot = name.lastIndex(of: ".") else { return name.lowercased() }
            return name[..<dot].lowercased()
        }
        let media = stem(mediaName)
        let ranked = files.map { file in
            let name = filename(file)
            let subtitle = stem(name)
            let exact = subtitle == media
            let matches = exact || subtitle.hasPrefix(media + ".")
            return (file: file, name: name, exact: exact, matches: matches)
        }
        let matches = ranked.filter { $0.matches }
        return (matches.isEmpty ? ranked : matches).sorted { lhs, rhs in
            if lhs.exact != rhs.exact { return lhs.exact }
            let order = lhs.name.caseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.name < rhs.name : order == .orderedAscending
        }.map { $0.file }
    }
}

struct LocalPlaybackFiles {
    let media: URL
    let captions: [URL]

    init(_ urls: [URL]) throws {
        let mediaFiles = urls.filter(LocalMediaStager.supports)
        guard let first = mediaFiles.first else { throw LocalMediaError.unsupportedFormat }
        guard mediaFiles.count == 1 else { throw SelectionError.multipleMedia }
        let subtitles = urls.filter(LocalCaptionReader.supports)
        guard urls.count == 1 + subtitles.count else { throw SelectionError.unsupportedSidecar }
        media = first
        captions = CaptionFileSelection.candidates(for: first.lastPathComponent, in: subtitles,
                                                   filename: \.lastPathComponent)
    }

    private enum SelectionError: LocalizedError {
        case multipleMedia, unsupportedSidecar
        var errorDescription: String? {
            switch self {
            case .multipleMedia: return "一次只能打开一个媒体文件，可同时选择多份字幕。"
            case .unsupportedSidecar: return "随片文件仅支持 SRT、VTT、ASS 和 SSA 字幕。"
            }
        }
    }
}
