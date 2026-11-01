import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// User-initiated, bounded SSDP M-SEARCH transport. No UI is exposed until the
/// Apple multicast entitlement and physical local-network permission are verified.
/// All discovered LOCATION values are revalidated by NativeSSDPResponse.parse;
/// discovery alone never authorizes SOAP control or media playback.
actor NativeSSDPDiscovery {
    enum DiscoveryError: LocalizedError, Equatable {
        case busy
        case rateLimited
        case networkUnavailable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .busy: return "正在搜索局域网设备，请等待当前搜索结束。"
            case .rateLimited: return "搜索过于频繁，请稍后重试。"
            case .networkUnavailable: return "无法发送局域网组播搜索；请检查本地网络权限与 Apple 组播授权。"
            case .cancelled: return "已取消局域网设备搜索。"
            }
        }
    }

    static let shared = NativeSSDPDiscovery()
    static let multicastAddress = "239.255.255.250"
    static let multicastPort: UInt16 = 1900
    static let maxDurationSeconds: TimeInterval = 3
    static let cooldownSeconds: TimeInterval = 10
    static let maxPackets = 64
    static let maxCandidates = 32

    private var scanning = false
    private var lastStartedAt: TimeInterval = -.greatestFiniteMagnitude

    /// Only these two fixed targets are emitted, with a single request per target.
    static func request(for target: String) -> Data? {
        guard target == NativeSSDPResponse.mediaRenderer || target == NativeSSDPResponse.avTransport else {
            return nil
        }
        return Data(("M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: \(target)\r\n\r\n").utf8)
    }

    static func deduplicated(_ candidates: [NativeSSDPResponse.Candidate]) -> [NativeSSDPResponse.Candidate] {
        var seen = Set<String>()
        var result: [NativeSSDPResponse.Candidate] = []
        for candidate in candidates {
            guard seen.insert(candidate.location.absoluteString).inserted else { continue }
            result.append(candidate)
            if result.count == maxCandidates { break }
        }
        return result
    }

    /// Not called by the shipping UI while the multicast entitlement is absent.
    /// No background scan, persisted address, or automatic renderer control.
    func discover() async throws -> [NativeSSDPResponse.Candidate] {
        guard !scanning else { throw DiscoveryError.busy }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastStartedAt >= Self.cooldownSeconds else {
            throw DiscoveryError.rateLimited
        }
        scanning = true
        lastStartedAt = now
        defer { scanning = false }
        let worker = Task.detached(priority: .userInitiated) {
            try Self.scan(destination: Self.multicastAddress, port: Self.multicastPort,
                          duration: Self.maxDurationSeconds)
        }
        do {
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        } catch is CancellationError {
            throw DiscoveryError.cancelled
        }
    }

    #if DEBUG
    /// Owned UDP fixture only. Release builds have no alternate destination.
    static func scanLoopbackFixture(port: UInt16, duration: TimeInterval = 0.6) throws -> [NativeSSDPResponse.Candidate] {
        try scan(destination: "127.0.0.1", port: port, duration: duration)
    }
    #endif

    private static func scan(destination: String, port: UInt16,
                             duration: TimeInterval) throws -> [NativeSSDPResponse.Candidate] {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), Int32(IPPROTO_UDP))
        #else
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #endif
        guard fd >= 0 else { throw DiscoveryError.networkUnavailable }
        defer { _ = close(fd) }

        var ttl: UInt8 = 1
        guard setsockopt(fd, Int32(IPPROTO_IP), Int32(IP_MULTICAST_TTL), &ttl,
                         socklen_t(MemoryLayout<UInt8>.size)) == 0 else {
            throw DiscoveryError.networkUnavailable
        }
        var local = sockaddr_in()
        #if canImport(Darwin)
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr = in_addr(s_addr: in_addr_t(0))
        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw DiscoveryError.networkUnavailable }

        var remote = sockaddr_in()
        #if canImport(Darwin)
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = port.bigEndian
        guard destination.withCString({ inet_pton(AF_INET, $0, &remote.sin_addr) }) == 1 else {
            throw DiscoveryError.networkUnavailable
        }
        for target in [NativeSSDPResponse.mediaRenderer, NativeSSDPResponse.avTransport] {
            try Task<Never, Never>.checkCancellation()
            guard let packet = request(for: target) else { continue }
            let written = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &remote) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard written == packet.count else { throw DiscoveryError.networkUnavailable }
        }

        let deadline = ProcessInfo.processInfo.systemUptime + min(max(duration, 0.1), maxDurationSeconds)
        var candidates: [NativeSSDPResponse.Candidate] = []
        var seen = Set<String>()
        var received = 0
        while ProcessInfo.processInfo.systemUptime < deadline && received < maxPackets && candidates.count < maxCandidates {
            try Task<Never, Never>.checkCancellation()
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int((deadline - ProcessInfo.processInfo.systemUptime) * 1000)
            let ready = poll(&pfd, 1, Int32(max(1, min(100, remaining))))
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                throw DiscoveryError.networkUnavailable
            }
            guard (pfd.revents & Int16(POLLIN)) != 0 else {
                if (pfd.revents & Int16(POLLERR | POLLNVAL)) != 0 {
                    throw DiscoveryError.networkUnavailable
                }
                continue
            }
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            var buffer = [UInt8](repeating: 0, count: NativeSSDPResponse.maxDatagramBytes + 1)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &sender) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &senderLength)
                    }
                }
            }
            received += 1
            guard count > 0, count <= NativeSSDPResponse.maxDatagramBytes,
                  sender.sin_family == sa_family_t(AF_INET) else { continue }
            var address = sender.sin_addr
            var addressBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &addressBuffer, socklen_t(addressBuffer.count)) != nil else {
                continue
            }
            let senderIPv4 = String(cString: addressBuffer)
            guard let candidate = try? NativeSSDPResponse.parse(Data(buffer.prefix(count)),
                                                                senderIPv4: senderIPv4),
                  seen.insert(candidate.location.absoluteString).inserted else { continue }
            candidates.append(candidate)
        }
        try Task<Never, Never>.checkCancellation()
        return candidates
    }
}
