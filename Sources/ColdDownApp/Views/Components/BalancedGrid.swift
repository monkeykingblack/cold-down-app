import SwiftUI

/// A grid that always fills its width. It computes how many columns of at least `minItemWidth` fit, then
/// balances items across rows (4 items that fit 3-up become 2 × 2, not 3 + 1; 2 items share the full width
/// instead of leaving an empty column). Items in a row get the row's height so cards line up.
struct BalancedGrid: Layout {
    var minItemWidth: CGFloat
    var spacing: CGFloat = Dashboard.spacing

    /// Measuring every subview is by far the expensive part, and one layout pass asks for the size and then
    /// places the items, which measured everything twice. Holding the metrics between those two halves makes
    /// the second one free; SwiftUI resets the cache whenever the subviews change.
    struct Cache {
        var key: Key?
        var metrics: Metrics?
    }

    struct Key: Equatable {
        var width: CGFloat
        var count: Int
        var minItemWidth: CGFloat
        var spacing: CGFloat
    }

    struct Metrics {
        var columns: Int
        var itemWidth: CGFloat
        var rowHeights: [CGFloat]
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? minItemWidth * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let metrics = metrics(width: width, subviews: subviews, cache: &cache)
        let height = metrics.rowHeights.reduce(0, +) + spacing * CGFloat(max(metrics.rowHeights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else { return }
        let metrics = metrics(width: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (row, rowHeight) in metrics.rowHeights.enumerated() {
            for column in 0..<metrics.columns {
                let index = row * metrics.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (metrics.itemWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: metrics.itemWidth, height: rowHeight)
                )
            }
            y += rowHeight + spacing
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews, cache: inout Cache) -> Metrics {
        let key = Key(width: width, count: subviews.count, minItemWidth: minItemWidth, spacing: spacing)
        if cache.key == key, let cached = cache.metrics { return cached }
        let computed = computedMetrics(width: width, subviews: subviews)
        cache.key = key
        cache.metrics = computed
        return computed
    }

    private func computedMetrics(width: CGFloat, subviews: Subviews) -> Metrics {
        let count = subviews.count
        let fitting = max(1, Int((width + spacing) / (minItemWidth + spacing)))
        let rows = Int((Double(count) / Double(min(fitting, count))).rounded(.up))
        let columns = Int((Double(count) / Double(rows)).rounded(.up))
        let itemWidth = max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        let rowHeights = stride(from: 0, to: count, by: columns).map { start in
            subviews[start..<min(start + columns, count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }
                .max() ?? 0
        }
        return Metrics(columns: columns, itemWidth: itemWidth, rowHeights: rowHeights)
    }
}
