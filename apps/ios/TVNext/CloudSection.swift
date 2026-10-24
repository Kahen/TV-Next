import SwiftUI

struct CloudSection: View {
    let serverURL: String
    let onPlay: (TVChannel) -> Void
    @State private var server = ""
    @State private var token = ""
    @State private var password = ""
    @State private var page: NativeCloudPage?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void,Never>?
    @State private var revision = UUID()
    var body: some View {
        GroupBox("网盘 · AList / OpenList") {
            VStack(alignment: .leading, spacing: 12) {
                Text("浏览你已挂载的网盘；令牌仅保留在当前页面内存。原版网盘 Spider 的 HTTP 服务可从订阅入口使用。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("网盘服务 URL",text:$server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                SecureField("访问令牌（可选）",text:$token).textFieldStyle(.roundedBorder)
                SecureField("目录密码（可选）",text:$password).textFieldStyle(.roundedBorder)
                HStack {
                    Button("打开网盘") { open("/") }.disabled(busy || server.isEmpty)
                    Button("断开并清除凭据") { task?.cancel(); revision = UUID(); token = ""; password = ""; page = nil; busy = false }
                }.buttonStyle(.bordered)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let page { listing(page) }
            }
        }.onDisappear { task?.cancel(); token = ""; password = "" }
    }
    @ViewBuilder private func listing(_ p: NativeCloudPage) -> some View {
        Text(p.path).font(.caption)
        Button("上级目录") { open((p.path as NSString).deletingLastPathComponent) }.disabled(busy || p.path == "/")
        ForEach(p.entries) { item in
            Button((item.directory ? "📁 " : "▶ ") + item.name) {
                open((p.path == "/" ? "" : p.path) + "/" + item.name,play:!item.directory)
            }.disabled(busy)
        }
        HStack {
            Button("上一页") { open(p.path,number:p.page-1) }.disabled(busy || p.page <= 1)
            Spacer()
            Button("下一页") { open(p.path,number:p.page+1) }.disabled(busy || !p.hasMore)
        }
    }
    private func open(_ path: String, number: Int = 1, play: Bool = false) {
        task?.cancel(); let id = UUID(); revision = id; busy = true; error = nil
        let payload = NativeCloudRequest(server:server,token:token,path:path.isEmpty ? "/" : path,password:password,page:number)
        task = Task { @MainActor in
            do {
                guard let url = URL(string:serverURL) else { throw APIError.invalidServer }
                let api = TVNextAPI(server:url)
                if play {
                    let result: NativeCloudPlayback = try await api.request("cloud/play",body:payload)
                    guard revision == id, !Task.isCancelled else { return }
                    onPlay(TVChannel(name:result.name,url:result.url,group:"网盘",logo:nil,tvgId:nil,headers:result.headers))
                } else {
                    let result: NativeCloudPage = try await api.request("cloud/list",body:payload)
                    guard revision == id, !Task.isCancelled else { return }
                    page = result
                }
            } catch { if revision == id && !Task.isCancelled { self.error = error.localizedDescription } }
            if revision == id { busy = false }
        }
    }
}
