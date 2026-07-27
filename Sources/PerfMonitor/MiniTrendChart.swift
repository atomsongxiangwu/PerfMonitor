import SwiftUI

struct MiniTrendChart: View {
    let values: [Double]
    let strokeColor: Color
    let maxY: Double?

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(size: geometry.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalizedPoints(size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let targetMax = max(maxY ?? values.max() ?? 1, 1)

        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let clamped = min(max(value, 0), targetMax)
            let ratio = clamped / targetMax
            let y = size.height - CGFloat(ratio) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
