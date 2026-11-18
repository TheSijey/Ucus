import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var babyName = ""
    @State private var myName = ""
    @State private var born = false
    @State private var birthDate = Date()
    @State private var sex: BabySex?
    @State private var loaded = false
    @State private var exportURL: URL?
    @ObservedObject private var cloud = CloudSync.shared
    @State private var inviteLink = ""
    @State private var confirmStop = false
    @State private var confirmLeave = false
    @State private var confirmClear = false
    @State private var cleared = false
    @AppStorage(Reminders.scheduleKey) private var remindSchedule = false
    @AppStorage(Reminders.vitaminKey) private var remindVitamin = false
    @AppStorage(Reminders.vitaminMinutesKey) private var vitaminMinutes = 9 * 60

    var body: some View {
        NavigationStack {
            Form {
                Section("Bebek") {
                    TextField("Bebeğin adı", text: $babyName)
                    Toggle("Bebek doğdu", isOn: $born)
                    if born {
                        DatePicker("Doğum tarihi", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                    Picker("Cinsiyet", selection: $sex) {
                        Text("Seçilmedi").tag(BabySex?.none)
                        ForEach(BabySex.allCases) { Text($0.title).tag(BabySex?.some($0)) }
                    }
                }
                Section {
                    TextField("Adınız (ör. Anne, Baba)", text: $myName)
                } header: {
                    Text("Siz")
                } footer: {
                    Text("Bu ad, girdiğiniz kayıtların yanında görünür.")
                }
                familySection
                Section {
                    Toggle("Kontrol ve aşı hatırlatmaları", isOn: $remindSchedule)
                    Toggle("D vitamini hatırlatması", isOn: $remindVitamin)
                    if remindVitamin {
                        DatePicker("Saat", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: vitaminMinutes / 60, minute: vitaminMinutes % 60, second: 0, of: Date()) ?? Date() },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                vitaminMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                            }), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Hatırlatmalar")
                } footer: {
                    Text("Kontrol ve aşılar bir gün önce hatırlatılır. D vitamini, o gün \"verildi\" işaretlenmediyse seçtiğiniz saatte hatırlatılır. Hatırlatmalar doğum tarihi girildikten sonra başlar ve her telefonda ayrı açılır.")
                }
                .onChange(of: remindSchedule) { _, on in remindersChanged(on) }
                .onChange(of: remindVitamin) { _, on in remindersChanged(on) }
                .onChange(of: vitaminMinutes) { _, _ in Reminders.refresh(store) }
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Dosyayı paylaş veya kaydet", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            exportURL = store.exportCSV()
                        } label: {
                            Label("Kayıtları dışa aktar (Excel/CSV)", systemImage: "tablecells")
                        }
                        .disabled(store.entries.isEmpty)
                    }
                } header: {
                    Text("Veriler")
                } footer: {
                    Text("Dışa aktarılan dosya Excel ve Numbers ile açılır.")
                }
                Section {
                    Button("Tüm kayıtları temizle", role: .destructive) { confirmClear = true }
                        .disabled(!store.hasAnyRecords)
                    if cleared {
                        Text("Kayıtlar temizlendi.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Temizle")
                } footer: {
                    Text("Bakım kayıtları, takı defteri, sorular, ölçümler, takvim ve D vitamini işaretleri silinir; eşinizin telefonundan da kalkar. Bebek adı, doğum tarihi, ayarlar ve aile paylaşımı olduğu gibi kalır.")
                }
                .confirmationDialog("Tüm kayıtlar iki telefondan da silinsin mi? Bu işlem geri alınamaz.", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Hepsini sil", role: .destructive) {
                        store.clearAllRecords()
                        cleared = true
                    }
                    Button("Vazgeç", role: .cancel) {}
                }
                Section("Hakkında") {
                    LabeledContent("Sürüm", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("LittleBabbi bir kayıt aracıdır; tıbbi tavsiye vermez ve teşhis koymaz. Bebeğinizin beslenmesi, uykusu ya da sağlığıyla ilgili her soruda çocuk doktorunuza danışın.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Ayarlar")
            .confirmationDialog("Paylaşım durdurulsun mu? Eşiniz yeni kayıtları göremez.", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Paylaşımı durdur", role: .destructive) {
                    Task { await cloud.stopSharing() }
                }
                Button("Vazgeç", role: .cancel) {}
            }
            .confirmationDialog("Aileden ayrılmak istiyor musunuz? Bu telefondaki kayıtlar silinmez.", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Ayrıl", role: .destructive) {
                    Task { await cloud.leave() }
                }
                Button("Vazgeç", role: .cancel) {}
            }
            .onAppear(perform: load)
            .onChange(of: babyName) { _, _ in commit() }
            .onChange(of: myName) { _, _ in commit() }
            .onChange(of: born) { _, _ in commit() }
            .onChange(of: birthDate) { _, _ in commit() }
            .onChange(of: sex) { _, _ in commit() }
        }
    }

    @ViewBuilder
    private var familySection: some View {
        Section {
            switch cloud.state.role {
            case .none:
                Button {
                    Task { await cloud.startSharing() }
                } label: {
                    Label("Eşimle paylaş", systemImage: "person.2.fill")
                }
                .disabled(cloud.busy)
                TextField("Davet linkini buraya yapıştırın", text: $inviteLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    let link = inviteLink
                    Task {
                        await cloud.join(link: link)
                        if cloud.state.role == .participant { inviteLink = "" }
                    }
                } label: {
                    Label("Davet linkiyle katıl", systemImage: "link")
                }
                .disabled(cloud.busy || inviteLink.trimmingCharacters(in: .whitespaces).isEmpty)
            case .owner:
                LabeledContent("Durum", value: cloud.state.shareURL == nil ? "iCloud'a yedekleniyor" : "Paylaşım açık")
                if let link = cloud.state.shareURL, let url = URL(string: link) {
                    ShareLink(item: url, message: Text("LittleBabbi'de bebeğimizin kayıtlarını birlikte tutalım. Önce uygulamayı kur, sonra bu linke dokun.")) {
                        Label("Davet linkini gönder", systemImage: "square.and.arrow.up")
                    }
                    Button("Paylaşımı durdur", role: .destructive) { confirmStop = true }
                        .disabled(cloud.busy)
                } else {
                    Button {
                        Task { await cloud.startSharing() }
                    } label: {
                        Label("Davet linki oluştur", systemImage: "person.2.fill")
                    }
                    .disabled(cloud.busy)
                }
                syncRows
            case .participant:
                LabeledContent("Durum", value: "Aileye bağlı")
                syncRows
                Button("Aileden ayrıl", role: .destructive) { confirmLeave = true }
                    .disabled(cloud.busy)
            }
            if cloud.busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("iCloud ile konuşuluyor…")
                        .foregroundStyle(Theme.muted)
                }
            }
            if let message = cloud.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.noteInk)
            }
        } header: {
            Text("Aile paylaşımı")
        } footer: {
            switch cloud.state.role {
            case .none:
                Text("Biriniz \"Eşimle paylaş\"a basıp linki gönderir; diğeri linke dokunur ya da buraya yapıştırır. İkinizin kayıtları birleşir.")
            case .owner:
                Text("Linki alan herkes kayıtları görebilir ve değiştirebilir; yalnızca ailenizle paylaşın. Devam eden emzirme sayacı paylaşılmaz, biten emzirme paylaşılır.")
            case .participant:
                Text("Kayıtlar eşinizin iCloud'undaki aile alanında tutulur ve iki telefonda da görünür.")
            }
        }
    }

    @ViewBuilder
    private var syncRows: some View {
        LabeledContent("Son eşitleme", value: cloud.state.lastSync.map { Fmt.day($0) + " " + Fmt.time($0) } ?? "Henüz yok")
        if !cloud.state.dirty.isEmpty {
            LabeledContent("Gönderilmeyi bekleyen", value: "\(cloud.state.dirty.count) kayıt")
        }
        Button {
            Task { await cloud.sync() }
        } label: {
            Label("Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func remindersChanged(_ on: Bool) {
        Task {
            if on { _ = await Reminders.requestPermission() }
            Reminders.refresh(store)
        }
    }

    private func load() {
        let p = store.profile
        babyName = p.babyName
        myName = p.myName
        born = p.birthDate != nil
        birthDate = p.birthDate ?? Date()
        sex = p.babySex
        exportURL = nil
        loaded = true
    }

    private func commit() {
        guard loaded else { return }
        var p = store.profile
        p.babyName = babyName.trimmingCharacters(in: .whitespaces)
        let name = myName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { p.myName = name }
        p.birthDate = born ? birthDate : nil
        p.babySex = sex
        if p != store.profile { store.updateProfile(p) }
    }
}
