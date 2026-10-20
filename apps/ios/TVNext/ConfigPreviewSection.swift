import SwiftUI
import UniformTypeIdentifiers

/// iPhone/iPad metadata inspection. No network or plugin execution.
struct ConfigPreviewSection: View {
    @State private var configText = ""
    @State private var preview: OfflineConfigPreview?
    @State private var errorMessage: String?
    @State private var showPicker = false

    var body: some View {
        GroupBox("FongMi JSON 配置（离线预览）") {
            VStack(alignment: .leading, spacing: 12) {
                Text("粘贴 JSON 或从 Files 选择文件，只解析站点元数据，不下载配置或连接站点。最大 1 MiB UTF-8。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showPicker = true
                } label: {
                    Label("选择本地 JSON 文件", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)

                TextEditor(text: $configText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                    .accessibilityLabel("JSON 配置内容")
                    .onChange(of: configText) { _, _ in
                        preview = nil
                        errorMessage = nil
                    }

                Button("检查 JSON 配置") {
                    do {
                        preview = try OfflineConfigParser.parse(configText)
                        errorMessage = nil
                    } catch {
                        preview = nil
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let preview {
                    Text("站点 " + String(preview.sites.count) + " · 直播源 " + String(preview.liveSourceCount))
                        .font(.subheadline).fontWeight(.semibold)
                    if preview.spiderDeclared {
                        Text("检测到 Spider 声明；不会加载或执行。")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    ForEach(preview.warnings, id: \.self) { warning in
                        Text(warning).font(.footnote).foregroundStyle(.orange)
                    }
                    if preview.sites.isEmpty {
                        Text("配置中没有可展示的站点。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(preview.sites) { site in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name).font(.subheadline).fontWeight(.semibold)
                            Text(site.key + " · type " + (site.type.map(String.init) ?? "unknown")
                                 + (site.searchable ? " · 可搜索（声明）" : " · 禁止搜索（声明）")
                                 + (site.hidden ? " · 已隐藏" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if !site.categories.isEmpty {
                                Text("分类：" + site.categories.joined(separator: " / "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
            }
            .padding(.top, 8)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importConfigFile(result)
        }
    }

    private func importConfigFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.int64Value <= Int64(OfflineConfigParser.maxBytes) else {
                throw OfflineConfigError.tooLarge
            }
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                throw OfflineConfigError.invalidJSON
            }
            configText = content
            preview = nil
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }
}
