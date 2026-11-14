import Foundation

@main struct WebDAVCaptionNetworkSmoke {
    static func main() async throws {
        let connection = try NativeWebDAVConnection(address: "http://127.0.0.1:8767/captions", username: "", password: "")
        func item(_ name: String) -> NativeWebDAVItem {
            NativeWebDAVItem(url: connection.root.appendingPathComponent(name), name: name, isDirectory: false)
        }
        for name in ["Owned.srt", "Unicode.vtt", "Utf16.srt", "Styled.ass"] {
            let cues = try await NativeWebDAVCaptionReader.load(item(name), connection: connection)
            precondition(cues.first?.text == "Owned captions", "Incorrect subtitle decoding for \(name)")
        }
        let legacy = try await NativeWebDAVCaptionReader.load(item("Legacy.srt"), connection: connection, encoding: .gb18030)
        precondition(legacy.first?.text == "中文字幕")
        for name in ["Redirect.srt", "Redirect-local.srt", "Unauthorized.srt", "Partial.srt", "Large.srt", "Streamed.srt", "Invalid.srt"] {
            do {
                _ = try await NativeWebDAVCaptionReader.load(item(name), connection: connection)
                fatalError("Accepted rejected subtitle \(name)")
            } catch NativeWebDAVError.httpStatus(302) where name.hasPrefix("Redirect") {
            } catch NativeWebDAVError.unauthorized where name == "Unauthorized.srt" {
            } catch NativeWebDAVError.httpStatus(206) where name == "Partial.srt" {
            } catch NativeWebDAVError.responseTooLarge where name == "Large.srt" || name == "Streamed.srt" {
            } catch CaptionError.invalidTimeline where name == "Invalid.srt" {
            } catch { fatalError("Wrong rejection for \(name): \(error)") }
        }
        let cancelled = Task { try await NativeWebDAVCaptionReader.load(item("Slow.srt"), connection: connection) }
        try await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled caption load succeeded") }
        catch is CancellationError { }
        catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { }
        let again = try await NativeWebDAVCaptionReader.load(item("Owned.srt"), connection: connection)
        precondition(again.first?.text == "Owned captions")
        print("WebDAV subtitles: real GET, Unicode/GB18030, formats, status/redirect/size rejection and cancellation passed")
    }
}
