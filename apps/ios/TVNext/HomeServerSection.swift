import SwiftUI

struct HomeServerSection: View {
    @Binding var serverURL: String
    @ObservedObject var library: MediaLibraryStore
    var onSessionChange: ((NativeHomeSession?,String)->Void)? = nil
    var remoteState="未连接"
    @State private var username=""
    @State private var password=""
    @State private var name="iPhone / iPad"
    @State private var claim=""
    @State private var session: NativeHomeSession?
    @State private var sessionServer=""
    @State private var devices: [NativeHomeDevice]=[]
    @State private var remote: NativeSyncedLibrary?
    @State private var diagnostics: NativeHomeDiagnostics?
    @State private var code=""
    @State private var online: [NativeRemoteDevice]=[]
    @State private var target=""
    @State private var seek=0.0
    @State private var media=""
    @State private var command=""
    @State private var busy=false
    @State private var error: String?
    @State private var notice: String?
    @State private var task: Task<Void,Never>?
    @State private var revision=UUID()
    var body: some View {
        GroupBox("家庭服务器 · 账号与同步") {
            VStack(alignment:.leading,spacing:12) {
                TextField("家庭服务器 API URL",text:$serverURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                if let session { authorized(session) } else { signIn }
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .onAppear { restoreSession() }
        .onChange(of:serverURL) { _,_ in task?.cancel();revision=UUID();session=nil;clearAccountState();password="";busy=false;restoreSession() }
        .onDisappear { task?.cancel() }
    }
    private var signIn: some View {
        VStack(alignment:.leading,spacing:10) {
            TextField("账号",text:$username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("密码（注册至少 12 位）",text:$password).textFieldStyle(.roundedBorder)
            TextField("设备名称",text:$name).textFieldStyle(.roundedBorder)
            HStack { Button("登录") { auth(false) };Button("注册账号") { auth(true) } }.buttonStyle(.bordered).disabled(busy)
            TextField("另一设备显示的配对码",text:$claim).textFieldStyle(.roundedBorder)
            Button("通过配对码登录",action:claimDevice).disabled(busy || claim.isEmpty)
        }
    }
    @ViewBuilder private func authorized(_ s: NativeHomeSession) -> some View {
        Text(s.user.username+" · "+s.device.name).font(.subheadline)
        Button("退出并撤销此设备") { logout() }
        HStack {
            Button("读取云端版本",action:fetchLibrary)
            Button("上传本地媒体库",action:uploadLibrary).disabled(remote==nil)
        }.buttonStyle(.bordered).disabled(busy)
        Button("用已读取版本替换本地") {
            do { if let remote { try library.restoreSnapshot(remote.library);notice="本地媒体库已恢复。" } }
            catch { self.error=error.localizedDescription }
        }.disabled(busy || remote==nil)
        Button("生成 5 分钟配对码",action:pairDevice).disabled(busy)
        if !code.isEmpty { Text(code).font(.system(.title3,design:.monospaced)).textSelection(.enabled) }
        Button("查看已授权设备",action:fetchDevices).disabled(busy)
        remoteControls
        Button("刷新服务器状态") {
            run(operation:{ api -> NativeHomeDiagnostics in try await api.get("home/diagnostics") }) { diagnostics=$0 }
        }.disabled(busy)
        if let diagnostics {
            Text("运行 \(diagnostics.uptimeSeconds) 秒 · 内存 \(diagnostics.memoryUsedBytes/1048576) / \(diagnostics.memoryMaxBytes/1048576) MiB")
                .font(.caption)
            Text("请求 \(diagnostics.httpRequests) · 4xx \(diagnostics.httpClientErrors) / 5xx \(diagnostics.httpServerErrors) · 本账号在线 \(diagnostics.onlineDevices)/\(diagnostics.devices) · 媒体库版本 \(diagnostics.libraryRevision)")
                .font(.caption)
        }
        ForEach(devices) { device in
            HStack {
                Text(device.name+(device.current ? "（当前设备）":""));Spacer()
                Button("撤销授权") { revoke(device) }.disabled(busy)
            }
        }
    }
    private var remoteControls: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("遥控接收端："+remoteState).font(.caption)
            Button("刷新遥控设备") {
                run(operation:{ api -> [NativeRemoteDevice] in try await api.get("home/remote/devices") }) { online=$0 }
            }.disabled(busy)
            Picker("遥控目标",selection:$target) {
                Text("选择设备").tag("")
                ForEach(online) { device in Text(device.name+(device.online ? " · 在线":" · 离线")).tag(device.id) }
            }
            HStack { Button("远程播放") { send("PLAY") };Button("远程暂停") { send("PAUSE") } }.disabled(busy || target.isEmpty)
            HStack { TextField("跳转秒数",value:$seek,format:.number).textFieldStyle(.roundedBorder);Button("远程跳转") { send("SEEK") }.disabled(busy || target.isEmpty) }
            TextField("远程媒体 URL",text:$media).keyboardType(.URL).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
            Button("远程加载媒体") { send("LOAD") }.disabled(busy || target.isEmpty || media.isEmpty)
            Button("查看遥控结果") {
                run(operation:{ api -> NativeRemoteStatus in try await api.get("home/remote/commands/"+command) }) { notice=$0.state+($0.message.map { " · "+$0 } ?? "") }
            }.disabled(busy || command.isEmpty)
        }
    }
    private func send(_ type: String) {
        let payload=NativeRemoteRequest(targetDeviceId:target,type:type,position:type=="SEEK" ? seek:nil,url:type=="LOAD" ? media:nil)
        run(operation:{ api -> NativeRemoteStatus in try await api.request("home/remote/commands",body:payload) }) { command=$0.id;notice="遥控指令已发出；可查看接收端结果。" }
    }
    private func auth(_ register: Bool) {
        let payload=NativeCredentials(username:username,password:password,deviceName:name)
        run(false,operation:{ api -> NativeHomeSession in try await api.request("home/auth/"+(register ? "register":"login"),body:payload) },receive:connected)
    }
    private func claimDevice() {
        let payload=NativePairRequest(deviceName:name,code:claim)
        run(false,operation:{ api -> NativeHomeSession in try await api.request("home/pairings/claim",body:payload) },receive:connected)
    }
    private func fetchLibrary() {
        run(operation:{ api -> NativeSyncedLibrary in try await api.get("home/library") }) { value in remote=value;notice="已读取云端；本地尚未替换。" }
    }
    private func uploadLibrary() {
        guard let remote else { return }
        let payload=NativeLibraryWrite(expectedRevision:remote.revision,library:library.syncedSnapshot())
        run(operation:{ api -> NativeSyncedLibrary in try await api.request("home/library",body:payload) }) { value in self.remote=value;notice="媒体库已上传。" }
    }
    private func pairDevice() {
        run(operation:{ api -> NativePairCode in try await api.request("home/pairings",body:EmptyHomeRequest()) }) { value in code=value.code }
    }
    private func fetchDevices() {
        run(operation:{ api -> [NativeHomeDevice] in try await api.get("home/devices") }) { value in devices=value }
    }
    private func revoke(_ device: NativeHomeDevice) {
        run(operation:{ api -> [String:Bool] in try await api.request("home/devices/"+device.id+"/revoke",body:EmptyHomeRequest()) }) { _ in
            if device.current { logout(revoke:false) } else { devices.removeAll { $0.id==device.id } }
        }
    }
    private func connected(_ result: NativeHomeSession) throws {
        session=result;sessionServer=serverURL;onSessionChange?(result,serverURL);password="";clearAccountState()
        try HomeKeychain.save(result,server:serverURL)
        notice="设备已登录；同步由你主动发起。"
    }
    private func restoreSession() { session=HomeKeychain.read(serverURL);sessionServer=serverURL;onSessionChange?(session,serverURL) }
    private func clearAccountState() { remote=nil;diagnostics=nil;devices=[];code="";claim="";online=[];target="";seek=0;media="";command="";notice=nil;error=nil }
    private func logout(revoke: Bool=true) {
        let previous=session
        let previousServer=sessionServer
        task?.cancel();revision=UUID();HomeKeychain.clear(previousServer);onSessionChange?(nil,previousServer);session=nil;clearAccountState();password="";busy=false
        if revoke,let previous,let url=URL(string:previousServer) {
            Task { let _: [String:Bool]? = try? await TVNextAPI(server:url,token:previous.token).request("home/devices/"+previous.device.id+"/revoke",body:EmptyHomeRequest()) }
        }
    }
    private func run<T>(_ authenticated: Bool=true,operation: @escaping (TVNextAPI) async throws -> T,receive: @escaping (T) throws -> Void) {
        task?.cancel();let id=UUID();revision=id;busy=true;error=nil;notice=nil
        let server=serverURL
        task=Task { @MainActor in
            do {
                guard revision==id,server==serverURL,!Task.isCancelled else { return }
                guard let url=URL(string:server) else { throw APIError.invalidServer }
                if authenticated && (session==nil || sessionServer != server) { throw NativeRequestError.message("请先登录当前服务器") }
                let api=TVNextAPI(server:url,token:authenticated ? session?.token:nil)
                let value=try await operation(api)
                guard revision==id,server==serverURL,!Task.isCancelled else { return }
                try receive(value)
            } catch { if revision==id && !Task.isCancelled { self.error=error.localizedDescription } }
            if revision==id { busy=false }
        }
    }
}
