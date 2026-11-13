import SwiftUI

// MARK: - İlk açılış tanıtımı

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private var pages: [(icon: String, color: Color, title: String, lines: [String])] {
        [
            ("airplane", .cyan, L("Hoş geldin", "Welcome"),
             [L("Uçuş, İGA CDM'deki stand, tescil, pist ve saatleri tek yerde toplar.",
                "Uçuş gathers the stand, registration, runway and times from İGA CDM in one place."),
              L("Kilit ekranında, Dynamic Island'da ve saatinde görürsün.",
                "You see them on the Lock Screen, in the Dynamic Island and on your watch."),
              L("Dış meydandan kalkışta imza ve otelden çıkışı sen girersin, uygulama sayar ve hatırlatır.",
                "For outstation departures you enter sign-on and hotel pickup; the app counts down and reminds you.")]),
            ("list.bullet.rectangle", .blue, L("Uçuşlarını ekle", "Add your flights"),
             [L("Uçuşlarım sekmesinde + ile tarih ve sefer numarası gir.",
                "In My Flights, tap + and enter the date and flight number."),
              L("Tarih UTC'dir: roster'da hangi gün yazıyorsa onu seç.",
                "The date is UTC: pick the day shown on your roster."),
              L("Ekledikçe takvim bir sonraki güne geçer; geçmiş uçuşlar kendiliğinden silinir.",
                "The date moves to the next day after each add; past flights are removed automatically.")]),
            ("location.fill", .green, L("Takibi başlat", "Start tracking"),
             [L("Uçuş günü kartındaki Takibi başlat'a dokun.",
                "On the flight day, tap Start tracking on the card."),
              L("Bilgiler CDM'den çekilir ve kilit ekranına, Ada'ya ve saate gelir.",
                "Data is fetched from CDM and shown on the Lock Screen, Dynamic Island and watch."),
              L("Stand ya da saat değişirse kilit ekranındaki ↻ ile yenile.",
                "If the stand or times change, refresh with ↻ on the Lock Screen.")]),
            ("timer", .yellow, L("Sayaçlar", "Countdowns"),
             [L("Yeşil ⌂ sayaç: evden çıkışa kalan süre.",
                "Green ⌂ countdown: time left until you leave home."),
              L("Sarı sayaç: imzaya kalan süre (EOBT − 1:15).",
                "Yellow countdown: time left to sign-on (EOBT − 1:15)."),
              L("EOBT öne çekilirse imza saati değişmez, ertelenirse yeni saate geçer.",
                "If EOBT moves earlier, sign-on stays; if it's delayed, sign-on follows.")]),
            ("rectangle.split.3x1", .purple, L("Sekmeler", "Tabs"),
             [L("Bugün: stand, gate, pist, TOBT/TSAT/CTOT ve gelen uçak.",
                "Today: stand, gate, runway, TOBT/TSAT/CTOT and the inbound aircraft."),
              L("Tur: imzadan dönüş inişine kadar günün akışı.",
                "Trip: the day from sign-on to the return landing."),
              L("Hava: METAR, TAF ve pist rüzgârı; gidiş yeşil, dönüş mavi işaretli.",
                "Weather: METAR, TAF and runway wind; outbound marked green, return blue.")]),
            ("bell.badge", .orange, L("İzinler", "Permissions"),
             [L("Bildirime izin ver: çıkış saatinde uçak sesi çalar.",
                "Allow notifications: an airplane chime plays when it's time to leave."),
              L("Canlı Etkinlikler açık olmalı (Ayarlar > Uçuş).",
                "Live Activities must be on (Settings > Uçuş)."),
              L("Çıkış süresini ve dili ⚙ Ayarlar'dan değiştirebilirsin.",
                "Change the leave time and language in ⚙ Settings.")]),
        ]
    }

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
                Text(page < pages.count - 1 ? L("Devam", "Next") : L("Başla", "Get started"))
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
            Button(L("Geç", "Skip")) { dismiss() }
                .padding()
        }
    }
}

// MARK: - Nasıl kullanılır

struct HelpView: View {
    @AppStorage("onboardingDone2") private var onboardingDone = false

