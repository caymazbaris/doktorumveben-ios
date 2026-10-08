import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000286 — HEKİMİN TAKVİM EKRANI.
//
// Kullanıcı (2 Eki 2026): "google takvim hatası var ona tıklayınca bu bölüm hesabınızda etkin değil gibi bi uyarı
// geliyor bunu düzenle google ve apple takvim senkronu da yapabilir olsun"; 6 Eki: "yap bunu da ekle".
//
// DVB-000341 — takvim EKLEME de uygulamada. Kullanıcı (8 Eki 2026): "takvim ekleme kısımlarını uygulamaya alalım".
//
// Kurallar sunucuda (HekimTakvimApiController, web takvim sayfasıyla aynı):
// · Apple Takvim aboneliği: hekimin ICS akışına `webcal://` ile tek dokunuşla abonelik (iOS kendi sorar, kendisi yeniler).
// · iCloud (çift yönlü): Apple ID + UYGULAMAYA ÖZEL ŞİFRE formu; şifre sunucuda şifreli saklanır, yanıtta geri gelmez.
// · Google / Outlook: izin SAFARİ'de verilir (OAuth gömülü web görünümünde açılmaz); Safari tek kullanımlık giriş
//   adresiyle (DVB-000273 köprüsü) panelin bağlantı adımına gider. Dönünce ekran kendini yeniler.
// · Dış takvim (ICS/webcal adresi): dolu saatleri içe alır.
// · Bağlantı kaldırma: içe alınan dolu saatler de temizlenir.
// · Paketi olmayan hekime satın alma yönlendirmesi YOK (App Store 3.1.1).
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBTakvimDurumu: Decodable {
    let enabled: Bool
    let message: String?
    let feeds: [Akis]
    let connections: [Baglanti]
    let googleAvailable: Bool?
    let googlePath: String?
    let managePath: String?
    // DVB-000341 — eski sunucuda yok (nil → ilgili düğme gösterilmez).
    let microsoftAvailable: Bool?
    let microsoftPath: String?
    let appleAvailable: Bool?
    let icsAvailable: Bool?
    let canDelete: Bool?
    let providers: [Saglayici]?

    struct Akis: Decodable, Identifiable {
        let label: String
        let url: String
        let webcal: String
        var id: String { url }
    }

    struct Baglanti: Decodable, Identifiable {
        let id: Int
        let provider: String
        let providerLabel: String
        let name: String
        let scope: String?
        let state: String
        let lastSyncedAt: Date?
        let lastError: String?

        enum CodingKeys: String, CodingKey {
            case id, provider, name, scope, state
            case providerLabel = "provider_label"
            case lastSyncedAt = "last_synced_at"
            case lastError = "last_error"
        }
    }

    struct Saglayici: Decodable, Identifiable {
        let id: Int
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case enabled, message, feeds, connections, providers
        case googleAvailable = "google_available"
        case googlePath = "google_path"
        case managePath = "manage_path"
        case microsoftAvailable = "microsoft_available"
        case microsoftPath = "microsoft_path"
        case appleAvailable = "apple_available"
        case icsAvailable = "ics_available"
        case canDelete = "can_delete"
    }
}

private struct DVBTakvimEsitlemeCevabi: Decodable {
    let ok: Bool
    let message: String
    let connection: DVBTakvimDurumu.Baglanti
}

private struct DVBTakvimEklemeCevabi: Decodable {
    let ok: Bool
    let message: String?
}

