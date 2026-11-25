//
//  Receipt.swift
//  Built into the app and its report extension.
//
//  The receipt look of the Time on apps card, drawn the same by the app
//  and the report extension, in light and dark mode alike, so the card
//  reads as one receipt to screenshot.
//

import SwiftUI

enum Receipt {
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    static let ink = Color(white: 0.12)
    static let faded = Color(white: 0.42)
    static let font = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let bold = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let small = Font.system(size: 12, weight: .regular, design: .monospaced)
}

/// A dashed line across the receipt.
struct ReceiptRule: View {
    var body: some View {
        DashedLine()
            .stroke(Receipt.faded, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
    }

    private struct DashedLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// A label and its value across the receipt.
struct ReceiptLine: View {
    let label: String
    let value: String
    var bold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .fixedSize()
        }
        .font(bold ? Receipt.bold : Receipt.font)
    }
}

/// The torn edge along the top of the receipt; turned over for the bottom.
struct ReceiptEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let count = max(1, Int(rect.width / 10))
        let step = rect.width / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for index in 0..<count {
            let x = rect.minX + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x + step / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x + step, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
