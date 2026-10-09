import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000352 — HESABIM, hasta tarafındaki son boşluklar: Puanlarım, Sigortalarım, Verilerimi indir, ödeme bekleyen
// randevular; ve `/hesabim/...` adreslerinin (bildirim, bildirim listesi) doğrudan yerli ekranda açılması.
//
// Kullanıcı (9 Eki 2026): "Hasta tarafındaki küçük boşluklar: Puanlarım, Sigortalarım, Verilerimi indir ve web
// görünümünde açılan profil ve ödemeler sayfalarını yerli ekrana çevirmek".
//
// Sunucu: HastaHesapEkApiController (web LoyaltyController / InsuranceController / ProfileController::export /
// PaymentController ile aynı kurallar). Profil ve ödemeler ekranları DVBHesabim.swift'te (DVB-000266); burada yalnız
// yönlendirme ve ödeme bekleyen randevular bölümü var.
//
// ⛔ Ödeme sayfası uygulama içinde AÇILMAZ (DVB-000271): "Öde" sistem tarayıcısına gider (DVBOdemeAdresi).
// ⛔ Para biçimi tek yerden: DVBPara.bicim (10.000,00 ₺).
// ⚠ iOS 15: `Section("Başlık") { } footer: { }` yok → `Section { } header: { } footer: { }`; alert içinde TextField yok.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Yönlendirme

/// Hesabım sekmesindeki yerli ekranlar. Sunucu adresi (`/hesabim/...`) bunlara eşlenir; web sayfası açılmaz.
enum DVBHastaHesapEkrani: Equatable {
    case profil, odemeler, yakinlar, yorumlar, puanlar, sigortalar, veriIndir

    init?(yol hamYol: String) {
        let yol = hamYol.count > 1 && hamYol.hasSuffix("/") ? String(hamYol.dropLast()) : hamYol
        switch yol {
        case "/hesabim/profil": self = .profil
        case "/hesabim/profil/veri-indir": self = .veriIndir
        case "/hesabim/odemeler": self = .odemeler
        case "/hesabim/yakinlar": self = .yakinlar
        case "/hesabim/yorumlar": self = .yorumlar
        case "/hesabim/puanlarim": self = .puanlar
        case "/hesabim/sigorta": self = .sigortalar
        default: return nil
        }
    }

    @MainActor @ViewBuilder var gorunum: some View {
        switch self {
        case .profil: DVBProfilView()
        case .odemeler: DVBOdemelerView()
        case .yakinlar: DVBYakinlarView()
        case .yorumlar: DVBYorumlarView()
        case .puanlar: DVBPuanlarimView()
        case .sigortalar: DVBSigortalarimView()
        case .veriIndir: DVBVeriIndirView()
        }
    }
}

// MARK: - Modeller

struct DVBPuanBilgisi: Decodable {
    let points: Int
    let code: String?
    let link: String?
    let invited: Int?
    let referralPoints: Int?
    let history: [Hareket]

    enum CodingKeys: String, CodingKey {
        case points, code, link, invited, history
        case referralPoints = "referral_points"
    }

    struct Hareket: Decodable, Identifiable {
        let id: Int
        let points: Int
        let reason: String?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, points, reason
            case createdAt = "created_at"
        }
    }
}

struct DVBHastaSigorta: Decodable, Identifiable {
    let id: Int
    let patientId: Int?
    let patientName: String?
    let insuranceCompanyId: Int?
    let companyName: String?
    let type: String?
    let typeLabel: String?
    let policyNo: String?
    /// "yyyy-MM-dd" — yalnız gün; ISO tarih çözücüsüne VERİLMEZ (saatsiz metin onu kırar).
    let validUntil: String?

    enum CodingKeys: String, CodingKey {
        case id, type
        case patientId = "patient_id"
        case patientName = "patient_name"
        case insuranceCompanyId = "insurance_company_id"
        case companyName = "company_name"
        case typeLabel = "type_label"
        case policyNo = "policy_no"
        case validUntil = "valid_until"
    }
}

struct DVBHastaSigortaListesi: Decodable {
    let data: [DVBHastaSigorta]
    let profiles: [Profil]
    let companies: [Firma]

