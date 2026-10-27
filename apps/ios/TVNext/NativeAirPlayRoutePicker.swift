import AVKit
import SwiftUI

/// System AirPlay route chooser. AVPlayer remains the single playback engine;
/// this view does not scan local networks or implement DLNA protocols.
struct NativeAirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.prioritizesVideoDevices = true
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) { }
}
