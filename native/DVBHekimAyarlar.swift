import SwiftUI
import CoreLocation
import CoreImage.CIFilterBuiltins

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000345 — KLİNİK YÖNETİMİ: hekim panelinin kalan bölümleri uygulamada.
//
// Kullanıcı (9 Eki 2026): "eksik kalan ne varsa app de yap en son derle ve son sürüm olarak gönder".
//
// Bu dosya: yönetim menüsü, muayenehane adresleri, anlaşmalı sigortalar, randevu onayı + hasta bildirim + WhatsApp
// ayarları, randevu sayfası (bağlantı + QR), memnuniyet, raporlar, sorun bildirme. Kurallar sunucuda
// (HekimAyarlarApiController — web panel denetleyicileriyle aynı). Menüde yalnız sunucunun açtığı bölümler görünür.
// ⛔ App Store 3.1.1: paket yükseltme / satın alma yönlendirmesi yok.
// ═══════════════════════════════════════════════════════════════════════════════

/// Basit sunucu yanıtı (ok + mesaj).
struct DVBYonCevap: Decodable {
    let ok: Bool?
    let message: String?
}

// MARK: - Yönetim menüsü

struct DVBHekimYonetimView: View {
    @EnvironmentObject private var session: DVBSession

    var body: some View {
        List {
            if let f = session.hekim?.features {
                Section("Muayenehane") {
                    if f.locations == true { satir("Adreslerim", "mappin.and.ellipse", DVBAdreslerView()) }
                    if f.insurances == true { satir("Anlaşmalı sigortalar", "cross.case", DVBSigortalarView()) }
                    if f.bookingSettings == true { satir("Randevu ve bildirim ayarları", "slider.horizontal.3", DVBRandevuAyarlariView()) }
                    if f.bookingPage == true { satir("Randevu sayfam (bağlantı ve QR)", "qrcode", DVBRandevuSayfasiView()) }
                }
                Section("Raporlar") {
                    if f.reports == true { satir("Raporlar", "chart.bar", DVBRaporlarView()) }
                    if f.nps == true { satir("Hasta memnuniyeti", "face.smiling", DVBMemnuniyetView()) }
                }
                Section("Finans") {
                    if f.packages == true { satir("Seans paketleri", "square.stack.3d.up", DVBPaketlerView()) }
                    if f.recurring == true { satir("Sabit giderler", "arrow.triangle.2.circlepath", DVBSabitGiderlerView()) }
                    if f.accountingSetup == true { satir("Muhasebe tanımları", "list.bullet.indent", DVBMuhasebeTanimlariView()) }
                    if f.incomingInvoices == true { satir("Gelen faturalar", "tray.and.arrow.down", DVBGelenFaturalarView()) }
                }
                Section("Ekip ve satış") {
                    if f.staff == true { satir("Personel", "person.3", DVBPersonelView()) }
                    if f.secretaries == true { satir("Sekreter yetkileri", "person.badge.key", DVBSekreterlerView()) }
                    if f.leads == true { satir("Satış adayları", "person.crop.circle.badge.plus", DVBSatisAdaylariView()) }
                }
                if f.issues == true {
                    Section {
                        satir("Sorun bildir / öneri", "exclamationmark.bubble", DVBSorunBildirView())
                    } footer: {
                        Text("Bildiriminiz ekibimize kayıt numarasıyla ulaşır; durumunu buradan izleyebilirsiniz.")
                    }
                }
            }
        }
        .navigationTitle("Klinik yönetimi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func satir<V: View>(_ baslik: String, _ simge: String, _ hedef: V) -> some View {
        NavigationLink(destination: hedef) { Label(baslik, systemImage: simge) }
    }
}

// MARK: - Ortak biçim

enum DVBYonBicim {
    static func ymd(_ d: Date) -> String { DVBSaat.anahtar(d) }

    static func tarih(_ ymd: String?) -> Date? {
        guard let ymd else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: ymd)
    }

    static func kirp(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Adreslerim

struct DVBAdres: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String
    let name: String
    let cityId: Int?
    let city: String?
    let districtId: Int?
    let district: String?
    let address: String?
    let phone: String?
    let lat: Double?
    let lng: Double?
    let isActive: Bool
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, name, city, district, address, phone, lat, lng
        case cityId = "city_id"
        case districtId = "district_id"
        case isActive = "is_active"
        case isPrimary = "is_primary"
    }
}

private struct DVBAdresListesi: Decodable {
    let data: [DVBAdres]
}

