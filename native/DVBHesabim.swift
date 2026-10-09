import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000266 — HESABIM, 1. ADIM: profil + şifre, yakınlarım, favorilerim, yorumlarım, ödemelerim.
//
// Kullanıcı (30 Eyl 2026): "hesabım kısmında da sitede üyenin profilinde olan herşey olmalı". Bu bölümler ya hiç
// yoktu ya da ("Profil bilgilerim") sitenin sayfasını bir web penceresinde açıyordu — uygulamanın oturumu o
// pencereye taşınmadığı için kişi giriş sayfası görüyordu. Sunucu kuralları web ile AYNI servislerden geçer
// (HesabimApiController); burada yalnız ekran var.
//
// ⚠ `Section("Başlık") { } footer: { }` diye bir kurucu YOK (build 18 bununla düştü) — başlık+altbilgi gerekince
// `Section { } header: { } footer: { }`.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBProfil: Decodable {
    let name: String?
    let email: String?
    let phone: String?
    let emailVerified: Bool?
    let phoneVerified: Bool?
    let hasPassword: Bool?

    enum CodingKeys: String, CodingKey {
        case name, email, phone
        case emailVerified = "email_verified"
        case phoneVerified = "phone_verified"
        case hasPassword = "has_password"
    }
}

private struct DVBProfilCevabi: Decodable {
    let profile: DVBProfil
    let message: String?
}

struct DVBYakin: Decodable, Identifiable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let relationship: String?
    let phone: String?
    let email: String?
    /// "yyyy-MM-dd" — yalnız gün; ISO tarih çözücüsüne VERİLMEZ (saatsiz metin onu kırar).
    let birthDate: String?
    let gender: String?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case id, relationship, phone, email, gender
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case isSelf = "is_self"
    }

    var adSoyad: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ") }

    static let yakinlikEtiketi: [String: String] = [
        "self": "Kendim", "spouse": "Eşim", "child": "Çocuğum", "parent": "Annem / Babam", "other": "Diğer",
    ]
}

private struct DVBFavori: Decodable, Identifiable {
    let id: Int
    let slug: String
    let name: String?
    let specialty: String?
    let avatar: String?
    let rating: Double?
}

private struct DVBYorumlar: Decodable {
    let reviews: [Yorum]
    let reviewable: [Degerlendirilecek]

    struct Yorum: Decodable, Identifiable {
        let id: Int
        let doctorName: String?
        let rating: Int?
        let comment: String?
        let status: String?
        let doctorReply: String?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, rating, comment, status
            case doctorName = "doctor_name"
            case doctorReply = "doctor_reply"
            case createdAt = "created_at"
        }
    }

    struct Degerlendirilecek: Decodable, Identifiable {
        let appointmentId: Int
        let doctorName: String?
        let specialty: String?
        let patientName: String?
        let startsAt: Date?
        var id: Int { appointmentId }

        enum CodingKeys: String, CodingKey {
            case specialty
            case appointmentId = "appointment_id"
            case doctorName = "doctor_name"
            case patientName = "patient_name"
            case startsAt = "starts_at"
        }
    }
}

private struct DVBOdeme: Decodable, Identifiable {
    let paymentNo: String?
    let amount: Double?
    let status: String?
    let paidAt: Date?
    let doctorName: String?
    let appointmentAt: Date?
    let createdAt: Date?
    var id: String { paymentNo ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case amount, status
        case paymentNo = "payment_no"
        case paidAt = "paid_at"
        case doctorName = "doctor_name"
        case appointmentAt = "appointment_at"
        case createdAt = "created_at"
    }
}

/// ⛔ Para biçimi her üründe aynı: 1.500,00 ₺ (İksero standardı §5.1).
enum DVBPara {
    static func bicim(_ tutar: Double?) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: tutar ?? 0)) ?? "0,00") + " ₺"
    }
}

// MARK: - Profil + şifre

