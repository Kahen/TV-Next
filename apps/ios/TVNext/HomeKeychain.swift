import Foundation
import Security

enum HomeKeychain {
    private static func query(_ server: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"dev.kahen.tvnext.home",kSecAttrAccount as String:server]
    }
    static func read(_ server: String) -> NativeHomeSession? {
        var item=query(server);item[kSecReturnData as String]=true;item[kSecMatchLimit as String]=kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary,&result)==errSecSuccess,let data=result as? Data,
              let session=try? JSONDecoder().decode(NativeHomeSession.self,from:data),session.device.expiresAt>Int64(Date().timeIntervalSince1970*1000) else { return nil }
        return session
    }
    static func save(_ session: NativeHomeSession,server: String) throws {
        let data=try JSONEncoder().encode(session)
        var item=query(server);SecItemDelete(item as CFDictionary)
        item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else { throw NativeRequestError.message("设备已登录，但钥匙串保存失败") }
    }
    static func clear(_ server: String) { SecItemDelete(query(server) as CFDictionary) }
}
