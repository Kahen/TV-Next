import SwiftUI
import UniformTypeIdentifiers

/// Local metadata preview only; does not load external media providers.
struct ConfigPreviewSection: View {
    @State private var configText = ""
    @State private var preview: OfflineConfigPreview?
    @State private var errorMessage: String?
    @State private var showPicker = false

    var body: some View {
        GroupBox("FongMi JSON 配置（离线预览）") {
            VStack(alignment: .leading, spacing: 12) {
                inputControls
                resultDetails
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

    private var inputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴 JSON 或从 Files 选择文件，仅解析站点元数据。最大 1 MiB UTF-8。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showPicker = true
            } label: {
                Label("选择本地 JSON 文件", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            TextEditor(text: $configText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)).allowsHitTesting(false))
                .accessibilityLabel("JSON 配置内容")
                .accessibilityIdentifier("config-input")
                .onChange(of: configText) { _, _ in
                    preview = nil
                    errorMessage = nil
                }
            Button("清空输入") { configText = "" }
                .disabled(configText.isEmpty)
                .accessibilityIdentifier("clear-config-input")
            Button("检查 JSON 配置") {
                inspect()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("inspect-config")
        }
    }

    @ViewBuilder
    private var resultDetails: some View {
        if let errorMessage {
            Text(errorMessage)
                .accessibilityIdentifier("config-error")
                .foregroundStyle(.red)
                .font(.footnote)
        }
        if let preview {
            previewDetails(preview)
        }
    }

    private func previewDetails(_ preview: OfflineConfigPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("站点 " + String(preview.sites.count) + " · 直播源 " + String(preview.liveSourceCount))
                .font(.subheadline)
                .fontWeight(.semibold)
            if preview.spiderDeclared {
                Text("检测到 Spider 声明；不会加载或执行。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(preview.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if preview.sites.isEmpty {
                Text("配置中没有可展示的站点。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(preview.sites) { site in
                siteRow(site)
            }
        }
    }

    private func siteRow(_ site: OfflineConfigSite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(site.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(siteSummary(site))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !site.categories.isEmpty {
                Text("分类：" + site.categories.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func siteSummary(_ site: OfflineConfigSite) -> String {
        let kind = site.type.map { String($0) } ?? "unknown"
        let search = site.searchable ? "可搜索（声明）" : "禁止搜索（声明）"
        return site.key + " · type " + kind + " · " + search + (site.hidden ? " · 已隐藏" : "")
    }

    private func inspect() {
        do {
            preview = try OfflineConfigParser.parse(configText)
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
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
            guard data.count <= OfflineConfigParser.maxBytes else {
                throw OfflineConfigError.tooLarge
            }
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