struct DVBHekimTakvimView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var durum: DVBTakvimDurumu?
    @State private var hata: String?
    @State private var esitlenen: Int?
    @State private var bilgi: String?
    @State private var safariHazirlaniyor = false
    // DVB-000341
    @State private var icloudAcik = false
    @State private var icsAcik = false
    @State private var silinecek: DVBTakvimDurumu.Baglanti?

    var body: some View {
        Group {
            if let d = durum {
                if d.enabled { liste(d) } else { kapali(d) }
            } else if let hata {
                DVBStateView(icon: "calendar.badge.exclamationmark", title: "Takvim bilgisi alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Takvim bağlantıları")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        // Safari'de Google/Outlook bağlandıktan sonra uygulamaya dönülünce durum tazelensin.
        .onChange(of: scenePhase) { yeni in
            if yeni == .active { Task { await yukle() } }
        }
        .alert("Takvim", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .confirmationDialog(
            "Bağlantı kaldırılsın mı?",
            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
            titleVisibility: .visible
        ) {
            Button("Bağlantıyı kaldır", role: .destructive) {
                if let b = silinecek { Task { await kaldir(b.id) } }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        } message: {
            Text("\(silinecek?.name ?? "Bu takvim") artık eşitlenmez; içe alınan dolu saatler de temizlenir.")
        }
        .sheet(isPresented: $icloudAcik) {
            DVBIcloudBaglaView(saglayicilar: durum?.providers ?? []) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $icsAcik) {
            DVBIcsEkleView(saglayicilar: durum?.providers ?? []) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    // MARK: - Paket kapalı

    private func kapali(_ d: DVBTakvimDurumu) -> some View {
        DVBStateView(
            icon: "calendar.badge.minus",
            title: "Takvim eşitleme kapalı",
            message: d.message ?? "Dış takvim eşitlemesi hesabınızın paketinde yok."
        )
    }

    // MARK: - Liste

    private func liste(_ d: DVBTakvimDurumu) -> some View {
        List {
            Section {
                ForEach(d.feeds) { akis in
                    Button {
                        if let url = URL(string: akis.webcal) { openURL(url) }
                    } label: {
                        Label(d.feeds.count > 1 ? akis.label : "iPhone Takvim'e abone ol", systemImage: "calendar.badge.plus")
                    }
                }
            } header: {
                Text("Apple Takvim")
            } footer: {
                Text("Randevularınız iPhone'un Takvim uygulamasında görünür. iOS aboneliği kendiliğinden yeniler; yeni randevunun görünmesi bir saati bulabilir.")
            }

            Section {
                if d.connections.isEmpty {
                    Text("Henüz bağlı takvim yok.").foregroundColor(.secondary)
                } else {
                    ForEach(d.connections) { b in
                        baglantiSatiri(b, silinebilir: d.canDelete == true)
                    }
                }
            } header: {
                Text("Bağlı takvimler")
            } footer: {
                Text(d.canDelete == true
                     ? "Bağlı takvimdeki dolu saatleriniz randevuya kapanır; yeni randevularınız o takvime yazılır. Kaldırmak için satırı sola kaydırın."
                     : "Bağlı takvimdeki dolu saatleriniz randevuya kapanır; yeni randevularınız o takvime yazılır.")
            }

            Section {
                if d.googleAvailable == true, let yol = d.googlePath {
                    safariDugmesi(
                        d.connections.contains(where: { $0.provider == "google" }) ? "Google Takvim'i yeniden bağla" : "Google Takvim'i bağla",
                        simge: "link", yol: yol
                    )
                }
                if d.microsoftAvailable == true, let yol = d.microsoftPath {
                    safariDugmesi(
                        d.connections.contains(where: { $0.provider == "microsoft" }) ? "Outlook'u yeniden bağla" : "Outlook / Microsoft 365 bağla",
                        simge: "envelope.badge", yol: yol
                    )
                }
                if d.appleAvailable == true {
                    Button {
                        icloudAcik = true
                    } label: {
                        Label("iCloud Takvim'i bağla (çift yönlü)", systemImage: "icloud")
                    }
                }
                if d.icsAvailable == true {
                    Button {
                        icsAcik = true
                    } label: {
                        Label("Dış takvim adresi ekle (ICS)", systemImage: "link.badge.plus")
                    }
                }
            } header: {
                Text("Takvim ekle")
            } footer: {
                Text("Google ve Outlook izni güvenlik gereği Safari'de verilir; bağladıktan sonra uygulamaya dönün, durum burada güncellenir. iCloud için Apple'ın ürettiği uygulamaya özel şifre gerekir.")
            }

            if let yol = d.managePath {
                Section {
                    Button {
                        Task { await safarideAc(yol) }
                    } label: {
                        Label("Web panelinde takvim ayarları", systemImage: "safari")
                    }
                    .disabled(safariHazirlaniyor)
                }
            }
        }
        .refreshable { await yukle() }
    }

    private func safariDugmesi(_ baslik: String, simge: String, yol: String) -> some View {
        Button {
            Task { await safarideAc(yol) }
        } label: {
            HStack {
                Label(baslik, systemImage: simge)
                if safariHazirlaniyor { Spacer(); ProgressView() }
            }
        }
        .disabled(safariHazirlaniyor)
    }

    private func baglantiSatiri(_ b: DVBTakvimDurumu.Baglanti, silinebilir: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(b.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(Self.durumEtiketi(b.state)).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Self.durumRengi(b.state).opacity(0.15)).foregroundColor(Self.durumRengi(b.state))
                    .clipShape(Capsule())
            }
            Text([b.providerLabel, b.scope].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundColor(.secondary)
            if let t = b.lastSyncedAt {
                Text("Son eşitleme: \(Self.goreli(t))").font(.caption).foregroundColor(.secondary)
            }
            if let e = b.lastError, !e.isEmpty {
                Text(e).font(.caption).foregroundColor(.red).lineLimit(3)
            }
            HStack(spacing: 16) {
                Button {
                    Task { await esitle(b.id) }
                } label: {
                    HStack(spacing: 6) {
                        if esitlenen == b.id { ProgressView() }
                        Text(esitlenen == b.id ? "Eşitleniyor…" : "Şimdi eşitle")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(esitlenen != nil)
                if silinebilir {
                    Button(role: .destructive) {
                        silinecek = b
                    } label: {
                        Text("Kaldır").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if silinebilir {
                Button(role: .destructive) {
                    silinecek = b
                } label: {
                    Label("Kaldır", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            durum = try await DVBAPI.shared.get("my/doctor/calendar", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func esitle(_ id: Int) async {
        guard let token = session.token, esitlenen == nil else { return }
        esitlenen = id
        defer { esitlenen = nil }
        do {
            let c: DVBTakvimEsitlemeCevabi = try await DVBAPI.shared.post("my/doctor/calendar/connections/\(id)/sync", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func kaldir(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBTakvimEklemeCevabi = try await DVBAPI.shared.delete("my/doctor/calendar/connections/\(id)", token: token)
            bilgi = c.message ?? "Bağlantı kaldırıldı."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    /// Panel sayfasını SAFARİ'de aç: tek kullanımlık giriş adresiyle (iki adımlı doğrulamalı hesapta köprü yok →
    /// sayfa doğrudan açılır, Safari'de kodla giriş istenir).
    private func safarideAc(_ yol: String) async {
        guard let hedef = URL(string: yol, relativeTo: DVBConfig.webBase)?.absoluteURL else { return }
        safariHazirlaniyor = true
        defer { safariHazirlaniyor = false }
        let adres = await DVBWebOturum.kopruAdresi(hedef) ?? hedef
        await MainActor.run { openURL(adres) }
    }

    // MARK: - Biçim

    static func durumEtiketi(_ s: String) -> String {
        switch s {
        case "ok": return "Bağlı"
        case "retrying": return "Yeniden deneniyor"
        case "stale": return "Güncel değil"
        case "paused": return "Duraklatıldı"
        default: return "Hata"
        }
    }

    static func durumRengi(_ s: String) -> Color {
        switch s {
        case "ok": return DVBTheme.accent
        case "retrying": return .orange
        case "paused": return .secondary
        default: return .red
        }
    }

    static func goreli(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - iCloud bağlama (DVB-000341)

/// Apple ID + uygulamaya özel şifre. Web formuyla aynı alanlar (`apple_id`, `app_password`, `name`, `staff_id`).
/// Şifre yalnız bu isteğin gövdesinde gider; cihazda saklanmaz, sunucu yanıtında geri gelmez.
struct DVBIcloudBaglaView: View {
    let saglayicilar: [DVBTakvimDurumu.Saglayici]
    var baglandi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var appleId = ""
    @State private var sifre = ""
    @State private var ad = ""
    @State private var saglayiciId: Int?
    @State private var calisiyor = false
    @State private var hata: String?

    private var hazir: Bool {
        appleId.contains("@") && sifre.filter { $0.isLetter || $0.isNumber }.count >= 8
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Apple ID (e-posta)", text: $appleId)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Uygulamaya özel şifre", text: $sifre)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Takvim adı (isteğe bağlı)", text: $ad)
                } header: {
                    Text("iCloud hesabı")
                } footer: {
                    Text("Normal Apple şifrenizi değil, Apple'ın bu iş için ürettiği 16 harfli \"uygulamaya özel şifre\"yi girin. Tire ve boşluklar önemli değil.")
                }

                if !saglayicilar.isEmpty {
                    Section("Kimin takvimi") {
                        Picker("Sağlayıcı", selection: $saglayiciId) {
                            Text("Klinik geneli").tag(Int?.none)
                            ForEach(saglayicilar) { p in Text(p.name).tag(Int?.some(p.id)) }
                        }
                    }
                }

                Section {
                    Button {
                        if let u = URL(string: "https://account.apple.com/account/manage") { openURL(u) }
                    } label: {
                        Label("Uygulamaya özel şifre nasıl alınır?", systemImage: "questionmark.circle")
                    }
                } footer: {
                    Text("Apple hesabı sayfasında Oturum Açma ve Güvenlik → Uygulamaya Özel Parolalar bölümünden yeni bir şifre oluşturun.")
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle("iCloud Takvim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await bagla() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Bağla").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func bagla() async {
        guard let token = session.token, hazir, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "apple_id": appleId.trimmingCharacters(in: .whitespacesAndNewlines),
            "app_password": sifre,
        ]
        let temizAd = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temizAd.isEmpty { govde["name"] = temizAd }
        if let saglayiciId { govde["staff_id"] = saglayiciId }
        do {
            let c: DVBTakvimEklemeCevabi = try await DVBAPI.shared.post("my/doctor/calendar/apple", body: govde, token: token)
            sifre = ""
            baglandi(c.message ?? "iCloud bağlandı.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Dış takvim (ICS) ekleme (DVB-000341)

struct DVBIcsEkleView: View {
    let saglayicilar: [DVBTakvimDurumu.Saglayici]
    var eklendi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var adres = ""
    @State private var ad = ""
    @State private var saglayiciId: Int?
    @State private var calisiyor = false
    @State private var hata: String?

    private var hazir: Bool {
        let a = adres.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a.hasPrefix("https://") || a.hasPrefix("http://") || a.hasPrefix("webcal://")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://… veya webcal://…", text: $adres)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Takvim adı (isteğe bağlı)", text: $ad)
                } header: {
                    Text("Takvim adresi")
                } footer: {
                    Text("Başka bir randevu sisteminin ya da takvimin \"ICS / iCal paylaşım adresi\"ni yapıştırın. O takvimdeki dolu saatler burada randevuya kapanır.")
                }

                if !saglayicilar.isEmpty {
                    Section("Kimin takvimi") {
                        Picker("Sağlayıcı", selection: $saglayiciId) {
                            Text("Klinik geneli").tag(Int?.none)
                            ForEach(saglayicilar) { p in Text(p.name).tag(Int?.some(p.id)) }
                        }
                    }
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle("Dış takvim ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await ekle() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Ekle").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ekle() async {
        guard let token = session.token, hazir, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["import_feed_url": adres.trimmingCharacters(in: .whitespacesAndNewlines)]
        let temizAd = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temizAd.isEmpty { govde["name"] = temizAd }
        if let saglayiciId { govde["staff_id"] = saglayiciId }
        do {
            let c: DVBTakvimEklemeCevabi = try await DVBAPI.shared.post("my/doctor/calendar/ics", body: govde, token: token)
            eklendi(c.message ?? "Dış takvim eklendi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
