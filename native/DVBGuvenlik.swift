import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000279 — İKİ ADIMLI DOĞRULAMA AYARLARI (Hesabım › Güvenlik).
//
// Kullanıcı (1 Eki 2026): "2 aşamalı girişi ios ve androidde aktifleştirebileyim". Android uygulaması siteyi açar
// (TWA) — ayar oradaki web sayfasında. Bu ekran iOS'un yerli Hesabım'ı için; kurallar sunucuda web ile AYNI serviste
// (IkiAdimAyarServisi): yönetim hesabında kapatılamaz, kod gidecek kanal yoksa açılamaz, kanal yalnız politikadaki
// listeden. Kurtarma kodu mevcut şifreyi ister; kodlar yalnız bir kez gösterilir ve cihazda SAKLANMAZ.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBIkiAdimDurumu: Decodable {
    let enabled: Bool
    let mandatory: Bool
    let requiredAtLogin: Bool
    let activeChannel: String?
    let preferredChannel: String?
    let channels: [Kanal]
    let recoveryRemaining: Int

    struct Kanal: Decodable, Hashable {
        let key: String
        let label: String
        let available: Bool
    }

    enum CodingKeys: String, CodingKey {
        case enabled, mandatory, channels
        case requiredAtLogin = "required_at_login"
        case activeChannel = "active_channel"
        case preferredChannel = "preferred_channel"
        case recoveryRemaining = "recovery_remaining"
    }
}

private struct DVBIkiAdimCevabi: Decodable {
    let data: DVBIkiAdimDurumu
}

private struct DVBKurtarmaKodlari: Decodable {
    let codes: [String]
    let message: String?
}

