import SwiftUI

// MARK: - İlk açılış tanıtımı

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pages: [(icon: String, color: Color, title: String, lines: [String])] = [
        ("list.bullet.rectangle", .blue, "Uçuşlarını ekle",
         ["Sağ üstteki + ile tarih ve sefer numarası gir.",
          "Tarih UTC'dir: roster'da ne görüyorsan onu seç.",
          "Ekledikçe takvim bir sonraki güne geçer."]),
        ("airplane.departure", .cyan, "Ada'ya ekle",
         ["Listede uçuşa dokun.",
          "Stand, tescil, gate ve saatler İGA CDM'den gelir.",
          "Kilit ekranında, Ada'da ve saatinde görünür."]),
        ("timer", .green, "Sayaçlar",
         ["Yeşil ⌂ sayaç: evden çıkışa kalan süre.",
          "Sarı sayaç: imzaya kalan süre (EOBT − 1:15).",
          "İmzadan 30 dk sonra her şey kendiliğinden kaybolur."]),
        ("bell.badge", .orange, "İzinler",
         ["Bildirime izin ver: çıkış saatinde chime çalar.",
          "Canlı Etkinlikler açık olmalı (Ayarlar > Uçuş).",
          "Çıkış süresini ⚙ Ayarlar'dan değiştirebilirsin."]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    let p = pages[i]
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: p.icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(p.color)
                        Text(p.title).font(.largeTitle.bold())
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(p.lines, id: \.self) { line in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.color)
                                    Text(line).font(.title3)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "Devam" : "Başla")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button("Geç") { dismiss() }
                .padding()
        }
    }
}

// MARK: - Nasıl kullanılır

struct HelpView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        List {
            Section("Uçuş ekleme") {
                bullet("Sağ üstteki + → tarih (UTC, roster'daki gibi) ve sefer numarası (1751 ya da TK1751).")
                bullet("Alttaki mavi Ekle butonu klavye açıkken de görünür; takvim her eklemede bir gün ilerler.")
                bullet("Silmek için listedeki uçuşu sola kaydır. Geçmiş günler kendiliğinden silinir.")
            }
            Section("Ada'ya ekleme") {
                bullet("Listede uçuşa ya da Hızlı arama'ya sefer/tescil yaz (1751, LTD, TC-LTD).")
                bullet("CDM o günün uçuşunu genelde aynı gün gösterir; başka bir günü gösterirse uygulama sorar.")
                bullet("Stand değişirse kilit ekranındaki ↻ ile yenile; imza saati sabit kalır.")
            }
            Section("Sayaçlar ve bildirim") {
                bullet("İmza = EOBT − 1:15. Evden çıkış = imza − Ayarlar'daki süre.")
                bullet("Çıkışa kadar yeşil ⌂ sayaç, sonra sarı imza sayacı. Çıkış saatinde chime'lı bildirim gelir.")
                bullet("Bildirime dokununca Ada hemen imza sayacına geçer; dokunmazsan iOS birkaç dakika içinde geçirir.")
                bullet("İmzadan 30 dk sonra Ada, kilit ekranı ve saatten kaldırılır.")
            }
            if InboundService.isEnabled {
                Section("Gelen uçak") {
                    bullet("Tescilden uçağın son seferi bulunur: nereden geldiği, ne zaman indiği ve parka girdiği.")
                    bullet("Henüz parkta değilse tahmini park saati = iniş + taksi süresi.")
                    bullet("Taksi süresi her uçuşta gerçek değerlerden öğrenilir; veri arttıkça tahmin iyileşir.")
                }
            }
            Section("Sorun olursa") {
                bullet("Ada çıkmıyor: Ayarlar > Uçuş > Canlı Etkinlikler açık mı?")
                bullet("Bildirim/ses yok: Ayarlar > Uçuş > Bildirimler açık mı? Telefon sessizde mi?")
                bullet("Saatte görünmüyor: iPhone'da Watch uygulaması > Akıllı Yığın > Canlı Etkinlikler.")
                bullet("CDM'den okunamadı: hata yazısındaki \"Sayfada görünen\" kısmının ekran görüntüsünü al.")
            }
            Section {
                Button("Tanıtımı tekrar göster") { onboardingDone = false }
            }
        }
        .navigationTitle("Nasıl kullanılır?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
        }
    }
}
