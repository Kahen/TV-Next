import AVKit
import SwiftUI

/// Standard AVKit controls expose supported device features, including user-initiated PiP.
/// SwiftUI captions/danmaku stay on the inline/fullscreen surface; they are not burned into PiP.
struct NativePlayerView: UIViewControllerRepresentable {
    @ObservedObject var library: MediaLibraryStore
    var onRestore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(library: library, onRestore: onRestore) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = library.player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== library.player { controller.player = library.player }
        context.coordinator.onRestore = onRestore
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        let library: MediaLibraryStore
        var onRestore: () -> Void
        init(library: MediaLibraryStore, onRestore: @escaping () -> Void) {
            self.library = library
            self.onRestore = onRestore
        }

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            // The background transition can precede didStart; protect an explicit PiP transition.
            library.setPictureInPictureActive(true)
        }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            library.setPictureInPictureActive(false, appIsBackground: UIApplication.shared.applicationState == .background)
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
            library.setPictureInPictureActive(false, appIsBackground: UIApplication.shared.applicationState == .background)
        }
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            onRestore()
            completionHandler(true)
        }
    }
}
