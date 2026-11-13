import SwiftUI

// MARK: - İlk açılış tanıtımı

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pages: [(icon: String, color: Color, title: String, lines: [String])] = [
        ("airplane", .cyan, "Hoş geldin",
         ["Uçuş, İGA CDM'deki stand, tescil, pist ve saatleri tek yerde toplar.",
          "Kilit ekranında, Dynamic Island'da ve saatinde görürsün.",
          "Şimdilik sadece İstanbul Havalimanı (IST) kalkışlı uçuşlarda çalışır."]),
        ("list.bullet.rectangle", .blue, "Uçuşlarını ekle",
         ["Uçuşlarım sekmesinde + ile tarih ve sefer numarası gir.",
          "Tarih UTC'dir: roster'da hangi gün yazıyorsa onu seç.",
          "Ekledikçe takvim bir sonraki güne geçer; geçmiş uçuşlar kendiliğinden silinir."]),
        ("location.fill", .green, "Takibi başlat",
         ["Uçuş günü kartındaki Takibi başlat'a dokun.",
          "Bilgiler CDM'den çekilir ve kilit ekranına, Ada'ya ve saate gelir.",
          "Stand ya da saat değişirse kilit ekranındaki ↻ ile yenile."]),
        ("timer", .yellow, "Sayaçlar",
         ["Yeşil ⌂ sayaç: evden çıkışa kalan süre.",
          "Sarı sayaç: imzaya kalan süre (EOBT − 1:15).",
          "EOBT öne çekilirse imza saati değişmez, ertelenirse yeni saate geçer."]),
        ("rectangle.split.3x1", .purple, "Sekmeler",
         ["Bugün: stand, gate, pist, TOBT/TSAT/CTOT ve gelen uçak.",
          "Tur: imzadan dönüş inişine kadar günün akışı.",
          "Hava: METAR, TAF ve pist rüzgârı; gidiş yeşil, dönüş mavi işaretli."]),
        ("bell.badge", .orange, "İzinler",
         ["Bildirime izin ver: çıkış saatinde uçak sesi çalar.",
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
    @AppStorage("onboardingDone2") private var onboardingDone = false

    var body: some View {
        List {
            Section("Hangi uçuşlar?") {
                bullet("Uygulama İstanbul Havalimanı'nın (IST) CDM sistemini kullanır; bu yüzden şimdilik sadece IST kalkışlı uçuşlarda çalışır. Dış meydandan kalkan seferler (ör. dönüş seferi) CDM'de görünmez.")
                bullet("Varış meydanının havası, pist rüzgârı ve dönüş seferi saatleri yine gösterilir.")
            }
            Section("Uçuş ekleme") {
                bullet("Uçuşlarım sekmesinde + → tarih (UTC, roster'daki gibi) ve sefer numarası (1751 ya da TK1751).")
                bullet("Alttaki mavi Ekle butonu klavye açıkken de görünür; takvim her eklemede bir gün ilerler.")
                bullet("Silmek için uçuşu sola kaydır. Geçmiş günler kendiliğinden silinir.")
            }
            Section("Takibi başlatma") {
                bullet("Sıradaki uçuşun kartında Takibi başlat'a dokun. Listede olmayan bir uçuş için Hızlı arama'ya sefer ya da tescil yaz (1751, LTD, TC-LTD).")
                bullet("Takip başlayınca kart \"Takip ediliyor\" olur; buton Takibi yenile'ye döner.")
                bullet("CDM uçuşu genelde aynı gün gösterir; başka bir günü gösterirse uygulama sorar.")
                bullet("Stand ya da saat değişirse kilit ekranındaki ↻'a dokun: uygulama açılır ve yenilenir. Uygulamada sağ üstteki ↻ da aynı işi yapar; uygulamayı açtığında da kendiliğinden yenilenir.")
                bullet("EOBT öne çekilirse imza ve çıkış saatleri değişmez; ertelenirse yeni saate geçer. Takibi yeniden başlatsan da bu kural geçerli.")
            }
            Section("Sayaçlar ve bildirim") {
                bullet("İmza = EOBT − 1:15. Evden çıkış = imza − Ayarlar'daki süre.")
                bullet("Çıkışa kadar yeşil ⌂ sayaç, sonra sarı imza sayacı. Çıkış saatinde uçak sesli bildirim gelir.")
                bullet("Bildirime dokununca sayaç hemen imzaya geçer; dokunmazsan iOS birkaç dakika içinde geçirir.")
                bullet("İmza + 30 dk'da uçuş Dynamic Island'dan kalkar. Kilit ekranında dönüş inişine kadar (iOS en fazla 4 saat) kalır; uygulamada dönüş inişine kadar durur.")
            }
            Section("Bugün") {
                bullet("Üstte stand, tescil ve sıradaki olay; altında gate, pist, TOBT, TSAT, CTOT kutuları.")
                bullet("Gelen uçak satırına dokununca uçak Flightradar24'te açılır.")
            }
            Section("Tur") {
                bullet("Gelen uçak, imza, kalkış, varış, dönüş ve bitiş adım adım sıralanır.")
                bullet("Üstteki seçiciyle saatleri yerel ya da UTC görebilirsin.")
            }
            Section("Hava") {
                bullet("İstanbul ve varış meydanı için METAR ve TAF. TAF'ta gidiş saatlerine denk gelen gruplar yeşil, dönüş saatlerine denk gelenler mavi işaretlenir.")
                bullet("Pist rüzgârı: yeşil ok karşı, kırmızı arka, turuncu yan rüzgâr. İstanbul'da CDM pisti (aktif), yoksa rüzgâra göre muhtemel pist; varışta son seferlerde inilen pist açılır. Alttaki pist kutucuklarıyla diğer pistlere geçebilirsin.")
            }
            if InboundService.isEnabled {
                Section("Gelen uçak") {
                    bullet("Tescilden uçağın son seferi bulunur: nereden geldiği, ne zaman indiği ve parka girdiği.")
                    bullet("Henüz parkta değilse tahmini park saati = iniş + taksi süresi.")
                    bullet("Taksi süresi her uçuşta gerçek değerlerden öğrenilir; veri arttıkça tahmin iyileşir.")
                }
            }
            Section("Sorun olursa") {
                bullet("Uçuş bulunamadı ya da başka bir uçuş geldi: uçuş CDM'de genelde kalkıştan birkaç saat önce görünür; biraz sonra tekrar dene.")
                bullet("Kilit ekranında ya da Ada'da görünmüyor: Ayarlar > Uçuş > Canlı Etkinlikler açık mı?")
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
