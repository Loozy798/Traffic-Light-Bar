import Foundation

struct TrendPoint: Identifiable {
    let id: Date
    let value: Double
    let segment: Int
}

enum TrendSeries {
    static func points(in samples: [MetricSample], value: KeyPath<MetricSample, Double?>) -> [TrendPoint] {
        var points: [TrendPoint] = []
        var segment = 0
        var previousSource: Int?
        var interrupted = true
        for sample in samples {
            guard let number = sample[keyPath: value], number.isFinite else { interrupted = true; continue }
            if interrupted || sample.segment != previousSource { segment += 1 }
            points.append(TrendPoint(id: sample.id, value: number, segment: segment))
            previousSource = sample.segment
            interrupted = false
        }
        return points
    }
}
