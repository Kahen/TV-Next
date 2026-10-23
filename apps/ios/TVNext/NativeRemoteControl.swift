import Foundation
import Combine

@MainActor final class NativeRemoteControl: ObservableObject {
    @Published private(set) var state="未连接"
    var receive: ((NativeRemotePacket) async throws -> Void)?
    private var task: Task<Void,Never>?
    private var heartbeat: Task<Void,Never>?
    private var socket: URLSessionWebSocketTask?
    private var key=""
    deinit { task?.cancel();heartbeat?.cancel();socket?.cancel(with:.normalClosure,reason:nil) }
    func configure(_ session: NativeHomeSession?,server: String) {
        let next=server+"|"+(session?.token ?? "")
        if key==next { return };key=next
        task?.cancel();heartbeat?.cancel();socket?.cancel(with:.normalClosure,reason:nil);state="未连接"
        guard let session,let base=URL(string:server) else { return }
        task=Task { @MainActor in
            var attempt=0
            while !Task.isCancelled {
                do {
                    if session.device.expiresAt<=Int64(Date().timeIntervalSince1970*1000) { state="登录已过期";return }
                    let ticket: NativeRemoteTicket=try await TVNextAPI(server:base,token:session.token).request("home/remote/ticket",body:EmptyHomeRequest())
                    guard !Task.isCancelled,key==next else { return }
                    var parts=URLComponents(url:base,resolvingAgainstBaseURL:false)!
                    parts.scheme=parts.scheme=="https" ? "wss":"ws";parts.path=parts.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))+"/api/v1/home/remote/socket"
                    if !parts.path.hasPrefix("/") { parts.path="/"+parts.path }
                    parts.queryItems=[URLQueryItem(name:"ticket",value:ticket.ticket)];parts.fragment=nil
                    guard let address=parts.url else { throw APIError.invalidServer }
                    let peer=URLSession.shared.webSocketTask(with:address);socket=peer;peer.resume();state="正在连接"
                    try await peer.send(.string("{\"type\":\"PING\"}"))
                    guard !Task.isCancelled,key==next else { peer.cancel(with:.normalClosure,reason:nil);return }
                    state="在线";attempt=0
                    heartbeat=Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds:25_000_000_000);if !Task.isCancelled { try? await peer.send(.string("{\"type\":\"PING\"}")) } } }
                    while !Task.isCancelled {
                        let message=try await peer.receive()
                        guard !Task.isCancelled,key==next else { return }
                        let data: Data
                        switch message { case .string(let text): data=Data(text.utf8);case .data(let bytes):data=bytes;@unknown default:continue }
                        guard data.count<=16384,let packet=try? JSONDecoder().decode(NativeRemotePacket.self,from:data) else { continue }
                        var success=true;var detail=""
                        do { guard let receive else { throw NativeRequestError.message("播放器尚未就绪") };try await receive(packet) }
                        catch { success=false;detail=error.localizedDescription }
                        guard !Task.isCancelled,key==next else { return }
                        let ack=try JSONSerialization.data(withJSONObject:["type":"ACK","id":packet.id,"success":success,"message":String(detail.prefix(200))])
                        try await peer.send(.string(String(decoding:ack,as:UTF8.self)))
                    }
                } catch {
                    if Task.isCancelled || key != next { return }
                    heartbeat?.cancel();socket?.cancel(with:.goingAway,reason:nil)
                    state="正在重连";attempt=min(attempt+1,5)
                    try? await Task.sleep(nanoseconds:UInt64(min(30,1<<attempt))*1_000_000_000)
                }
            }
        }
    }
}