struct DVBProfilView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var profil: DVBProfil?
    @State private var ad = ""
    @State private var eposta = ""
    @State private var telefon = ""
    @State private var mevcutSifre = ""
    @State private var yeniSifre = ""
    @State private var yeniSifreTekrar = ""
    @State private var mesaj: String?
    @State private var hata: String?
    @State private var sifreMesaj: String?
    @State private var sifreHata: String?
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section {
                TextField("Ad Soyad", text: $ad).textContentType(.name)
                TextField("E-posta", text: $eposta)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Cep telefonu", text: $telefon)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            } header: {
                Text("Kişisel bilgiler")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let p = profil {
                        Text(p.phoneVerified == true ? "Telefonunuz doğrulandı." : "Telefonunuz henüz doğrulanmadı.")
                        if p.email != nil {
                            Text(p.emailVerified == true ? "E-postanız doğrulandı." : "E-postanız henüz doğrulanmadı.")
                        }
                    }
                    Text("Telefon ya da e-posta değişirse yeniden doğrulanır.")
                    if let mesaj { Text(mesaj).foregroundColor(DVBTheme.accent) }
                    if let hata { Text(hata).foregroundColor(.red) }
                }
            }

            Section {
                Button(calisiyor ? "Kaydediliyor…" : "Bilgilerimi kaydet") { Task { await kaydet() } }
                    .disabled(calisiyor || ad.trimmingCharacters(in: .whitespaces).count < 2)
            }

            Section {
                if profil?.hasPassword == true {
                    SecureField("Mevcut şifre", text: $mevcutSifre).textContentType(.password)
                }
                SecureField("Yeni şifre", text: $yeniSifre).textContentType(.newPassword)
                SecureField("Yeni şifre (tekrar)", text: $yeniSifreTekrar).textContentType(.newPassword)
                Button(profil?.hasPassword == true ? "Şifremi değiştir" : "Şifre belirle") { Task { await sifreKaydet() } }
                    .disabled(calisiyor || yeniSifre.isEmpty || yeniSifre != yeniSifreTekrar)
            } header: {
                Text(profil?.hasPassword == true ? "Şifre" : "Şifre belirle")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    // Hesap talep formundan ya da WhatsApp'tan açıldıysa şifresizdir; mevcut şifre sorulmaz.
                    Text("En az 10 karakter; büyük harf, küçük harf ve rakam/sembol içermeli. Adınızı ya da e-postanızı içeremez.")
                    if let sifreMesaj { Text(sifreMesaj).foregroundColor(DVBTheme.accent) }
                    if let sifreHata { Text(sifreHata).foregroundColor(.red) }
                }
            }
        }
        .navigationTitle("Profil bilgilerim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBProfilCevabi = try await DVBAPI.shared.get("my/profile", token: token)
            doldur(c.profile)
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func doldur(_ p: DVBProfil) {
        profil = p
        ad = p.name ?? ""
        eposta = p.email ?? ""
        telefon = p.phone ?? ""
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true; hata = nil; mesaj = nil
        defer { calisiyor = false }
        var govde: [String: Any] = ["name": ad.trimmingCharacters(in: .whitespaces), "phone": telefon]
        let e = eposta.trimmingCharacters(in: .whitespaces)
        if !e.isEmpty { govde["email"] = e }
        do {
            let c: DVBProfilCevabi = try await DVBAPI.shared.put("my/profile", body: govde, token: token)
            doldur(c.profile)
            mesaj = c.message ?? "Kaydedildi."
            await session.restore()   // başlıktaki ad/e-posta güncellensin
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func sifreKaydet() async {
        guard let token = session.token else { return }
        calisiyor = true; sifreHata = nil; sifreMesaj = nil
        defer { calisiyor = false }
        var govde: [String: Any] = ["password": yeniSifre, "password_confirmation": yeniSifreTekrar]
        if profil?.hasPassword == true { govde["current_password"] = mevcutSifre }
        do {
            let c: DVBMessage = try await DVBAPI.shared.post("my/password", body: govde, token: token)
            sifreMesaj = c.message ?? "Şifreniz kaydedildi."
            mevcutSifre = ""; yeniSifre = ""; yeniSifreTekrar = ""
            await yukle()   // "Şifre belirle" → "Şifremi değiştir"
        } catch {
            if let m = DVBError.mesaj(error) { sifreHata = m }
        }
    }
}

// MARK: - Yakınlarım

struct DVBYakinlarView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var yakinlar: [DVBYakin] = []
    @State private var yukleniyor = false
    @State private var hata: String?
    /// nil = kapalı; `.yeni` = ekle; `.duzenle(y)` = düzenle.
    @State private var form: YakinFormu?

    enum YakinFormu: Identifiable {
        case yeni
        case duzenle(DVBYakin)
        var id: String {
            switch self {
            case .yeni: return "yeni"
            case .duzenle(let y): return "y\(y.id)"
            }
        }
    }

    var body: some View {
        List {
            if yukleniyor && yakinlar.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let hata, yakinlar.isEmpty {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) { Task { await yukle() } }
            }
            Section {
                ForEach(yakinlar) { y in
                    Button {
                        form = .duzenle(y)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(y.adSoyad.isEmpty ? "—" : y.adSoyad).foregroundColor(.primary)
                            Text(DVBYakin.yakinlikEtiketi[y.relationship ?? ""] ?? "—")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .deleteDisabled(y.isSelf == true)
                }
                .onDelete { sirasi in Task { await sil(sirasi) } }
            } footer: {
                Text("Yakınlarınız için de randevu alabilirsiniz. Kendi profiliniz silinemez.")
            }
        }
        .navigationTitle("Yakınlarım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { form = .yeni } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Yakın ekle")
            }
        }
        .sheet(item: $form, onDismiss: { Task { await yukle() } }) { f in
            switch f {
            case .yeni: DVBYakinFormView(yakin: nil).environmentObject(session)
            case .duzenle(let y): DVBYakinFormView(yakin: y).environmentObject(session)
            }
        }
        .task { await yukle() }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let l: DVBList<DVBYakin> = try await DVBAPI.shared.get("my/dependents", token: token)
            yakinlar = l.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func sil(_ sirasi: IndexSet) async {
        guard let token = session.token else { return }
        for i in sirasi {
            let y = yakinlar[i]
            guard y.isSelf != true else { continue }
            let _: DVBMessage? = try? await DVBAPI.shared.delete("my/dependents/\(y.id)", token: token)
        }
        await yukle()
    }
}