    struct Profil: Decodable, Identifiable {
        let id: Int
        let name: String?
        let relationshipLabel: String?
        let isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name
            case relationshipLabel = "relationship_label"
            case isSelf = "is_self"
        }
    }

    struct Firma: Decodable, Identifiable {
        let id: Int
        let name: String
        let types: [Tip]
    }

    struct Tip: Decodable, Hashable {
        let value: String
        let label: String
    }
}

private struct DVBHastaSigortaCevabi: Decodable {
    let insurance: DVBHastaSigorta
    let message: String?
}

/// Web /hesabim/odemeler "Ödeme Bekleyen Randevular" satırı.
struct DVBOdemeBekleyen: Decodable, Identifiable {
    let appointmentNo: String
    let doctorName: String?
    let startsAt: Date?
    let price: Double?
    let canPay: Bool?
    let payUrl: String?
    var id: String { appointmentNo }

    enum CodingKeys: String, CodingKey {
        case price
        case appointmentNo = "appointment_no"
        case doctorName = "doctor_name"
        case startsAt = "starts_at"
        case canPay = "can_pay"
        case payUrl = "pay_url"
    }
}

/// Sunucunun gün metni ("yyyy-MM-dd") ↔ tarih seçici. Cihaz saat diliminde: seçilen gün kaymasın.
private enum DVBSigortaGunu {
    static let sunucu: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func tarih(_ metin: String?) -> Date? {
        guard let metin, !metin.isEmpty else { return nil }
        return sunucu.date(from: metin)
    }

    static func metin(_ tarih: Date) -> String { sunucu.string(from: tarih) }

    /// "31.12.2027" (web ile aynı).
    static func goster(_ metin: String?) -> String? {
        guard let d = tarih(metin) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = .current
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }
}

// MARK: - Puanlarım

