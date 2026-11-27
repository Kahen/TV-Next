import Foundation

/// Strictly bounded explicit page selection for FongMi browsing.
enum NativeFongMiPageJump {
    static let maximumPage = 10_000

    static func parse(_ input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 5,
              value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let number = Int(value), (1...maximumPage).contains(number) else {
            return nil
        }
        return number
    }
}