    var body: some View {
        List {
            Section(L("Hangi uçuşlar?", "Which flights?")) {
                bullet(L("İstanbul kalkışı (gidiş-dönüş ya da yatılı): stand, pist, SID ve saatler İGA CDM'den gelir.",
                         "Istanbul departures (round trip or layover): stand, runway, SID and times come from İGA CDM."))
                bullet(L("Yatılı uçuş: aynı gün dönüş bulunmazsa tur varışta biter, dönüş adımları çıkmaz; kilit ekranı inişten 30 dk sonra kapanır.",
                         "Layover: if no same-day return is found, the trip ends at arrival with no return steps; the Lock Screen closes 30 min after landing."))
                bullet(L("Dış meydan kalkışı (ör. Beyrut → İstanbul): CDM yok; kalkış saati, tescil, gate ve varış uçuş verisinden gelir. Uygulama bunu kendisi anlar.",
                         "Outstation departure (e.g. Beirut → Istanbul): no CDM; departure time, registration, gate and arrival come from flight data. The app detects this itself."))
                bullet(L("Dış meydanda Bugün ekranından otelden çıkış, imza ve standı girersin (meydanın yerel saatiyle). Otel sayacı ve hatırlatma bunlara göre çalışır; imza girilmezse kalkış − 1 sa tahmini gösterilir.",
                         "At an outstation, set hotel pickup, sign-on and stand on the Today screen (in local time). The hotel countdown and reminder follow them; without a sign-on, departure − 1 h is shown as an estimate."))
            }
            Section(L("Uçuş ekleme", "Adding flights")) {
                bullet(L("Uçuşlarım sekmesinde + → tarih (UTC, roster'daki gibi) ve sefer numarası (1751 ya da TK1751).",
                         "In My Flights, + → date (UTC, as on your roster) and flight number (1751 or TK1751)."))
                bullet(L("Alttaki mavi Ekle butonu klavye açıkken de görünür; takvim her eklemede bir gün ilerler.",
                         "The blue Add button stays visible with the keyboard open; the date advances one day per add."))
                bullet(L("Silmek için uçuşu sola kaydır. Geçmiş günler kendiliğinden silinir.",
                         "Swipe a flight left to delete it. Past days are removed automatically."))
            }
            Section(L("Takibi başlatma", "Starting tracking")) {
                bullet(L("Sıradaki uçuşun kartında Takibi başlat'a dokun. Listede olmayan bir uçuş için Hızlı arama'ya sefer ya da tescil yaz (1751, LTD, TC-LTD).",
                         "Tap Start tracking on the next flight's card. For a flight not in your list, type a flight or registration in Quick search (1751, LTD, TC-LTD)."))
                bullet(L("Takip başlayınca kart \"Takip ediliyor\" olur; buton Takibi yenile'ye döner.",
                         "Once tracking starts the card shows \"Tracking\" and the button becomes Refresh tracking."))
                bullet(L("CDM uçuşu genelde aynı gün gösterir; başka bir günü gösterirse uygulama sorar.",
                         "CDM usually shows a flight on its day; if it shows another day, the app asks."))
                bullet(L("Stand ya da saat değişirse kilit ekranındaki ↻'a dokun: uygulama açılır ve yenilenir. Uygulamada sağ üstteki ↻ da aynı işi yapar; uygulamayı açtığında da kendiliğinden yenilenir.",
                         "If the stand or times change, tap ↻ on the Lock Screen: the app opens and refreshes. The ↻ at the top right of the app does the same, and the app also refreshes when opened."))
                bullet(L("EOBT öne çekilirse imza ve çıkış saatleri değişmez; ertelenirse yeni saate geçer. Takibi yeniden başlatsan da bu kural geçerli.",
                         "If EOBT moves earlier, sign-on and leave times stay; if delayed, they follow. This holds even if you restart tracking."))
            }
            Section(L("Sayaçlar ve bildirim", "Countdowns and alerts")) {
                bullet(L("İmza = EOBT − 1:15. Evden çıkış = imza − Ayarlar'daki süre.",
                         "Sign-on = EOBT − 1:15. Leave home = sign-on − the time in Settings."))
                bullet(L("Çıkışa kadar yeşil ⌂ sayaç, sonra sarı imza sayacı. Çıkış saatinde uçak sesli bildirim gelir.",
                         "Green ⌂ countdown until you leave, then the yellow sign-on countdown. An alert with the airplane chime arrives at leave time."))
                bullet(L("Bildirime dokununca sayaç hemen imzaya geçer; dokunmazsan iOS birkaç dakika içinde geçirir.",
                         "Tapping the alert switches to the sign-on countdown right away; otherwise iOS switches within a few minutes."))
                bullet(L("İmza + 30 dk'da uçuş Dynamic Island'dan kalkar. Kilit ekranında dönüş inişine kadar (iOS en fazla 4 saat) kalır; uygulamada dönüş inişine kadar durur.",
                         "At sign-on + 30 min the flight leaves the Dynamic Island. It stays on the Lock Screen until the return landing (iOS allows up to 4 hours) and in the app until the return landing."))
            }
            Section(L("Bugün", "Today")) {
                bullet(L("Üstte stand, tescil ve sıradaki olay; altında gate, pist, TOBT, TSAT, CTOT kutuları.",
                         "Stand, registration and the next event at the top; gate, runway, TOBT, TSAT, CTOT tiles below."))
                bullet(L("Gelen uçak satırına dokununca uçak Flightradar24'te açılır.",
                         "Tap the inbound row to open the aircraft in Flightradar24."))
            }
            Section(L("Tur", "Trip")) {
                bullet(L("Gelen uçak, imza, kalkış, varış, dönüş ve bitiş adım adım sıralanır.",
                         "Inbound, sign-on, departure, arrival, return and duty end, step by step."))
                bullet(L("Üstteki seçiciyle saatleri yerel ya da UTC görebilirsin.",
                         "Use the picker at the top to see times in local or UTC."))
            }
            Section(L("Hava", "Weather")) {
                bullet(L("İstanbul ve varış meydanı için METAR ve TAF. TAF'ta gidiş saatlerine denk gelen gruplar yeşil, dönüş saatlerine denk gelenler mavi işaretlenir.",
                         "METAR and TAF for Istanbul and the destination. TAF groups covering the outbound times are marked green, those covering the return times blue."))
                bullet(L("Pist rüzgârı: yeşil ok karşı, kırmızı arka, turuncu yan rüzgâr; değerler okların yanında yazar. İstanbul'da CDM pisti (aktif), yoksa rüzgâra göre muhtemel pist; varışta son seferlerde inilen pist açılır. Alttaki pist kutucuklarıyla diğer pistlere geçebilirsin.",
                         "Runway wind: green arrow headwind, red tailwind, orange crosswind; values are shown next to the arrows. At Istanbul the CDM runway (active) opens, otherwise the likely runway by wind; at the destination, the runway used on recent flights. Use the runway chips to switch."))
            }
            if InboundService.isEnabled {
                Section(L("Gelen uçak", "Inbound aircraft")) {
                    bullet(L("Tescilden uçağın son seferi bulunur: nereden geldiği, ne zaman indiği ve parka girdiği.",
                             "The aircraft's last flight is found from its registration: where it came from, when it landed and reached the stand."))
                    bullet(L("Henüz parkta değilse tahmini park saati = iniş + taksi süresi.",
                             "If not on stand yet, estimated on-block = landing + taxi time."))
                    bullet(L("Taksi süresi her uçuşta gerçek değerlerden öğrenilir; veri arttıkça tahmin iyileşir.",
                             "Taxi time is learned from real values on each flight; the estimate improves with more data."))
                }
            }
            Section(L("Sorun olursa", "Troubleshooting")) {
                bullet(L("Uçuş bulunamadı ya da başka bir uçuş geldi: uçuş CDM'de genelde kalkıştan birkaç saat önce görünür; biraz sonra tekrar dene.",
                         "Flight not found or a different flight came up: flights usually appear in CDM a few hours before departure; try again a bit later."))
                bullet(L("Kilit ekranında ya da Ada'da görünmüyor: Ayarlar > Uçuş > Canlı Etkinlikler açık mı?",
                         "Not on the Lock Screen or Dynamic Island: is Settings > Uçuş > Live Activities on?"))
                bullet(L("Bildirim/ses yok: Ayarlar > Uçuş > Bildirimler açık mı? Telefon sessizde mi?",
                         "No alert/sound: is Settings > Uçuş > Notifications on? Is the phone on silent?"))
                bullet(L("Saatte görünmüyor: iPhone'da Watch uygulaması > Akıllı Yığın > Canlı Etkinlikler.",
                         "Not on the watch: Watch app on iPhone > Smart Stack > Live Activities."))
                bullet(L("CDM'den okunamadı: hata yazısındaki \"Sayfada görünen\" kısmının ekran görüntüsünü al.",
                         "Couldn't read CDM: take a screenshot of the \"Page shows\" part of the error."))
            }
            Section {
                Button(L("Tanıtımı tekrar göster", "Show the intro again")) { onboardingDone = false }
            }
        }
        .navigationTitle(L("Nasıl kullanılır?", "How to use"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
        }
    }
}
