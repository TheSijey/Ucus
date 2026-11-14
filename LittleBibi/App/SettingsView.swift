import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var babyName = ""
    @State private var myName = ""
    @State private var born = false
    @State private var birthDate = Date()
    @State private var loaded = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bebek") {
                    TextField("Bebeğin adı", text: $babyName)
                    Toggle("Bebek doğdu", isOn: $born)
                    if born {
                        DatePicker("Doğum tarihi", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section {
                    TextField("Adınız (ör. Anne, Baba)", text: $myName)
                } header: {
                    Text("Siz")
                } footer: {
                    Text("Bu ad, girdiğiniz kayıtların yanında görünür.")
                }
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
                    Text("Kayıtlar yalnızca bu telefonda saklanır. Eşinizle iCloud üzerinden paylaşım bir sonraki sürümde gelecek.")
                }
                Section("Hakkında") {
                    LabeledContent("Sürüm", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("LittleBibi bir kayıt aracıdır; tıbbi tavsiye vermez ve teşhis koymaz. Bebeğinizin beslenmesi, uykusu ya da sağlığıyla ilgili her soruda çocuk doktorunuza danışın.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear(perform: load)
            .onChange(of: babyName) { _, _ in commit() }
            .onChange(of: myName) { _, _ in commit() }
            .onChange(of: born) { _, _ in commit() }
            .onChange(of: birthDate) { _, _ in commit() }
        }
    }

    private func load() {
        let p = store.profile
        babyName = p.babyName
        myName = p.myName
        born = p.birthDate != nil
        birthDate = p.birthDate ?? Date()
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
        if p != store.profile { store.updateProfile(p) }
    }
}
