import SwiftUI

/// Günün akışı: imza → gidiş (yeşil) → tur (gri) → dönüş (mavi), "şu an" işaretiyle.
struct DayTimelineData: Codable, Hashable {
    var signOn: Date
    var outDep: Date?
    var outArr: Date?
    var retDep: Date?
    var retArr: Date?
    var destCode: String

    var start: Date { signOn }
    var end: Date? { retArr ?? outArr }
    var isUsable: Bool { outDep != nil && end != nil && (end ?? signOn) > signOn }
}

struct DayTimelineBar: View {
    let data: DayTimelineData
    var height: CGFloat = 10
    var showLegend = true
    var compactLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.25))
                    segment(from: data.signOn, to: data.outDep, color: .gray.opacity(0.55), width: w)
                    segment(from: data.outDep, to: data.outArr, color: .green, width: w)
                    segment(from: data.outArr, to: data.retDep, color: .gray.opacity(0.45), width: w)
                    segment(from: data.retDep, to: data.retArr, color: .blue, width: w)
                    if let x = position(Date(), width: w), x > 0, x < w {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: height + 8)
                            .offset(x: x - 1)
                    }
                }
            }
            .frame(height: height + 8)

            if showLegend {
                if compactLegend {
                    HStack(spacing: 8) {
                        legendItem(.green, data.outDep, data.outArr)
                        if data.retDep != nil { legendItem(.blue, data.retDep, data.retArr) }
                    }
                    .font(.caption2.monospacedDigit())
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        row(.gray, "İmza", data.signOn, nil, nil)
                        row(.green, "Gidiş", data.outDep, data.outArr, data.destCode)
                        if data.retDep != nil { row(.blue, "Dönüş", data.retDep, data.retArr, "IST") }
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func position(_ d: Date?, width: CGFloat) -> CGFloat? {
        guard let d, let end = data.end else { return nil }
        let total = end.timeIntervalSince(data.start)
        guard total > 0 else { return nil }
        return CGFloat(min(max(d.timeIntervalSince(data.start) / total, 0), 1)) * width
    }

    @ViewBuilder
    private func segment(from a: Date?, to b: Date?, color: Color, width: CGFloat) -> some View {
        if let x1 = position(a, width: width), let x2 = position(b, width: width), x2 > x1 {
            Capsule()
                .fill(color)
                .frame(width: max(x2 - x1, 3), height: height)
                .offset(x: x1)
        }
    }

    private func t(_ d: Date?) -> String { d.map { $0.formatted(.dateTime.hour().minute()) } ?? "—" }

    private func legendItem(_ c: Color, _ a: Date?, _ b: Date?) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text("\(t(a))–\(t(b))")
        }
    }

    private func row(_ c: Color, _ title: String, _ a: Date?, _ b: Date?, _ place: String?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(title).frame(width: 46, alignment: .leading).foregroundStyle(.secondary)
            Text(b == nil ? t(a) : "\(t(a)) → \(t(b))")
            if let place, !place.isEmpty { Text(place).foregroundStyle(.secondary) }
        }
    }
}

extension FlightAttributes.ContentState {
    var dayTimeline: DayTimelineData? {
        let d = DayTimelineData(signOn: signOn,
                                outDep: tsat ?? tobt ?? eobt,
                                outArr: turn?.outboundArrival,
                                retDep: turn?.returnDeparture,
                                retArr: turn?.returnArrival,
                                destCode: turn.map { $0.destIATA.isEmpty ? $0.destICAO : $0.destIATA } ?? destination)
        return d.isUsable ? d : nil
    }
}