struct DVBIkiAdimAyarView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var durum: DVBIkiAdimDurumu?
    @State private var yukleniyor = false
    @State private var calisiyor = false
    @State private var mesaj: String?
    @State private var hata: String?
    /// Tek sayfa: önce şifre sorulur, doğrulanınca AYNI sayfanın içeriği kodlara döner (iki sayfayı art arda açmak
    /// SwiftUI'da güvenilir değil — kapanan sayfa sürerken ikincisi açılmayabiliyor).
    @State private var kurtarmaSayfasi = false
    @State private var sifre = ""
    @State private var uretilenKodlar: [String]?

    var body: some View {
        Form {
            if let d = durum {
                Section {
                    // Anahtar GERÇEK durumu gösterir: zorunlu hesapta bayrak kapalı olsa bile girişte kod sorulur
                    // (canlıda yönetici hesabı tam böyle) — "kapalı" görünmesi yanıltırdı. Zorunluysa açık + kilitli.
                    Toggle(isOn: Binding(get: { d.enabled || d.mandatory }, set: { yeni in Task { await ayarla(yeni) } })) {
                        Label("İki adımlı doğrulama", systemImage: "lock.shield")
                    }
                    .disabled(calisiyor || d.mandatory)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if d.mandatory {
                            Text("Yönetim hesaplarında iki adımlı doğrulama zorunludur; her girişte kod istenir ve kapatılamaz.")
                        } else {
                            Text("Açıkken her girişte şifrenizden sonra gelen kodu girersiniz. Şifreniz başkasının eline geçse bile hesabınıza giremez.")
                        }
                        if let mesaj { Text(mesaj).foregroundColor(DVBTheme.accent) }
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }

                Section {
                    Picker("Kodun gideceği yer", selection: Binding(
                        get: { d.preferredChannel ?? d.activeChannel ?? "" },
                        set: { yeni in Task { await kanalSec(yeni) } }
                    )) {
                        ForEach(d.channels.filter(\.available), id: \.key) { k in
                            Text(k.label).tag(k.key)
                        }
                    }
                    .disabled(calisiyor)
                } header: {
                    Text("Kod kanalı")
                } footer: {
                    Text("Seçtiğiniz kanala ulaşılamazsa kod sıradaki kanala (e-posta) gönderilir.")
                }

                Section {
                    HStack {
                        Text("Kalan kurtarma kodu")
                        Spacer()
                        Text("\(d.recoveryRemaining)").foregroundColor(.secondary).monospacedDigit()
                    }
                    Button("Yeni kurtarma kodları üret") { sifre = ""; uretilenKodlar = nil; hata = nil; kurtarmaSayfasi = true }
                        .disabled(calisiyor)
                } header: {
                    Text("Kurtarma kodları")
                } footer: {
                    Text("Telefonunuza ve e-postanıza ulaşamadığınızda girişte kod yerine bir kurtarma kodu kullanabilirsiniz. Yeni kodlar üretince eskileri geçersiz olur.")
                }
            } else if yukleniyor {
                ProgressView().frame(maxWidth: .infinity)
            } else if let hata {
                DVBStateView(icon: "wifi.exclamationmark", title: "Ayarlar alınamadı", message: hata) { Task { await yukle() } }
            }
        }
        .navigationTitle("İki adımlı doğrulama")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .sheet(isPresented: $kurtarmaSayfasi, onDismiss: { uretilenKodlar = nil; sifre = "" }) {
            if let kodlar = uretilenKodlar {
                DVBKurtarmaKodlariSayfasi(kodlar: kodlar)
            } else {
                sifreSayfasi
            }
        }
    }

    private var sifreSayfasi: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("Mevcut şifreniz", text: $sifre)
                        .textContentType(.password)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Güvenliğiniz için kurtarma kodu üretmeden önce şifrenizi soruyoruz.")
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle("Şifrenizi doğrulayın")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kurtarmaSayfasi = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Üret") { Task { await kurtarmaKoduUret() } }
                        .disabled(sifre.isEmpty || calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let c: DVBIkiAdimCevabi = try await DVBAPI.shared.get("my/security/two-factor", token: token)
            durum = c.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func ayarla(_ acik: Bool) async {
        guard let token = session.token else { return }
        calisiyor = true; mesaj = nil; hata = nil
        defer { calisiyor = false }
        do {
            let c: DVBIkiAdimCevabi = try await DVBAPI.shared.put("my/security/two-factor", body: ["enabled": acik], token: token)
            durum = c.data
            mesaj = acik ? "İki adımlı doğrulama açıldı. Bir sonraki girişinizde kod istenecek." : "İki adımlı doğrulama kapatıldı."
        } catch {
            let m = DVBError.mesaj(error)
            await yukle()   // anahtar sunucudaki gerçek duruma dönsün (yükleme hatayı siler — mesaj SONRA yazılır)
            if let m { hata = m }
        }
    }

    private func kanalSec(_ kanal: String) async {
        guard let token = session.token, !kanal.isEmpty else { return }
        calisiyor = true; mesaj = nil; hata = nil
        defer { calisiyor = false }
        do {
            let c: DVBIkiAdimCevabi = try await DVBAPI.shared.put("my/security/two-factor/channel", body: ["channel": kanal], token: token)
            durum = c.data
            mesaj = "Doğrulama kodu kanalı güncellendi."
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kurtarmaKoduUret() async {
        guard let token = session.token else { return }
        calisiyor = true; hata = nil
        defer { calisiyor = false }
        do {
            let c: DVBKurtarmaKodlari = try await DVBAPI.shared.post(
                "my/security/two-factor/recovery-codes", body: ["current_password": sifre], token: token
            )
            sifre = ""
            uretilenKodlar = c.codes   // sayfa açık kalır, içerik kodlara döner
            await yukle()
        } catch {
            sifre = ""
            if let m = DVBError.mesaj(error) { hata = m }   // sayfa açık kalır; kişi şifreyi yeniden dener
        }
    }
}

/// Kurtarma kodları — YALNIZ bir kez gösterilir; cihazda saklanmaz. Kopyalama kişinin kendi tercihi.
private struct DVBKurtarmaKodlariSayfasi: View {
    let kodlar: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var kopyalandi = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(kodlar, id: \.self) { kod in
                        Text(kod).font(.body.monospaced()).textSelection(.enabled)
                    }
                } footer: {
                    Text("Bu kodlar bir daha gösterilmez. Güvenli bir yere kaydedin; her kod bir kez kullanılabilir.")
                }
                Section {
                    Button(kopyalandi ? "Kopyalandı" : "Tümünü kopyala") {
                        UIPasteboard.general.string = kodlar.joined(separator: "\n")
                        kopyalandi = true
                    }
                }
            }
            .navigationTitle("Kurtarma kodları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kaydettim") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }
}
