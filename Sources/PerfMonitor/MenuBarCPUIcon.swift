import SwiftUI

struct MenuBarCPUIcon: View {
    let cpuPercent: Double

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 0.5
            let center = CGPoint(x: size.width / 2, y: size.height - inset)
            let radius = min(size.width / 2 - inset, size.height - inset * 2)

            // Gauge track (background arc) — upper semicircle
            var track = Path()
            track.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: true
            )
            context.stroke(
                track,
                with: .color(Color.primary.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )

            // Active progress arc
            let progress = min(max(cpuPercent / 100.0, 0), 1)
            if progress > 0.01 {
                var active = Path()
                active.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 - 180 * progress),
                    clockwise: true
                )
                context.stroke(
                    active,
                    with: .color(gaugeColor),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }

            // Needle
            let angle = Angle.degrees(180 - 180 * progress)
            let needleLength = radius - 1
            let tip = CGPoint(
                x: center.x + CGFloat(Foundation.cos(angle.radians)) * needleLength,
                y: center.y - CGFloat(Foundation.sin(angle.radians)) * needleLength
            )
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            context.stroke(
                needle,
                with: .color(gaugeColor),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )

            // Hub
            let hub = Path(ellipseIn: CGRect(
                x: center.x - 1.2,
                y: center.y - 1.2,
                width: 2.4,
                height: 2.4
            ))
            context.fill(hub, with: .color(gaugeColor))
        }
        .frame(width: 16, height: 10)
        .accessibilityHidden(true)
    }

    private var gaugeColor: Color {
        if cpuPercent >= 85 { return .red }
        if cpuPercent >= 60 { return .orange }
        return Color(red: 0.20, green: 0.66, blue: 0.45) // calm green
    }
}
