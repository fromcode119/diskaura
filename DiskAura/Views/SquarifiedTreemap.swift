import Foundation
import CoreGraphics

/// Classic squarified treemap layout (Bruls, Huizing, van Wijk) — produces
/// near-square rectangles instead of thin slivers, which is what makes a
/// treemap actually readable at a glance (GrandPerspective/DaisyDisk-style).
enum SquarifiedTreemap {
    struct LayoutItem {
        let node: FileNode
        let rect: CGRect
    }

    static func layout(nodes: [FileNode], in rect: CGRect) -> [LayoutItem] {
        let positiveNodes = nodes.filter { $0.sizeBytes > 0 }
        guard !positiveNodes.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let total = positiveNodes.reduce(0.0) { $0 + Double($1.sizeBytes) }
        guard total > 0 else { return [] }

        // Normalize sizes to the rect's area so the squarify ratio math is scale-independent.
        let area = Double(rect.width * rect.height)
        let scaled = positiveNodes.map { (node: $0, area: Double($0.sizeBytes) / total * area) }
            .sorted { $0.area > $1.area }

        var result: [LayoutItem] = []
        squarify(items: scaled, rect: rect, result: &result)
        return result
    }

    private static func squarify(
        items: [(node: FileNode, area: Double)],
        rect: CGRect,
        result: inout [LayoutItem]
    ) {
        var remaining = items
        var currentRect = rect

        while !remaining.isEmpty {
            let shortSide = min(currentRect.width, currentRect.height)
            var row: [(node: FileNode, area: Double)] = [remaining[0]]
            var rowAreaSum = remaining[0].area
            var bestWorst = worstRatio(row: row, sideLength: Double(shortSide))

            var i = 1
            while i < remaining.count {
                let candidate = remaining[i]
                let candidateRow = row + [candidate]
                let candidateSum = rowAreaSum + candidate.area
                let candidateWorst = worstRatio(row: candidateRow, sideLength: Double(shortSide), areaSumOverride: candidateSum)

                if candidateWorst <= bestWorst {
                    row = candidateRow
                    rowAreaSum = candidateSum
                    bestWorst = candidateWorst
                    i += 1
                } else {
                    break
                }
            }

            currentRect = placeRow(row, rowAreaSum: rowAreaSum, in: currentRect, result: &result)
            remaining.removeFirst(row.count)
        }
    }

    private static func worstRatio(
        row: [(node: FileNode, area: Double)],
        sideLength: Double,
        areaSumOverride: Double? = nil
    ) -> Double {
        guard sideLength > 0 else { return .infinity }
        let sum = areaSumOverride ?? row.reduce(0.0) { $0 + $1.area }
        guard sum > 0 else { return .infinity }
        let maxArea = row.map(\.area).max() ?? 0
        let minArea = row.map(\.area).min() ?? 0
        guard minArea > 0 else { return .infinity }

        let sideSquared = sideLength * sideLength
        let ratio1 = (sideSquared * maxArea) / (sum * sum)
        let ratio2 = (sum * sum) / (sideSquared * minArea)
        return max(ratio1, ratio2)
    }

    /// Places one row of items along the shorter side of `rect`, returns the remaining rect.
    private static func placeRow(
        _ row: [(node: FileNode, area: Double)],
        rowAreaSum: Double,
        in rect: CGRect,
        result: inout [LayoutItem]
    ) -> CGRect {
        let isHorizontalSplit = rect.width >= rect.height

        if isHorizontalSplit {
            // Row occupies a vertical strip on the left; thickness derived from area.
            let stripWidth = rect.height > 0 ? CGFloat(rowAreaSum / Double(rect.height)) : 0
            var y = rect.minY
            for item in row {
                let h = rect.height > 0 ? CGFloat(item.area / Double(stripWidth == 0 ? 1 : stripWidth)) : 0
                let itemRect = CGRect(x: rect.minX, y: y, width: stripWidth, height: h)
                result.append(LayoutItem(node: item.node, rect: itemRect))
                y += h
            }
            return CGRect(x: rect.minX + stripWidth, y: rect.minY, width: rect.width - stripWidth, height: rect.height)
        } else {
            let stripHeight = rect.width > 0 ? CGFloat(rowAreaSum / Double(rect.width)) : 0
            var x = rect.minX
            for item in row {
                let w = rect.width > 0 ? CGFloat(item.area / Double(stripHeight == 0 ? 1 : stripHeight)) : 0
                let itemRect = CGRect(x: x, y: rect.minY, width: w, height: stripHeight)
                result.append(LayoutItem(node: item.node, rect: itemRect))
                x += w
            }
            return CGRect(x: rect.minX, y: rect.minY + stripHeight, width: rect.width, height: rect.height - stripHeight)
        }
    }
}
