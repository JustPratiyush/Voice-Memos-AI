import SwiftUI

/// Draws measured audio peaks. The detailed view keeps the playhead centered;
/// the overview maps the whole recording to the available width.
struct WaveformView: View {
    var samples: [Float]
    var duration: TimeInterval
    @Binding var position: TimeInterval
    var live = false
    var overview = false
    var selection: ClosedRange<Double>?
    var onSeek: (Double) -> Void = { _ in }
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvas in
                let secondsVisible = overview ? max(duration, 0.1) : max(4, canvas.width / 100)
                let scale = canvas.width / secondsVisible
                let origin = overview ? 0 : canvas.width / 2 - position * scale
                let centerY = (canvas.height - (overview ? 0 : 28)) / 2
                if !overview {
                    let left = max(0, origin)
                    let right = min(canvas.width, origin + duration * scale)
                    context.fill(Path(CGRect(x: left, y: 0, width: max(0, right - left), height: canvas.height - 27)),
                                 with: .color(.primary.opacity(0.025)))
                }
                if let selection {
                    let lo = origin + selection.lowerBound * scale
                    let hi = origin + selection.upperBound * scale
                    context.fill(Path(CGRect(x: max(0, lo), y: 0, width: max(0, min(hi, canvas.width) - max(0, lo)),
                                             height: canvas.height - (overview ? 0 : 28))), with: .color(.yellow.opacity(0.2)))
                }
                var bars = Path()
                let barSpacing: CGFloat = overview ? 3 : 4
                let count = max(1, Int(canvas.width / barSpacing))
                for i in 0...count {
                    let x = CGFloat(i) * barSpacing
                    let second = (x - origin) / scale
                    guard second >= 0, second <= duration, !samples.isEmpty else { continue }
                    let index = min(samples.count - 1, max(0, Int(second / max(duration, 0.001) * Double(samples.count))))
                    let amplitude = CGFloat(max(0.008, min(1, samples[index])))
                    let height = max(1, amplitude * (canvas.height - (overview ? 6 : 50)) * 0.85)
                    bars.move(to: CGPoint(x: x, y: centerY - height / 2))
                    bars.addLine(to: CGPoint(x: x, y: centerY + height / 2))
                }
                context.stroke(bars, with: .color(live ? MemoStyle.red : .primary.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
                if !overview {
                    let interval: Double = secondsVisible > 12 ? 5 : 1
                    let first = max(0, floor((position - secondsVisible / 2) / interval) * interval)
                    let last = min(max(duration, secondsVisible), position + secondsVisible / 2)
                    if first <= last {
                        for tick in stride(from: first, through: last, by: interval / 4) {
                            let x = origin + tick * scale
                            var line = Path()
                            let major = abs(tick / interval - (tick / interval).rounded()) < 0.01
                            line.move(to: CGPoint(x: x, y: canvas.height - 27))
                            line.addLine(to: CGPoint(x: x, y: canvas.height - (major ? 17 : 22)))
                            context.stroke(line, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                            if major {
                                context.draw(Text(timeLabel(tick)).font(.system(size: 11)).foregroundColor(.secondary),
                                             at: CGPoint(x: x + 10, y: canvas.height - 7))
                            }
                        }
                    }
                }
                let playhead = overview ? CGFloat(position / max(duration, 0.1)) * canvas.width : canvas.width / 2
                var cursor = Path()
                cursor.move(to: CGPoint(x: playhead, y: 0))
                cursor.addLine(to: CGPoint(x: playhead, y: canvas.height - (overview ? 0 : 27)))
                let color: Color = live ? MemoStyle.red : .accentColor
                context.stroke(cursor, with: .color(color), style: StrokeStyle(lineWidth: overview ? 3 : 1))
                if !overview {
                    for y in [CGFloat(0), canvas.height - 27] {
                        context.fill(Path(ellipseIn: CGRect(x: playhead - 3, y: y - 3, width: 6, height: 6)), with: .color(color))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard !live else { return }
                if dragStart == nil { dragStart = position }
                let secondsVisible = max(4, size.width / 100)
                let next = overview
                    ? event.location.x / max(1, size.width) * duration
                    : (dragStart ?? position) - event.translation.width / max(1, size.width) * secondsVisible
                position = min(duration, max(0, next))
                onSeek(position)
            }.onEnded { _ in dragStart = nil })
            .accessibilityElement()
            .accessibilityLabel(overview ? "Waveform Overview" : "Waveform Detail")
            .accessibilityValue(timeLabel(position))
            .accessibilityAdjustableAction { direction in
                position = min(duration, max(0, position + (direction == .increment ? 1 : -1)))
                onSeek(position)
            }
        }
        .background(MemoStyle.waveform)
    }
}

struct RecordButton: View {
    var action: () -> Void
    #if os(macOS)
    private let diameter: CGFloat = 44
    private let stroke: CGFloat = 2
    #else
    private let diameter: CGFloat = 60
    private let stroke: CGFloat = 4
    #endif
    var body: some View {
        Button(action: action) {
            Circle().fill(MemoStyle.red).frame(width: diameter, height: diameter)
                .padding(4).overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record")
        .help("Start a new recording")
    }
}