struct DVBPuanlarimView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var bilgi: DVBPuanBilgisi?
    @State private var hata: String?
    @State private var kopyalandi = false
    @State private var paylasimAcik = false

    var body: some View {
        Group {
            if let b = bilgi {
                icerik(b)
            } else if let hata {
                DVBStateView(icon: "wifi.exclamationmark", title: "Puanlarınız alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Puanlarım")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    private func icerik(_ b: DVBPuanBilgisi) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toplam puanınız").font(.subheadline).foregroundColor(.secondary)
                    Text(Self.sayi(b.points))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(DVBTheme.brand)
                    Text("\(b.invited ?? 0) kişi davet ettiniz").font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }

            if let kod = b.code {
                Section {
                    HStack {
                        Text("Davet kodunuz")
                        Spacer()
                        Text(kod).font(.title3.weight(.bold).monospaced()).textSelection(.enabled)
                    }
                    if let link = b.link {
                        Button {
                            UIPasteboard.general.string = link
                            kopyalandi = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { kopyalandi = false }
                        } label: {
                            Label(kopyalandi ? "Kopyalandı" : "Davet bağlantısını kopyala",
                                  systemImage: kopyalandi ? "checkmark" : "doc.on.doc")
                        }
                        Button {
                            paylasimAcik = true
                        } label: {
                            Label("Davet bağlantısını paylaş", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Davet")
                } footer: {
                    Text("Davet ettiğiniz kişi üye olunca \(b.referralPoints ?? 100) puan kazanırsınız.")
                }
            }

            Section {
                if b.history.isEmpty {
                    Text("Henüz puan hareketiniz yok.").foregroundColor(.secondary)
                }
                ForEach(b.history) { h in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.reason ?? "—")
                            if let t = h.createdAt { Text(t.dvbLong).font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        Text((h.points >= 0 ? "+" : "") + Self.sayi(h.points))
                            .font(.headline)
                            .foregroundColor(h.points >= 0 ? DVBTheme.brand : .red)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Puan geçmişi")
            }
        }
        .refreshable { await yukle() }
        .sheet(isPresented: $paylasimAcik) {
            DVBPaylasSayfasi(ogeler: [paylasimMetni(b)])
        }
    }

    private func paylasimMetni(_ b: DVBPuanBilgisi) -> String {
        var metin = "Doktorum Ve Ben'e davetlisin."
        if let kod = b.code { metin += " Davet kodum: \(kod)" }
        if let link = b.link { metin += "\n\(link)" }
        return metin
    }

    /// Puan (para DEĞİL): binlik ayraçlı tam sayı — web Para::sayi ile aynı görünüm (10.000).
    private static func sayi(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            bilgi = try await DVBAPI.shared.get("my/loyalty", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Sigortalarım

struct DVBSigortalarimView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var liste: DVBHastaSigortaListesi?
    @State private var hata: String?
    @State private var islemHatasi: String?
    @State private var form: SigortaFormu?
    @State private var silinecek: DVBHastaSigorta?

    /// nil = kapalı; `.yeni` = ekle; `.duzenle(s)` = poliçe no / geçerlilik düzenle.
    enum SigortaFormu: Identifiable {
        case yeni
        case duzenle(DVBHastaSigorta)

        var id: String {
            switch self {
            case .yeni: return "yeni"
            case .duzenle(let s): return "s\(s.id)"
            }
        }
    }

    var body: some View {
        List {
            if let hata, liste == nil {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) { Task { await yukle() } }
            } else if let l = liste, l.data.isEmpty {
                DVBStateView(
                    icon: "cross.case",
                    title: "Sigorta bilginiz yok",
                    message: l.companies.isEmpty
                        ? "Şu an tanımlı sigorta firması yok."
                        : "Hangi sağlık sigortası firmasıyla, hangi tip (özel / tamamlayıcı) anlaşmanız olduğunu sağ üstteki + ile ekleyin. Kendiniz ve yakınlarınız için ayrı ekleyebilirsiniz."
                )
            } else if liste == nil {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let l = liste, !l.data.isEmpty {
                Section {
                    ForEach(l.data) { s in
                        Button {
                            form = .duzenle(s)
                        } label: {
                            satir(s)
                        }
                        .foregroundColor(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                silinecek = s
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Kayıtlı sigortalarım")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Düzenlemek için dokunun, silmek için sola kaydırın.")
                        if let islemHatasi { Text(islemHatasi).foregroundColor(.red) }
                    }
                }
            }
        }
        .navigationTitle("Sigortalarım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    form = .yeni
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Sigorta ekle")
                .disabled(liste == nil || liste?.companies.isEmpty == true)
            }
        }
        .sheet(item: $form) { f in
            if let l = liste {
                DVBSigortaFormView(form: f, secenekler: l, kaydedildi: { Task { await yukle() } })
                    .environmentObject(session)
            }
        }
        .alert("Bu sigorta kaydı silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } })) {
            Button("Vazgeç", role: .cancel) {}
            Button("Sil", role: .destructive) {
                if let s = silinecek { Task { await sil(s) } }
            }
        } message: {
            Text("\(silinecek?.companyName ?? "Sigorta") · \(silinecek?.patientName ?? "")")
        }
        .refreshable { await yukle() }
        .task { await yukle() }
    }

    private func satir(_ s: DVBHastaSigorta) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.companyName ?? "Sigorta").font(.headline)
            Text(s.typeLabel ?? "").font(.subheadline).foregroundColor(DVBTheme.brand)
            HStack(spacing: 6) {
                if let ad = s.patientName { Text(ad) }
                if let p = s.policyNo, !p.isEmpty { Text("· Poliçe: \(p)") }
                if let g = DVBSigortaGunu.goster(s.validUntil) { Text("· \(g)") }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            liste = try await DVBAPI.shared.get("my/insurances", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func sil(_ s: DVBHastaSigorta) async {
        guard let token = session.token else { return }
        islemHatasi = nil
        do {
            let _: DVBMessage = try await DVBAPI.shared.delete("my/insurances/\(s.id)", token: token)
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { islemHatasi = m }
        }
    }
}

/// Sigorta ekle / düzenle. Düzenlemede profil, firma ve tip DEĞİŞMEZ (o başka kayıttır: sil + yeniden ekle).
struct DVBSigortaFormView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    let form: DVBSigortalarimView.SigortaFormu
    let secenekler: DVBHastaSigortaListesi
    let kaydedildi: () -> Void

    @State private var hastaId = 0
    @State private var firmaId: Int?
    @State private var tip = ""
    @State private var policeNo = ""
    @State private var tarihVar = false
    @State private var gecerlilik = Date()
    @State private var calisiyor = false
    @State private var hata: String?
    /// Aranabilir firma listesinden dönüşte `onAppear` yeniden çalışır; alanlar bir kez doldurulur.
    @State private var dolduruldu = false

    private var duzenlenen: DVBHastaSigorta? {
        if case .duzenle(let s) = form { return s }
        return nil
    }

    private var seciliFirma: DVBHastaSigortaListesi.Firma? {
        secenekler.companies.first { $0.id == firmaId }
    }

    private var gecerli: Bool {
        duzenlenen != nil || (hastaId != 0 && firmaId != nil && !tip.isEmpty)
    }

    var body: some View {
        NavigationView {
            Form {
                if let s = duzenlenen {
                    Section {
                        bilgiSatiri("Kim için?", s.patientName)
                        bilgiSatiri("Sigorta firması", s.companyName)
                        bilgiSatiri("Sigorta tipi", s.typeLabel)
                    } footer: {
                        Text("Firma ya da tip değişecekse bu kaydı silip yenisini ekleyin.")
                    }
                } else {
                    Section {
                        Picker("Kim için?", selection: $hastaId) {
                            Text("Seçin").tag(0)
                            ForEach(secenekler.profiles) { p in
                                Text(profilAdi(p)).tag(p.id)
                            }
                        }
                        DVBAramaliSecici(
                            baslik: "Sigorta firması",
                            secenekler: secenekler.companies.map { DVBSecenek(id: $0.id, ad: $0.name) },
                            secili: $firmaId
                        )
                        Picker("Sigorta tipi", selection: $tip) {
                            Text(firmaId == nil ? "Önce firma seçin" : "Seçin").tag("")
                            ForEach(seciliFirma?.types ?? [], id: \.value) { t in
                                Text(t.label).tag(t.value)
                            }
                        }
                        .disabled(firmaId == nil)
                    } footer: {
                        Text("Kendiniz ve yakınlarınız için ayrı ayrı ekleyebilirsiniz. Aynı kişi, firma ve tip yeniden eklenirse mevcut kayıt güncellenir.")
                    }
                }

                Section {
                    TextField("Poliçe no (isteğe bağlı)", text: $policeNo)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                    Toggle("Geçerlilik tarihi", isOn: $tarihVar)
                    if tarihVar {
                        DatePicker("Geçerlilik", selection: $gecerlilik, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                    }
                } footer: {
                    if let hata { Text(hata).foregroundColor(.red) }
                }
            }
            .navigationTitle(duzenlenen == nil ? "Sigorta ekle" : "Sigortayı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(calisiyor ? "Kaydediliyor…" : "Kaydet") { Task { await kaydet() } }
                        .disabled(calisiyor || !gecerli)
                }
            }
            .onAppear(perform: doldur)
            .onChange(of: firmaId) { _ in
                // Firma değişince tip o firmanın sunduklarından olmalı (web formundaki gibi); tek tip varsa o seçilir.
                let tipler = seciliFirma?.types ?? []
                if !tipler.contains(where: { $0.value == tip }) {
                    tip = tipler.count == 1 ? tipler[0].value : ""
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func bilgiSatiri(_ baslik: String, _ deger: String?) -> some View {
        HStack {
            Text(baslik)
            Spacer()
            Text(deger ?? "—").foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func profilAdi(_ p: DVBHastaSigortaListesi.Profil) -> String {
        let ad = p.name ?? "—"
        guard let y = p.relationshipLabel, !y.isEmpty else { return ad }
        return "\(ad) (\(y))"
    }

    private func doldur() {
        guard !dolduruldu else { return }
        dolduruldu = true
        if let s = duzenlenen {
            policeNo = s.policyNo ?? ""
            if let d = DVBSigortaGunu.tarih(s.validUntil) {
                tarihVar = true
                gecerlilik = d
            }
        } else {
            // Varsayılan: kişinin kendi profili (web'deki açılır listenin ilk satırı).
            hastaId = secenekler.profiles.first(where: { $0.isSelf == true })?.id ?? secenekler.profiles.first?.id ?? 0
        }
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        hata = nil
        defer { calisiyor = false }

        let police = policeNo.trimmingCharacters(in: .whitespaces)
        var govde: [String: Any] = [
            "policy_no": police.isEmpty ? NSNull() as Any : police as Any,
            "valid_until": tarihVar ? DVBSigortaGunu.metin(gecerlilik) as Any : NSNull() as Any,
        ]
        do {
            if let s = duzenlenen {
                let _: DVBHastaSigortaCevabi = try await DVBAPI.shared.put("my/insurances/\(s.id)", body: govde, token: token)
            } else {
                govde["patient_id"] = hastaId
                govde["insurance_company_id"] = firmaId ?? 0
                govde["type"] = tip
                let _: DVBHastaSigortaCevabi = try await DVBAPI.shared.post("my/insurances", body: govde, token: token)
            }
            kaydedildi()
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Verilerimi indir (KVKK)

/// Web "Hesabım › Profil › Verilerimi indir" ile AYNI dosya (doktorumveben-verilerim.json). Dosya geçici klasöre
/// yazılır, önizlemede açılır; sağ üstteki paylaş menüsünden Dosyalar'a kaydedilir ya da gönderilir.
struct DVBVeriIndirView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var calisiyor = false
    @State private var hata: String?
    @State private var onizlenen: DVBYerelDosya?

    var body: some View {
        Form {
            Section {
                Text("Hesabınızdaki kişisel verilerin makine tarafından okunabilir (JSON) bir kopyasını indirebilirsiniz: üyelik bilgileriniz, hasta profilleriniz, randevularınız, ödemeleriniz ve değerlendirmeleriniz.")
                    .font(.subheadline)
            } header: {
                Text("Kişisel verileriniz")
            } footer: {
                Text("Dosyada kişisel ve sağlık verileriniz bulunur; kimlerle paylaştığınıza dikkat edin.")
            }

            Section {
                Button {
                    Task { await indir() }
                } label: {
                    HStack {
                        if calisiyor { ProgressView().padding(.trailing, 6) }
                        Label("Verilerimi indir", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(calisiyor)
            } footer: {
                if let hata { Text(hata).foregroundColor(.red) }
            }
        }
        .navigationTitle("Verilerimi indir")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $onizlenen) { d in
            DVBBelgeOnizleme(dosya: d.url, kapat: { onizlenen = nil })
        }
    }

    private func indir() async {
        guard let token = session.token else { return }
        calisiyor = true
        hata = nil
        defer { calisiyor = false }
        do {
            let veri = try await DVBAPI.shared.veri("my/export", token: token)
            // Yanıt gerçekten JSON mu? (Yönlendirilen bir giriş sayfası dosya diye kaydedilmesin.)
            guard (try? JSONSerialization.jsonObject(with: veri)) is [String: Any] else { throw DVBError.decoding }
            let yol = FileManager.default.temporaryDirectory.appendingPathComponent("doktorumveben-verilerim.json")
            try veri.write(to: yol, options: [.atomic, .completeFileProtection])
            onizlenen = DVBYerelDosya(url: yol)
        } catch DVBError.server(let kod, _) where kod == 429 {
            hata = "Kısa sürede çok sayıda indirme yapıldı. Lütfen bir saat sonra tekrar deneyin."
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Ödeme bekleyen randevular (Ödemelerim ekranının üst bölümü)

/// Web /hesabim/odemeler "Ödeme Bekleyen Randevular" kutusu. "Öde" SİSTEM TARAYICISINDA açılır (DVB-000271);
/// ödenebilirlik kararı sunucuda (`can_pay`, DVB-000162: ön ödeme yok).
struct DVBOdemeBekleyenlerBolumu: View {
    let bekleyenler: [DVBOdemeBekleyen]

    @ViewBuilder var body: some View {
        if !bekleyenler.isEmpty {
            Section {
                ForEach(bekleyenler) { b in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.doctorName ?? "—").font(.headline)
                            if let t = b.startsAt { Text(t.dvbLong).font(.caption).foregroundColor(.secondary) }
                            Text(DVBPara.bicim(b.price)).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        if b.canPay == true, let raw = b.payUrl, let url = URL(string: raw) {
                            Button("Öde") { DVBOdemeAdresi.tarayicidaAc(url) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityHint("Ödeme sayfası tarayıcıda açılır")
                        } else {
                            Text("Randevudan sonra").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Ödeme bekleyen randevular")
            } footer: {
                Text("Dilerseniz hekiminize doğrudan (nakit veya kartla) da ödeyebilirsiniz. Ödeme sayfası tarayıcıda açılır.")
            }
        }
    }
}