struct DVBYakinFormView: View {
    let yakin: DVBYakin?

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var ad = ""
    @State private var soyad = ""
    @State private var yakinlik = "child"
    @State private var cinsiyet = ""
    @State private var dogumVar = false
    @State private var dogum = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
    @State private var hata: String?
    @State private var calisiyor = false

    private var kendisi: Bool { yakin?.isSelf == true }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Ad", text: $ad)
                    TextField("Soyad", text: $soyad)
                    if !kendisi {
                        Picker("Yakınlık", selection: $yakinlik) {
                            ForEach(["spouse", "child", "parent", "other"], id: \.self) {
                                Text(DVBYakin.yakinlikEtiketi[$0] ?? $0).tag($0)
                            }
                        }
                    }
                    Picker("Cinsiyet", selection: $cinsiyet) {
                        Text("Belirtilmedi").tag("")
                        Text("Kadın").tag("female")
                        Text("Erkek").tag("male")
                    }
                    Toggle("Doğum tarihi", isOn: $dogumVar.animation())
                    if dogumVar {
                        DatePicker("Doğum tarihi", selection: $dogum, in: ...Date(), displayedComponents: .date)
                    }
                } footer: {
                    if let hata { Text(hata).foregroundColor(.red) }
                }
            }
            .navigationTitle(yakin == nil ? "Yakın ekle" : "Bilgileri düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await kaydet() } }
                        .disabled(calisiyor || ad.trimmingCharacters(in: .whitespaces).isEmpty || soyad.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: doldur)
        }
        .navigationViewStyle(.stack)
    }

    private func doldur() {
        guard let y = yakin else { return }
        ad = y.firstName ?? ""
        soyad = y.lastName ?? ""
        yakinlik = y.relationship ?? "other"
        cinsiyet = y.gender ?? ""
        if let d = y.birthDate, let t = Self.gunBicimi.date(from: d) { dogum = t; dogumVar = true }
    }

    private static let gunBicimi: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true; hata = nil
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "first_name": ad.trimmingCharacters(in: .whitespaces),
            "last_name": soyad.trimmingCharacters(in: .whitespaces),
            // Kendi profilde yakınlık değişmez; sunucu listesinde 'self' yok → kayıttaki değer korunur.
            "relationship": kendisi ? "other" : yakinlik,
        ]
        if !cinsiyet.isEmpty { govde["gender"] = cinsiyet }
        if dogumVar { govde["birth_date"] = Self.gunBicimi.string(from: dogum) }
        do {
            if let y = yakin {
                let _: DVBMessage = try await DVBAPI.shared.put("my/dependents/\(y.id)", body: govde, token: token)
            } else {
                let _: DVBMessage = try await DVBAPI.shared.post("my/dependents", body: govde, token: token)
            }
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Favorilerim

struct DVBFavorilerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var favoriler: [DVBFavori] = []
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            if let hata, favoriler.isEmpty {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) { Task { await yukle() } }
            } else if yuklendi && favoriler.isEmpty {
                DVBStateView(icon: "heart", title: "Favori hekiminiz yok", message: "Hekim sayfasındaki kalp simgesiyle ekleyebilirsiniz.")
            }
            ForEach(favoriler) { f in
                NavigationLink(destination: DVBDoctorDetailView(doctor: DVBDoctor(
                    slug: f.slug, name: f.name, specialty: f.specialty, avatar: f.avatar, rating: f.rating,
                    ratingCount: nil, isVerified: nil, district: nil, experience: nil, distanceKm: nil
                ))) {
                    HStack(spacing: 12) {
                        DVBAvatar(url: f.avatar, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name ?? "—").font(.headline)
                            if let s = f.specialty { Text(s).font(.subheadline).foregroundColor(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Favorilerim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let l: DVBList<DVBFavori> = try await DVBAPI.shared.get("my/favorites", token: token)
            favoriler = l.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yuklendi = true
    }
}

// MARK: - Yorumlarım

struct DVBYorumlarView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBYorumlar?
    @State private var hata: String?
    @State private var degerlendir: DVBYorumlar.Degerlendirilecek?

    var body: some View {
        List {
            if let hata, veri == nil {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) { Task { await yukle() } }
            }
            if let bekleyen = veri?.reviewable, !bekleyen.isEmpty {
                Section {
                    ForEach(bekleyen) { r in
                        Button { degerlendir = r } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.doctorName ?? "—").foregroundColor(.primary)
                                    if let t = r.startsAt { Text(t.dvbLong).font(.caption).foregroundColor(.secondary) }
                                }
                                Spacer()
                                Text("Değerlendir").font(.subheadline.weight(.semibold)).foregroundColor(DVBTheme.brand)
                            }
                        }
                    }
                } header: {
                    Text("Değerlendirme bekleyen randevular")
                }
            }
            Section {
                if let yorumlar = veri?.reviews, !yorumlar.isEmpty {
                    ForEach(yorumlar) { y in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(y.doctorName ?? "—").font(.headline)
                                Spacer()
                                Text(String(repeating: "★", count: max(0, min(5, y.rating ?? 0))))
                                    .foregroundColor(.orange)
                            }
                            if let c = y.comment, !c.isEmpty { Text(c).font(.subheadline) }
                            Text(Self.durumEtiketi(y.status)).font(.caption).foregroundColor(.secondary)
                            if let cevap = y.doctorReply, !cevap.isEmpty {
                                Text("Hekimin yanıtı: \(cevap)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else if veri != nil {
                    Text("Henüz değerlendirmeniz yok.").foregroundColor(.secondary)
                }
            } header: {
                Text("Değerlendirmelerim")
            }
        }
        .navigationTitle("Yorumlarım")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $degerlendir, onDismiss: { Task { await yukle() } }) { r in
            DVBDegerlendirView(randevu: r).environmentObject(session)
        }
        .task { await yukle() }
    }

    static func durumEtiketi(_ s: String?) -> String {
        switch s {
        case "approved": return "Yayında"
        case "rejected": return "Yayınlanmadı"
        default: return "Onay bekliyor"
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/reviews", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBDegerlendirView: View {
    let randevu: DVBYorumlar.Degerlendirilecek

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var puan = 5
    @State private var yorum = ""
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(randevu.doctorName ?? "—").font(.headline)
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Button { puan = i } label: {
                                Image(systemName: i <= puan ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(i) yıldız")
                        }
                    }
                    TextField("Yorumunuz (isteğe bağlı)", text: $yorum)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Değerlendirmeniz ekibimiz onayladıktan sonra yayınlanır. Lütfen sağlık bilgilerinizi yazmayın.")
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle("Değerlendir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gönder") { Task { await gonder() } }.disabled(calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func gonder() async {
        guard let token = session.token else { return }
        calisiyor = true; hata = nil
        defer { calisiyor = false }
        var govde: [String: Any] = ["rating": puan]
        let y = yorum.trimmingCharacters(in: .whitespaces)
        if !y.isEmpty { govde["comment"] = y }
        do {
            let _: DVBMessage = try await DVBAPI.shared.post("my/appointments/\(randevu.appointmentId)/review", body: govde, token: token)
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Ödemelerim

struct DVBOdemelerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var odemeler: [DVBOdeme] = []
    /// DVB-000352 — web'deki "Ödeme Bekleyen Randevular" kutusu ("Öde" tarayıcıda açılır).
    @State private var bekleyenler: [DVBOdemeBekleyen] = []
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            DVBOdemeBekleyenlerBolumu(bekleyenler: bekleyenler)
            if let hata, odemeler.isEmpty {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) { Task { await yukle() } }
            } else if yuklendi && odemeler.isEmpty {
                DVBStateView(icon: "creditcard", title: "Ödemeniz yok")
            }
            ForEach(odemeler) { o in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(o.doctorName ?? "—").font(.headline)
                        if let t = o.paidAt ?? o.createdAt { Text(t.dvbLong).font(.caption).foregroundColor(.secondary) }
                        if let no = o.paymentNo { Text(no).font(.caption2.monospaced()).foregroundColor(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(DVBPara.bicim(o.amount)).font(.headline).monospacedDigit()
                        Text(Self.durumEtiketi(o.status)).font(.caption).foregroundColor(o.status == "paid" ? DVBTheme.accent : .secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Ödemelerim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    static func durumEtiketi(_ s: String?) -> String {
        switch s {
        case "paid": return "Ödendi"
        case "refunded": return "İade edildi"
        case "failed": return "Başarısız"
        default: return "Bekliyor"
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let l: DVBList<DVBOdeme> = try await DVBAPI.shared.get("my/payments", token: token)
            odemeler = l.data
            hata = nil
            // DVB-000352 — bekleyenler ayrı uç; alınamazsa geçmiş listesi yine gösterilir.
            if let b: DVBList<DVBOdemeBekleyen> = try? await DVBAPI.shared.get("my/payments/pending", token: token) {
                bekleyenler = b.data
            }
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yuklendi = true
    }
}