struct DVBAdreslerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var adresler: [DVBAdres]?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var duzenlenen: DVBAdres?
    @State private var yeniAcik = false
    @State private var silinecek: DVBAdres?

    var body: some View {
        Group {
            if let a = adresler {
                List {
                    Section {
                        if a.isEmpty { Text("Henüz adres yok.").foregroundColor(.secondary) }
                        ForEach(a) { adr in
                            Button { duzenlenen = adr } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(adr.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                        if adr.isPrimary { Text("Birincil").font(.caption2.weight(.semibold)).foregroundColor(DVBTheme.accent) }
                                        if !adr.isActive { Text("Pasif").font(.caption2).foregroundColor(.secondary) }
                                    }
                                    Text([adr.district, adr.city].compactMap { $0 }.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                                    if let ad = adr.address, !ad.isEmpty { Text(ad).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { silinecek = adr } label: { Label("Sil", systemImage: "trash") }
                            }
                        }
                    } footer: {
                        Text("Birincil adres profilinizde ve hastaya giden randevu mesajında konum olarak görünür.")
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "mappin.slash", title: "Adresler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Adreslerim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { yeniAcik = true } label: { Label("Adres ekle", systemImage: "plus") }
            }
        }
        .task { await yukle() }
        .alert("Adreslerim", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .confirmationDialog("Adres silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let a = silinecek { Task { await sil(a.id) } }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        }
        .sheet(isPresented: $yeniAcik) {
            DVBAdresFormView(adres: nil) { m in bilgi = m; Task { await yukle() } }.environmentObject(session)
        }
        .sheet(item: $duzenlenen) { a in
            DVBAdresFormView(adres: a) { m in bilgi = m; Task { await yukle() } }.environmentObject(session)
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBAdresListesi = try await DVBAPI.shared.get("my/doctor/locations", token: token)
            adresler = c.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func sil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.delete("my/doctor/locations/\(id)", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

struct DVBAdresFormView: View {
    let adres: DVBAdres?
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var tur: String
    @State private var ad: String
    @State private var ilId: Int?
    @State private var ilceId: Int?
    @State private var acikAdres: String
    @State private var telefon: String
    @State private var harita = ""
    @State private var haritaDegisti = false
    @State private var etkin: Bool
    @State private var birincil: Bool
    @State private var iller: [DVBIl] = []
    @State private var ilceler: [DVBIlce] = []
    @State private var konumAliniyor = false
    @State private var calisiyor = false
    @State private var hata: String?

    init(adres: DVBAdres?, kaydedildi: @escaping (String) -> Void) {
        self.adres = adres
        self.kaydedildi = kaydedildi
        _tur = State(initialValue: adres?.type ?? "muayenehane")
        _ad = State(initialValue: adres?.name ?? "")
        _ilId = State(initialValue: adres?.cityId)
        _ilceId = State(initialValue: adres?.districtId)
        _acikAdres = State(initialValue: adres?.address ?? "")
        _telefon = State(initialValue: adres?.phone ?? "")
        _etkin = State(initialValue: adres?.isActive ?? true)
        _birincil = State(initialValue: adres?.isPrimary ?? false)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Tür", selection: $tur) {
                        Text("Muayenehane").tag("muayenehane")
                        Text("Klinik").tag("klinik")
                        Text("Hastane").tag("hastane")
                    }
                    TextField("Ad (ör. Alsancak Muayenehanesi)", text: $ad)
                    DVBAramaliSecici(baslik: "İl", secenekler: iller.map { DVBSecenek(id: $0.id, ad: $0.name, populer: $0.popular ?? false) }, secili: $ilId)
                    if ilId != nil {
                        DVBAramaliSecici(baslik: "İlçe", secenekler: ilceler.map { DVBSecenek(id: $0.id, ad: $0.name) }, secili: $ilceId)
                    }
                    TextField("Açık adres", text: $acikAdres)
                    TextField("Telefon (isteğe bağlı)", text: $telefon).keyboardType(.phonePad)
                }
                Section {
                    TextField("Google Haritalar bağlantısı ya da enlem,boylam", text: $harita)
                        .autocapitalization(.none).disableAutocorrection(true)
                        .onChange(of: harita) { _ in haritaDegisti = true }
                    Button {
                        Task { await konumuKullan() }
                    } label: {
                        HStack {
                            Label("Bulunduğum konumu kullan", systemImage: "location")
                            if konumAliniyor { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(konumAliniyor)
                    if let a = adres, let lat = a.lat, let lng = a.lng, !haritaDegisti {
                        Text("Kayıtlı konum: \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng))").font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Harita konumu")
                } footer: {
                    Text("Hastaya giden randevu mesajındaki yol tarifi bu konumu kullanır. Boş bırakırsanız kayıtlı konum değişmez.")
                }
                Section {
                    Toggle("Etkin", isOn: $etkin)
                    Toggle("Birincil adres", isOn: $birincil)
                }
                if let hata { Section { Text(hata).foregroundColor(.red).font(.subheadline) } }
            }
            .navigationTitle(adres == nil ? "Adres ekle" : "Adresi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await kaydet() } } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(calisiyor || DVBYonBicim.kirp(ad).isEmpty)
                }
            }
            .task { await illeriYukle() }
            .onChange(of: ilId) { _ in Task { await ilceleriYukle(sifirla: true) } }
        }
        .navigationViewStyle(.stack)
    }

    private func illeriYukle() async {
        guard iller.isEmpty else { return }
        if let c: DVBList<DVBIl> = try? await DVBAPI.shared.get("geo/cities") { iller = c.data }
        await ilceleriYukle(sifirla: false)
    }

    private func ilceleriYukle(sifirla: Bool) async {
        guard let ilId else { ilceler = []; return }
        if sifirla { ilceId = nil }
        if let c: DVBList<DVBIlce> = try? await DVBAPI.shared.get("geo/districts", query: ["city_id": String(ilId)]) { ilceler = c.data }
    }

    private func konumuKullan() async {
        konumAliniyor = true
        defer { konumAliniyor = false }
        if let k = await DVBKonum.shared.konumAl() {
            harita = String(format: "%.6f,%.6f", k.coordinate.latitude, k.coordinate.longitude)
            haritaDegisti = true
        } else {
            hata = "Konum alınamadı. Ayarlar'dan konum iznini kontrol edin ya da Google Haritalar bağlantısını yapıştırın."
        }
    }

    private func kaydet() async {
        guard let token = session.token, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "type": tur, "name": DVBYonBicim.kirp(ad), "address": DVBYonBicim.kirp(acikAdres),
            "phone": DVBYonBicim.kirp(telefon), "is_active": etkin, "is_primary": birincil,
        ]
        if let ilId { govde["city_id"] = ilId }
        if let ilceId { govde["district_id"] = ilceId }
        if haritaDegisti && !DVBYonBicim.kirp(harita).isEmpty { govde["harita"] = DVBYonBicim.kirp(harita) }
        do {
            let c: DVBYonCevap
            if let adres {
                c = try await DVBAPI.shared.put("my/doctor/locations/\(adres.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/locations", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Adres kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Anlaşmalı sigortalar

private struct DVBSigortaVerisi: Decodable {
    let companies: [Sirket]
    let selected: [String]

    struct Sirket: Decodable, Identifiable {
        let id: Int
        let name: String
        let types: [Tur]
    }

    struct Tur: Decodable, Hashable {
        let key: String
        let label: String
        let token: String
    }
}

struct DVBSigortalarView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBSigortaVerisi?
    @State private var secili: Set<String> = []
    @State private var arama = ""
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var calisiyor = false

    var body: some View {
        Group {
            if let v = veri {
                List {
                    ForEach(v.companies.filter { arama.isEmpty || DVBArama.katla($0.name).contains(DVBArama.katla(arama)) }) { s in
                        Section(s.name) {
                            ForEach(s.types, id: \.token) { t in
                                Toggle(t.label, isOn: Binding(get: { secili.contains(t.token) }, set: { yeni in
                                    if yeni { secili.insert(t.token) } else { secili.remove(t.token) }
                                }))
                            }
                        }
                    }
                }
                .searchable(text: $arama, prompt: "Sigorta şirketi ara")
            } else if let hata {
                DVBStateView(icon: "cross.case", title: "Sigortalar alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Anlaşmalı sigortalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await kaydet() } } label: {
                    if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                }
                .disabled(veri == nil || calisiyor)
            }
        }
        .task { if veri == nil { await yukle() } }
        .alert("Sigortalar", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBSigortaVerisi = try await DVBAPI.shared.get("my/doctor/insurances", token: token)
            veri = v
            secili = Set(v.selected)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.put("my/doctor/insurances", body: ["items": Array(secili)], token: token)
            bilgi = c.message
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Randevu ve bildirim ayarları

private struct DVBRandevuAyarlari: Decodable {
    let editable: Bool
    let autoConfirm: Bool
    let autoConfirmMinDays: Int
    let hastaBildirimKapali: Bool
    let hastaHatirlatmaKapali: Bool
    let hastaYorumIstegiKapali: Bool
    let randevuOnayNotu: String?
    let whatsappAvailable: Bool
    let waSharePrice: Bool
    let waAutoBook: Bool
    let waAutoBookPlatform: Bool
    let approvalRules: [Kural]
    let message: String?

    struct Kural: Decodable, Identifiable {
        let id: Int
        let day: String
        let range: String
        let note: String?
    }

    enum CodingKeys: String, CodingKey {
        case editable, message
        case autoConfirm = "auto_confirm"
        case autoConfirmMinDays = "auto_confirm_min_days"
        case hastaBildirimKapali = "hasta_bildirim_kapali"
        case hastaHatirlatmaKapali = "hasta_hatirlatma_kapali"
        case hastaYorumIstegiKapali = "hasta_yorum_istegi_kapali"
        case randevuOnayNotu = "randevu_onay_notu"
        case whatsappAvailable = "whatsapp_available"
        case waSharePrice = "wa_share_price"
        case waAutoBook = "wa_auto_book"
        case waAutoBookPlatform = "wa_auto_book_platform"
        case approvalRules = "approval_rules"
    }
}

struct DVBRandevuAyarlariView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBRandevuAyarlari?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var calisiyor = false
    @State private var kuralAcik = false

    @State private var otoOnay = false
    @State private var enErkenGun = 1
    @State private var bildirimKapali = false
    @State private var hatirlatmaKapali = false
    @State private var yorumKapali = false
    @State private var onayNotu = ""
    @State private var fiyatPaylas = false
    @State private var otoRandevu = false

    var body: some View {
        Group {
            if let v = veri {
                form(v)
            } else if let hata {
                DVBStateView(icon: "slider.horizontal.3", title: "Ayarlar alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Randevu ayarları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await kaydet() } } label: {
                    if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                }
                .disabled(veri?.editable != true || calisiyor)
            }
        }
        .task { if veri == nil { await yukle() } }
        .alert("Randevu ayarları", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .sheet(isPresented: $kuralAcik) {
            DVBOnayKuraliEkleView { yeni in veri = yeni; bilgi = yeni.message }.environmentObject(session)
        }
    }

    private func form(_ v: DVBRandevuAyarlari) -> some View {
        Form {
            if !v.editable {
                Section { Text("Bu ayarlar klinik/hekim düzeyindedir; yalnız hekim ya da klinik sahibi değiştirebilir.").font(.footnote).foregroundColor(.secondary) }
            }
            Section {
                Toggle("Randevuları otomatik onayla", isOn: $otoOnay)
                if otoOnay {
                    Stepper("En erken \(enErkenGun) gün sonrası", value: $enErkenGun, in: 0...30)
                }
            } header: {
                Text("Onay")
            } footer: {
                Text("Örneğin 1 seçilirse bugüne alınan randevu otomatik onaylanmaz, sizin onayınıza düşer.")
            }

            Section {
                ForEach(v.approvalRules) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(k.day) · \(k.range)").font(.subheadline)
                        if let n = k.note, !n.isEmpty { Text(n).font(.caption).foregroundColor(.secondary) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { Task { await kuralSil(k.id) } } label: { Label("Sil", systemImage: "trash") }
                    }
                }
                Button { kuralAcik = true } label: { Label("Aralık ekle", systemImage: "plus.circle") }
            } header: {
                Text("Onay gerektiren aralıklar")
            } footer: {
                Text("Bu aralıklara düşen randevular otomatik onay açık olsa da sizin onayınızı bekler.")
            }

            Section {
                Toggle("Hastaya randevu bildirimi gönderme", isOn: $bildirimKapali)
                Toggle("Hastaya hatırlatma gönderme", isOn: $hatirlatmaKapali)
                Toggle("Hastadan yorum isteme", isOn: $yorumKapali)
                TextField("Onay mesajına not (ör. 10 dk önce gelin)", text: $onayNotu)
            } header: {
                Text("Hastaya giden bildirimler")
            } footer: {
                Text("Not, hastaya giden randevu onayı mesajına eklenir (tek satır, en çok 300 karakter).")
            }

            if v.whatsappAvailable {
                Section {
                    Toggle("WhatsApp'ta fiyat bilgisini paylaş", isOn: $fiyatPaylas)
                    if v.waAutoBookPlatform {
                        Toggle("WhatsApp'tan otomatik randevu", isOn: $otoRandevu)
                    }
                } header: {
                    Text("WhatsApp")
                }
            }
        }
        .disabled(!v.editable)
    }

    private func doldur(_ v: DVBRandevuAyarlari) {
        otoOnay = v.autoConfirm
        enErkenGun = v.autoConfirmMinDays
        bildirimKapali = v.hastaBildirimKapali
        hatirlatmaKapali = v.hastaHatirlatmaKapali
        yorumKapali = v.hastaYorumIstegiKapali
        onayNotu = v.randevuOnayNotu ?? ""
        fiyatPaylas = v.waSharePrice
        otoRandevu = v.waAutoBook
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBRandevuAyarlari = try await DVBAPI.shared.get("my/doctor/booking-settings", token: token)
            veri = v
            doldur(v)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        let govde: [String: Any] = [
            "auto_confirm": otoOnay, "auto_confirm_min_days": enErkenGun,
            "hasta_bildirim_kapali": bildirimKapali, "hasta_hatirlatma_kapali": hatirlatmaKapali,
            "hasta_yorum_istegi_kapali": yorumKapali, "randevu_onay_notu": DVBYonBicim.kirp(onayNotu),
            "wa_share_price": fiyatPaylas, "wa_auto_book": otoRandevu,
        ]
        do {
            let v: DVBRandevuAyarlari = try await DVBAPI.shared.put("my/doctor/booking-settings", body: govde, token: token)
            veri = v
            doldur(v)
            bilgi = v.message ?? "Ayarlar kaydedildi."
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func kuralSil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let v: DVBRandevuAyarlari = try await DVBAPI.shared.delete("my/doctor/booking-settings/approval-rules/\(id)", token: token)
            veri = v
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

private struct DVBOnayKuraliEkleView: View {
    var eklendi: (DVBRandevuAyarlari) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var gun: Int = 0
    @State private var tumGun = true
    @State private var bas = DVBSaatCevir.tarih("09:00")
    @State private var bit = DVBSaatCevir.tarih("12:00")
    @State private var not = ""
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationView {
            Form {
                Picker("Gün", selection: $gun) {
                    Text("Her gün").tag(0)
                    ForEach(1...7, id: \.self) { g in Text(DVBYonGunler.ad(g)).tag(g) }
                }
                Toggle("Tüm gün", isOn: $tumGun)
                if !tumGun {
                    DatePicker("Başlangıç", selection: $bas, displayedComponents: .hourAndMinute).environment(\.timeZone, DVBTime.klinik)
                    DatePicker("Bitiş", selection: $bit, displayedComponents: .hourAndMinute).environment(\.timeZone, DVBTime.klinik)
                }
                TextField("Not (isteğe bağlı)", text: $not)
                if let hata { Text(hata).foregroundColor(.red).font(.subheadline) }
            }
            .navigationTitle("Onay aralığı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await ekle() } } label: {
                        if calisiyor { ProgressView() } else { Text("Ekle").bold() }
                    }
                    .disabled(calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ekle() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["full_day": tumGun]
        if gun > 0 { govde["weekday"] = gun }
        if !tumGun {
            govde["start_time"] = DVBSaatCevir.metin(bas)
            govde["end_time"] = DVBSaatCevir.metin(bit)
        }
        let n = DVBYonBicim.kirp(not)
        if !n.isEmpty { govde["note"] = n }
        do {
            let v: DVBRandevuAyarlari = try await DVBAPI.shared.post("my/doctor/booking-settings/approval-rules", body: govde, token: token)
            eklendi(v)
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

enum DVBYonGunler {
    static func ad(_ g: Int) -> String {
        ["", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"][max(0, min(7, g))]
    }
}

// MARK: - Randevu sayfam

private struct DVBRandevuSayfasi: Decodable, Identifiable {
    let id: Int
    let staff: String?
    let url: String
    let headline: String?
    let intro: String?
    let brandColor: String
    let acceptMode: String
    let kvkkRequired: Bool
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, staff, url, headline, intro
        case brandColor = "brand_color"
        case acceptMode = "accept_mode"
        case kvkkRequired = "kvkk_required"
        case isActive = "is_active"
    }
}

private struct DVBRandevuSayfalari: Decodable {
    let data: [DVBRandevuSayfasi]
}

private struct DVBRandevuSayfasiCevabi: Decodable {
    let message: String?
    let page: DVBRandevuSayfasi
}

struct DVBRandevuSayfasiView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var sayfalar: [DVBRandevuSayfasi]?
    @State private var hata: String?

    var body: some View {
        Group {
            if let s = sayfalar {
                List {
                    ForEach(s) { p in
                        NavigationLink(destination: DVBRandevuSayfasiDuzenleView(sayfa: p) { Task { await yukle() } }) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.staff ?? "Klinik randevu sayfası").font(.subheadline.weight(.semibold))
                                Text(p.url).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                if !p.isActive { Text("Kapalı").font(.caption2).foregroundColor(.orange) }
                            }
                        }
                    }
                }
            } else if let hata {
                DVBStateView(icon: "qrcode", title: "Randevu sayfası alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Randevu sayfam")
        .navigationBarTitleDisplayMode(.inline)
        .task { if sayfalar == nil { await yukle() } }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBRandevuSayfalari = try await DVBAPI.shared.get("my/doctor/booking-page", token: token)
            sayfalar = c.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBRandevuSayfasiDuzenleView: View {
    let sayfa: DVBRandevuSayfasi
    var degisti: () -> Void

    @EnvironmentObject private var session: DVBSession
    @State private var url: String
    @State private var baslik: String
    @State private var tanitim: String
    @State private var renk: Color
    @State private var anlik: Bool
    @State private var kvkk: Bool
    @State private var etkin: Bool
    @State private var bilgi: String?
    @State private var yenileOnayi = false
    @State private var calisiyor = false

    init(sayfa: DVBRandevuSayfasi, degisti: @escaping () -> Void) {
        self.sayfa = sayfa
        self.degisti = degisti
        _url = State(initialValue: sayfa.url)
        _baslik = State(initialValue: sayfa.headline ?? "")
        _tanitim = State(initialValue: sayfa.intro ?? "")
        _renk = State(initialValue: DVBRenk.renk(sayfa.brandColor))
        _anlik = State(initialValue: sayfa.acceptMode == "instant")
        _kvkk = State(initialValue: sayfa.kvkkRequired)
        _etkin = State(initialValue: sayfa.isActive)
    }

    var body: some View {
        Form {
            Section {
                if let qr = DVBQR.uret(url) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 220).frame(maxWidth: .infinity)
                }
                Text(url).font(.caption).textSelection(.enabled)
                Button { UIPasteboard.general.string = url; bilgi = "Bağlantı kopyalandı." } label: { Label("Bağlantıyı kopyala", systemImage: "doc.on.doc") }
                if let u = URL(string: url) { DVBPaylasDugmesi(url: u) }
            } header: {
                Text(sayfa.staff ?? "Bağlantı ve QR")
            } footer: {
                Text("Bu bağlantıyı Google İşletme profilinize, Instagram'a ya da web sitenize koyabilirsiniz; QR'ı muayenehanenizde basabilirsiniz.")
            }
            Section("Görünüm") {
                TextField("Başlık", text: $baslik)
                TextField("Kısa tanıtım", text: $tanitim)
                ColorPicker("Marka rengi", selection: $renk, supportsOpacity: false)
            }
            Section {
                Toggle("Randevu anında kesinleşsin", isOn: $anlik)
                Toggle("KVKK onayı zorunlu", isOn: $kvkk)
                Toggle("Sayfa açık", isOn: $etkin)
            } footer: {
                Text("Kapalıysa randevular talep olarak gelir, siz onaylarsınız.")
            }
            Section {
                Button { Task { await kaydet() } } label: {
                    HStack { Text("Kaydet").bold(); if calisiyor { Spacer(); ProgressView() } }
                }
                .disabled(calisiyor)
                Button(role: .destructive) { yenileOnayi = true } label: { Text("Bağlantıyı yenile") }
            } footer: {
                Text("Bağlantıyı yenilerseniz eski bağlantı ve QR çalışmaz.")
            }
        }
        .navigationTitle("Randevu sayfası")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Randevu sayfası", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .alert("Bağlantı yenilensin mi?", isPresented: $yenileOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("Yenile", role: .destructive) { Task { await yenile() } }
        } message: {
            Text("Eski bağlantı ve basılı QR artık çalışmaz; paylaştığınız yerleri güncellemeniz gerekir.")
        }
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        let govde: [String: Any] = [
            "headline": DVBYonBicim.kirp(baslik), "intro": DVBYonBicim.kirp(tanitim), "brand_color": DVBRenk.hex(renk),
            "accept_mode": anlik ? "instant" : "request", "kvkk_required": kvkk, "is_active": etkin,
        ]
        do {
            let c: DVBRandevuSayfasiCevabi = try await DVBAPI.shared.put("my/doctor/booking-page/\(sayfa.id)", body: govde, token: token)
            bilgi = c.message
            degisti()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func yenile() async {
        guard let token = session.token else { return }
        do {
            let c: DVBRandevuSayfasiCevabi = try await DVBAPI.shared.post("my/doctor/booking-page/\(sayfa.id)/rotate", token: token)
            url = c.page.url
            bilgi = c.message
            degisti()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

enum DVBQR {
    static func uret(_ metin: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(metin.utf8)
        f.correctionLevel = "M"
        guard let cikti = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(cikti, from: cikti.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum DVBRenk {
    static func renk(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return DVBTheme.brand }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = { (x: CGFloat) -> Int in max(0, min(255, Int((x * 255).rounded()))) }
        return String(format: "#%02x%02x%02x", k(r), k(g), k(b))
    }
}

// MARK: - Memnuniyet

private struct DVBMemnuniyet: Decodable {
    let summary: Ozet
    let responses: [Yanit]

    struct Ozet: Decodable {
        let nps: Int?
        let total: Int
        let promoters: Int
        let passives: Int
        let detractors: Int
    }

    struct Yanit: Decodable, Hashable {
        let score: Int
        let comment: String?
        let patient: String?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case score, comment, patient
            case createdAt = "created_at"
        }
    }
}

struct DVBMemnuniyetView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBMemnuniyet?
    @State private var hata: String?

    var body: some View {
        Group {
            if let v = veri {
                List {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("NPS").font(.caption).foregroundColor(.secondary)
                                Text(v.summary.nps.map { String($0) } ?? "—").font(.largeTitle.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Tavsiye eden: \(v.summary.promoters)").font(.caption).foregroundColor(DVBTheme.accent)
                                Text("Kararsız: \(v.summary.passives)").font(.caption).foregroundColor(.secondary)
                                Text("Eleştiren: \(v.summary.detractors)").font(.caption).foregroundColor(.red)
                            }
                        }
                    } footer: {
                        Text("Toplam \(v.summary.total) yanıt. Anket randevudan sonraki gün hastaya gider.")
                    }
                    Section("Son yanıtlar") {
                        if v.responses.isEmpty { Text("Henüz yanıt yok.").foregroundColor(.secondary) }
                        ForEach(v.responses, id: \.self) { y in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(y.score)/10").font(.subheadline.weight(.bold))
                                        .foregroundColor(y.score >= 9 ? DVBTheme.accent : (y.score <= 6 ? .red : .orange))
                                    Text(y.patient ?? "").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    if let t = y.createdAt { Text(DVBSaat.gun(t, "d MMM")).font(.caption2).foregroundColor(.secondary) }
                                }
                                if let c = y.comment, !c.isEmpty { Text(c).font(.caption) }
                            }
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "face.smiling", title: "Memnuniyet alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Hasta memnuniyeti")
        .navigationBarTitleDisplayMode(.inline)
        .task { if veri == nil { await yukle() } }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/nps", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Raporlar

private struct DVBRaporOzeti: Decodable {
    let total: Int
    let completed: Int
    let noShow: Int
    let cancelled: Int
    let noShowRate: Int
    let completionRate: Int
    let revenue: Double
    let expense: Double
    let net: Double
    let newPatients: Int
    let channels: [Kanal]

    struct Kanal: Decodable, Hashable {
        let label: String
        let count: Int
    }

    enum CodingKeys: String, CodingKey {
        case total, completed, cancelled, revenue, expense, net, channels
        case noShow = "no_show"
        case noShowRate = "no_show_rate"
        case completionRate = "completion_rate"
        case newPatients = "new_patients"
    }
}

struct DVBRaporlarView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var bas: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var bit = Date()
    @State private var rapor: DVBRaporOzeti?
    @State private var hata: String?
    @State private var onizlenen: DVBYerelDosya?
    @State private var pdfHazirlaniyor = false

    private var anahtar: String { DVBYonBicim.ymd(bas) + "|" + DVBYonBicim.ymd(bit) }

    var body: some View {
        List {
            Section {
                DatePicker("Başlangıç", selection: $bas, displayedComponents: .date).environment(\.timeZone, DVBTime.klinik).environment(\.locale, Locale(identifier: "tr_TR"))
                DatePicker("Bitiş", selection: $bit, displayedComponents: .date).environment(\.timeZone, DVBTime.klinik).environment(\.locale, Locale(identifier: "tr_TR"))
            }
            if let r = rapor {
                Section("Randevular") {
                    satir("Toplam", "\(r.total)")
                    satir("Tamamlanan", "\(r.completed) (%\(r.completionRate))")
                    satir("Gelmeyen", "\(r.noShow) (%\(r.noShowRate))")
                    satir("İptal", "\(r.cancelled)")
                    satir("Yeni hasta", "\(r.newPatients)")
                }
                Section("Gelir / gider") {
                    satir("Gelir", DVBPara.bicim(r.revenue))
                    satir("Gider", DVBPara.bicim(r.expense))
                    satir("Net", DVBPara.bicim(r.net))
                }
                if !r.channels.isEmpty {
                    Section("Randevu kanalları") {
                        ForEach(r.channels, id: \.self) { k in satir(k.label, "\(k.count)") }
                    }
                }
                Section {
                    Button { Task { await pdf() } } label: {
                        HStack { Label("PDF rapor", systemImage: "doc.richtext"); if pdfHazirlaniyor { Spacer(); ProgressView() } }
                    }
                    .disabled(pdfHazirlaniyor)
                }
            } else if let hata {
                Section { Text(hata).foregroundColor(.red) }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Raporlar")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: anahtar) { await yukle() }
        .sheet(item: $onizlenen) { d in DVBBelgeOnizleme(dosya: d.url, kapat: { onizlenen = nil }) }
    }

    private func satir(_ e: String, _ d: String) -> some View {
        HStack { Text(e); Spacer(); Text(d).monospacedDigit().foregroundColor(.secondary) }.font(.subheadline)
    }

    private var sorgu: [String: String] { ["from": DVBYonBicim.ymd(bas), "to": DVBYonBicim.ymd(bit)] }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            rapor = try await DVBAPI.shared.get("my/doctor/reports", query: sorgu, token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func pdf() async {
        guard let token = session.token else { return }
        pdfHazirlaniyor = true
        defer { pdfHazirlaniyor = false }
        do {
            let veri = try await DVBAPI.shared.veri("my/doctor/reports/pdf", query: sorgu, token: token)
            let yol = FileManager.default.temporaryDirectory.appendingPathComponent("Rapor_" + DVBYonBicim.ymd(bas) + "_" + DVBYonBicim.ymd(bit) + ".pdf")
            try veri.write(to: yol, options: .atomic)
            onizlenen = DVBYerelDosya(url: yol)
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Sorun bildir

private struct DVBSorunVerisi: Decodable {
    let data: [Kayit]
    let types: [Secenek]
    let severity: [Secenek]

    struct Kayit: Decodable, Hashable {
        let code: String
        let title: String
        let statusLabel: String?

        enum CodingKeys: String, CodingKey {
            case code, title
            case statusLabel = "status_label"
        }
    }

    struct Secenek: Decodable, Hashable {
        let key: String
        let label: String
    }
}

struct DVBSorunBildirView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBSorunVerisi?
    @State private var baslik = ""
    @State private var aciklama = ""
    @State private var tur = "hata"
    @State private var onem = "orta"
    @State private var calisiyor = false
    @State private var bilgi: String?

    var body: some View {
        Form {
            Section {
                TextField("Kısa başlık", text: $baslik)
                TextEditor(text: $aciklama).frame(minHeight: 120)
                if let v = veri {
                    Picker("Tür", selection: $tur) { ForEach(v.types, id: \.key) { t in Text(t.label).tag(t.key) } }
                    Picker("Önem", selection: $onem) { ForEach(v.severity, id: \.key) { t in Text(t.label).tag(t.key) } }
                }
                Button { Task { await gonder() } } label: {
                    HStack { Text("Gönder").bold(); if calisiyor { Spacer(); ProgressView() } }
                }
                .disabled(calisiyor || DVBYonBicim.kirp(baslik).isEmpty || DVBYonBicim.kirp(aciklama).isEmpty)
            } header: {
                Text("Yeni bildirim")
            } footer: {
                Text("Ne yaptığınızı ve ne beklediğinizi yazın; hangi ekranda olduğunu belirtin.")
            }
            if let v = veri, !v.data.isEmpty {
                Section("Son bildirimlerim") {
                    ForEach(v.data, id: \.self) { k in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.title).font(.subheadline)
                            Text([k.code, k.statusLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sorun bildir")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .alert("Sorun bildir", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        veri = try? await DVBAPI.shared.get("my/doctor/issues", token: token)
    }

    private func gonder() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        let govde: [String: Any] = ["title": DVBYonBicim.kirp(baslik), "description": DVBYonBicim.kirp(aciklama), "type": tur, "severity": onem]
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/issues", body: govde, token: token)
            bilgi = c.message
            baslik = ""
            aciklama = ""
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}
