import SwiftUI
import AVFoundation
import UIKit

struct DanmakuOptions: Equatable {
    var enabled = true
    var opacity = 0.8
    var fontSize = 22.0
    var area = 0.5
    var duration = 8.0
    var offset = 0.0
    var blocked = ""
}
private struct PositionedDanmaku {
    let comment: DanmakuComment
    let lane: Int
    let width: Double
}
struct DanmakuOverlay: View {
    let player: AVPlayer
    let comments: [DanmakuComment]
    let options: DanmakuOptions
    @State private var positioned: [PositionedDanmaku] = []

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                Canvas { context, size in
                    let now = player.currentTime().seconds - options.offset
                    if options.enabled && now.isFinite {
                        context.opacity = options.opacity
                        var low = 0, high = positioned.count
                        while low < high {
                            let middle = (low + high) / 2
                            if positioned[middle].comment.time <= now { low = middle + 1 } else { high = middle }
                        }
                        var index = low - 1
                        while index >= 0 && positioned[index].comment.time > now - options.duration {
                            let item = positioned[index], c = item.comment
                            let progress = (now - c.time) / options.duration
                            let x = c.mode == 4 || c.mode == 5 ? (size.width - item.width) / 2 :
                                c.mode == 6 ? -item.width + progress * (size.width + item.width) : size.width - progress * (size.width + item.width)
                            let y = c.mode == 4 ? size.height - Double(item.lane + 1) * (options.fontSize + 8) : Double(item.lane) * (options.fontSize + 8)
                            let color = Color(red: Double((c.color >> 16) & 255) / 255, green: Double((c.color >> 8) & 255) / 255, blue: Double(c.color & 255) / 255)
                            let text = Text(c.text).font(.system(size: options.fontSize)).foregroundColor(color)
                            context.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
                            index -= 1
                        }
                    }
                }
            }
            .onAppear { layout(geometry.size) }
            .onChange(of: geometry.size) { _, size in layout(size) }
            .onChange(of: comments) { _, _ in layout(geometry.size) }
            .onChange(of: options) { _, _ in layout(geometry.size) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func layout(_ size: CGSize) {
        let count = max(1, Int(size.height * options.area / (options.fontSize + 8)))
        var scrolling: [PositionedDanmaku?] = Array(repeating: nil, count: count)
        var top = Array(repeating: -Double.infinity, count: count), bottom = top
        let words = options.blocked.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result: [PositionedDanmaku] = []
        for c in comments where !words.contains(where: { c.text.contains($0) }) {
            let width = (c.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: options.fontSize)]).width
            var lane: Int?
            if c.mode == 4 { lane = bottom.firstIndex { $0 <= c.time }; if let lane { bottom[lane] = c.time + options.duration } }
            else if c.mode == 5 { lane = top.firstIndex { $0 <= c.time }; if let lane { top[lane] = c.time + options.duration } }
            else {
                lane = scrolling.firstIndex { previous in
                    guard let p = previous else { return true }
                    let gap = max(p.width / ((size.width + p.width) / options.duration), options.duration - size.width / ((size.width + width) / options.duration))
                    return p.comment.time + options.duration <= c.time || p.comment.mode == c.mode && c.time - p.comment.time >= gap
                }
            }
            if let lane {
                let item = PositionedDanmaku(comment: c, lane: lane, width: width)
                result.append(item)
                if c.mode == 1 || c.mode == 6 { scrolling[lane] = item }
            }
        }
        positioned = result
    }
}
