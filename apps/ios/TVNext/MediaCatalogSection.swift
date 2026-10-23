import SwiftUI
import UniformTypeIdentifiers

/// Native, fully offline view of user-supplied FongMi Result JSON.
struct MediaCatalogSection: View {
    let onPlay: (TVChannel) -> Void

    @State private var text = ""
    @State private var catalog: OfflineMediaCatalog?
    @State private var selectedCategory: String?
    @State private var query = ""
    @State private var selectedVideo: OfflineMediaVideo?
    @State private var selectedLine = 0
    @State private var page = 1
    @State private var choosingFile = false
    @State private var errorMessage: String?

    private let pageSize = 40

    private var filteredVideos: [OfflineMediaVideo] {
        guard let catalog else { return [] }
        let items = selectedCategory.map { catalog.category($0) } ?? catalog.videos
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    private var visibleVideos: [OfflineMediaVideo] {
        Array(filteredVideos.dropFirst((page - 1) * pageSize).prefix(pageSize))
    }

    var body: some View {
        GroupBox("影视目录 · FongMi Result") {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅解析你导入的 class/list JSON。不执行 Spider，不连接影视站点，也不下载封面。每份数据最多 1 MiB。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    choosingFile = true
                } label: {
                    Label("从“文件”导入 Result JSON", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 115)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                    .accessibilityLabel("FongMi Result JSON")
                    .onChange(of: text) { _, _ in
                        catalog = nil
                        selectedVideo = nil
                    }

                Button("解析影视目录") {
                    parse()
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if let catalog {
                    catalogView(catalog)
                }
            }
            .padding(.top, 8)
        }
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: [UTType(filenameExtension: "json") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            importJSON(result)
        }
    }

    @ViewBuilder
    private func catalogView(_ catalog: OfflineMediaCatalog) -> some View {
        Text("本机目录：\(catalog.videos.count) 部影视 · \(catalog.categories.count) 个分类")
            .font(.subheadline)
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                Button("全部") {
                    selectedCategory = nil
                    selectedVideo = nil
                    page = 1
                }
                .buttonStyle(.bordered)
                .tint(selectedCategory == nil ? .blue : .gray)

                ForEach(catalog.categories) { category in
                    Button(category.name) {
                        selectedCategory = category.id
                        selectedVideo = nil
                        page = 1
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedCategory == category.id ? .blue : .gray)
                }
            }
        }

        TextField("搜索已导入的影视名称", text: $query)
            .textFieldStyle(.roundedBorder)
            .onChange(of: query) { _, _ in
                page = 1
                selectedVideo = nil
            }

        Text("找到 \(filteredVideos.count) 项 · 第 \(page) 页")
            .font(.caption)
            .foregroundStyle(.secondary)

        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(visibleVideos) { video in
                Button {
                    selectedVideo = video
                    selectedLine = 0
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.name).font(.subheadline).fontWeight(.semibold)
                        Text([video.categoryName ?? video.categoryId, video.year, video.remarks]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        HStack {
            Button("上一页") { page -= 1 }
                .disabled(page <= 1)
            Spacer()
            Button("下一页") { page += 1 }
                .disabled(page * pageSize >= filteredVideos.count)
        }
        .buttonStyle(.bordered)

        if let selectedVideo {
            detailView(selectedVideo)
        }
    }

    @ViewBuilder
    private func detailView(_ video: OfflineMediaVideo) -> some View {
        Divider()
        Text(video.name).font(.headline)
        if let description = video.description {
            Text(description).font(.subheadline)
        }
        if let director = video.director {
            Text("导演：" + director).font(.caption)
        }
        if let actors = video.actors {
            Text("演员：" + actors).font(.caption)
        }
        if video.lines.isEmpty {
            Text("没有直接可播放的线路。复杂来源需要后续 Spider 适配。")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(video.lines.indices, id: \.self) { index in
                        Button(video.lines[index].name) {
                            selectedLine = index
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedLine == index ? .blue : .gray)
                    }
                }
            }
            if video.lines.indices.contains(selectedLine) {
                let current = video.lines[selectedLine]
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(current.episodes.indices, id: \.self) { index in
                        let episode = current.episodes[index]
                        Button {
                            guard let url = episode.directURL, MediaAddress.valid(url) else { return }
                            onPlay(TVChannel(
                                name: video.name + " · " + episode.name,
                                url: url,
                                group: current.name,
                                logo: nil,
                                tvgId: nil
                            ))
                        } label: {
                            Label(
                                episode.name + (episode.directURL == nil ? " · 需适配" : ""),
                                systemImage: episode.directURL == nil ? "lock" : "play.circle"
                            )
                        }
                        .disabled(episode.directURL == nil)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func parse() {
        do {
            catalog = try OfflineMediaParser.parse(text)
            selectedCategory = nil
            selectedVideo = nil
            query = ""
            page = 1
            errorMessage = nil
        } catch {
            catalog = nil
            selectedVideo = nil
            errorMessage = error.localizedDescription
        }
    }

    private func importJSON(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.pathExtension.lowercased() == "json" else {
                throw OfflineMediaError.invalidJSON
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber, size.int64Value > OfflineMediaParser.maxBytes {
                throw OfflineMediaError.tooLarge
            }
            let data = try Data(contentsOf: url)
            guard data.count <= OfflineMediaParser.maxBytes else { throw OfflineMediaError.tooLarge }
            guard let source = String(data: data, encoding: .utf8) else {
                throw OfflineMediaError.invalidJSON
            }
            text = source
            catalog = nil
            selectedVideo = nil
            errorMessage = nil
        } catch {
            catalog = nil
            selectedVideo = nil
            errorMessage = error.localizedDescription
        }
    }
}
