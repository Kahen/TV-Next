import Foundation
struct NativeRecent: Codable { let channel: TVChannel; let openedAt: Double }
struct NativeLibrarySnapshot: Codable {
    let version: Int
    let channels: [TVChannel]
    let favorites: [String]
    let recent: [NativeRecent]
    let positions: [String:Double]
}
struct NativeSyncedLibrary: Codable { let revision: Int64; let updatedAt: Int64; let library: NativeLibrarySnapshot }
struct NativeHomeDevice: Codable, Identifiable { let id: String; let name: String; let createdAt: Int64; let expiresAt: Int64; let current: Bool }
struct NativeHomeUser: Codable { let id: String; let username: String }
struct NativeHomeSession: Codable { let token: String; let user: NativeHomeUser; let device: NativeHomeDevice }
struct NativeCredentials: Encodable { let username: String; let password: String; let deviceName: String }
struct NativePairRequest: Encodable { let deviceName: String; let code: String }
struct NativePairCode: Decodable { let code: String; let expiresAt: Int64 }
struct NativeLibraryWrite: Encodable { let expectedRevision: Int64; let library: NativeLibrarySnapshot }
struct EmptyHomeRequest: Encodable {}
struct NativeRemoteTicket: Decodable { let ticket: String; let expiresAt: Int64 }
struct NativeRemotePacket: Decodable { let id: String; let type: String; let position: Double?; let url: String? }
struct NativeRemoteDevice: Decodable, Identifiable { let id: String; let name: String; let current: Bool; let online: Bool }
struct NativeRemoteStatus: Decodable { let id: String; let state: String; let message: String? }
struct NativeRemoteRequest: Encodable { let targetDeviceId: String; let type: String; var position: Double? = nil; var url: String? = nil }

struct NativeHomeDiagnostics: Decodable {
    let uptimeSeconds: Int64; let memoryUsedBytes: Int64; let memoryMaxBytes: Int64
    let httpRequests: Int64; let httpClientErrors: Int64; let httpServerErrors: Int64
    let devices: Int; let onlineDevices: Int; let libraryRevision: Int64
}
