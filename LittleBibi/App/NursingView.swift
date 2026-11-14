import SwiftUI

/// Gece kullanımı için karanlık emzirme sayacı.
struct NursingView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    @State private var burpLogged = false

    private let night = Color(hex: 0x15111C)
    private let panel = Color(hex: 0x261E36)
    private let lilac = Color(hex: 0xBCA2EC)
    private let soft = Color(hex: 0xB5ABC8)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .preferredColorScheme(.dark)
    }

    private func content(now: Date) -> some View {
        let n = store.nursing
        return VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Bugün", systemImage: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(lilac)
                Spacer()
                if n != nil {
                    Button("Vazgeç") { confirmDiscard = true }
                        .font(.body)
                        .foregroundStyle(soft)
                        .frame(minHeight: 44)
                }
            }

            VStack(spacing: 6) {
                Text(statusText(n))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(lilac)
                Text(clockText(currentSeconds(n, now: now)))
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Bu seans toplam · \(clockText(n?.total(at: now) ?? 0))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(soft)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                sideButton(.left, n: n, now: now)
                sideButton(.right, n: n, now: now)
            }

            Text(n == nil ? "Başlamak için emzirdiğiniz tarafa dokunun" : "Taraf değiştirmek için diğerine dokunun")
                .font(.footnote)
                .foregroundStyle(soft)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    store.nursingPauseResume()
                } label: {
                    Text(n?.isRunning == true ? "Duraklat" : "Devam et")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(n?.side == nil)
                .opacity(n?.side == nil ? 0.4 : 1)

                Button {
                    store.logBurp()
                    burpLogged = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        burpLogged = false
                    }
                } label: {
                    Text(burpLogged ? "Kaydedildi" : "Gaz çıktı")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .foregroundStyle(.white)

            Button {
                store.finishNursing()
                dismiss()
            } label: {
                Text("Bitir ve kaydet")
                    .font(.headline)
                    .foregroundStyle(night)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color(hex: 0xF1EAFB), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(n == nil)
            .opacity(n == nil ? 0.4 : 1)

            Text("Sayaç kilit ekranında da görünür. Bu ekranı kapatsanız da çalışmaya devam eder.")
                .font(.caption)
                .foregroundStyle(soft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(night.ignoresSafeArea())
        .confirmationDialog("Bu emzirme kaydedilmeden silinsin mi?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Sil ve kapat", role: .destructive) {
                store.discardNursing()
                dismiss()
            }
            Button("Devam et", role: .cancel) {}
        }
    }

    private func statusText(_ n: ActiveNursing?) -> String {
        guard let n, let side = n.side else { return "HAZIR" }
        return "\(side.title.uppercased(with: Locale(identifier: "tr_TR"))) MEME · \(n.isRunning ? "DEVAM EDİYOR" : "DURAKLATILDI")"
    }

    private func currentSeconds(_ n: ActiveNursing?, now: Date) -> Double {
        guard let n, let side = n.side else { return 0 }
        return n.elapsed(side, at: now)
    }

    private func sideButton(_ side: Side, n: ActiveNursing?, now: Date) -> some View {
        let active = n?.side == side && n?.isRunning == true
        let seconds = n?.elapsed(side, at: now) ?? 0
        return Button {
            store.nursingTap(side)
        } label: {
            VStack(spacing: 6) {
                Text(side.title)
                    .font(.title.bold())
                Text(clockText(seconds))
                    .font(.body.monospacedDigit())
                Text(active ? "Çalışıyor" : " ")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(active ? night : .white)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(active ? lilac : panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side.title) meme, \(Fmt.duration(seconds))\(active ? ", çalışıyor" : "")")
        .accessibilityHint(active ? "Duraklatmak için dokunun" : "Bu tarafa geçmek için dokunun")
    }
}
