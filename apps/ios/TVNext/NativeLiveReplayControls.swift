import SwiftUI

@MainActor
final class NativeReplayRequestCoordinator {
    private var generation=UUID()
    func begin() -> UUID { generation=UUID();return generation }
    func isCurrent(_ id: UUID) -> Bool { generation==id }
    func invalidate() { generation=UUID() }
}

struct NativeLiveReplayControls: View {
    let channel: TVChannel
    let serverURL: String
    let session: NativeHomeSession?
    let onPlay: (TVChannel)->Void
    var programme: NativeEpgProgram? = nil
    var playbackGeneration=0
    var coordinator: NativeReplayRequestCoordinator? = nil
    @State private var selectedTime = Date().addingTimeInterval(-60)
    @State private var task: Task<Void,Never>?
    @State private var generation=UUID()
    @State private var busy=false
    @State private var error: String?

    var body: some View {
        TimelineView(.periodic(from:.now,by:programme == nil ? 1 : 60)) { context in
            let now=Int64(context.date.timeIntervalSince1970*1000)
            let range=channel.timeshift?.range(now:now)
            if range != nil || programme != nil && channel.catchup != nil || channel.replay != nil {
                VStack(alignment:.leading,spacing:8) {
                    if session == nil { Text("登录家庭服务器后可使用直播回放。").font(.caption) }
                    if let range,programme == nil {
                        DatePicker("回放时间",selection:$selectedTime,
                            in:Date(timeIntervalSince1970:Double(range.lowerBound)/1000)...context.date,
                            displayedComponents:[.date,.hourAndMinute])
                            .accessibilityIdentifier("live-replay-time")
                        Text("提供方允许范围："+Date(timeIntervalSince1970:Double(range.lowerBound)/1000).formatted()+" 至当前时间")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("播放所选时间") { replay(Int64(selectedTime.timeIntervalSince1970*1000)) }
                            .disabled(session == nil)
                    }
                    if let programme,channel.catchup != nil {
                        Button("回看 · "+programme.title) {
                            let parser=ISO8601DateFormatter()
                            guard let start=parser.date(from:programme.start),let stop=parser.date(from:programme.stop) else {
                                error="节目时间无效";return
                            }
                            replay(Int64(start.timeIntervalSince1970*1000),stop:min(Int64(stop.timeIntervalSince1970*1000),now))
                        }.disabled(session == nil)
                    }
                    if programme == nil { Button("回到直播") { replay(0) }.disabled(session == nil) }
                    if busy { HStack { ProgressView();Button("取消回放请求") { cancel() } } }
                    if let error { Text(error).foregroundStyle(.red).font(.caption).accessibilityIdentifier("live-replay-error") }
                }.buttonStyle(.bordered)
            }
        }
        .onChange(of:playbackGeneration) { _,_ in cancel() }
        .onChange(of:channel.id) { _,_ in cancel();error=nil }
        .onChange(of:session?.token) { _,_ in cancel();error=nil }
        .onChange(of:serverURL) { _,_ in cancel();error=nil }
        .onDisappear { cancel() }
    }

    private func cancel() { generation=UUID();task?.cancel();task=nil;busy=false }
    private func replay(_ time: Int64,stop: Int64? = nil) {
        guard let session,let server=URL(string:serverURL) else { error="请先登录家庭服务器。";return }
        if time != 0 && stop == nil {
            let now=Int64(Date().timeIntervalSince1970*1000)
            guard channel.timeshift?.range(now:now)?.contains(time) == true else { error="请选择提供方允许的回放时间。";return }
        }
        cancel();let id=UUID();generation=id;let owner=coordinator?.begin();busy=true;error=nil
        task=Task { @MainActor in
            defer { if generation==id { busy=false } }
            let api=TVNextAPI(server:server,token:session.token)
            do {
                let result: NativeReplaySession=try await api.request("subscriptions/replay",
                    body:NativeReplayRequest(channel:channel,time:time,stop:stop,timezone:TimeZone.current.identifier))
                let address=try MediaRelayAddress.resolve(result.path,server:server)
                guard !Task.isCancelled,generation==id,(owner == nil || coordinator?.isCurrent(owner!) == true) else {
                    let _: [String:Bool]? = try? await api.request("home/media/"+address.ticket+"/close",body:EmptyHomeRequest())
                    return
                }
                var replaying=channel;replaying.replay=result
                replaying.replaySelection=NativeReplaySelection(time:time,stop:stop,timezone:TimeZone.current.identifier)
                onPlay(replaying)
            } catch { if !Task.isCancelled,generation==id { self.error=error.localizedDescription } }
        }
    }
}
