import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000345 — FİNANS BÖLÜMLERİ: seans paketleri, sabit giderler, muhasebe tanımları, gelen faturalar, personel.
//
// Kullanıcı (9 Eki 2026): "eksik kalan ne varsa app de yap en son derle ve son sürüm olarak gönder".
//
// Kurallar sunucuda (HekimFinansEkApiController — web PackageController, RecurringExpenseController,
// FinanceCategory/CashAccountController, IncomingInvoiceController, StaffController ile aynı). Tutarlar 10.000,00 ₺;
// girişte `DVBPara.coz`, API'ye `DVBPara.makine`.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBFinSecenek: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String?
}

// MARK: - Seans paketleri

private struct DVBPaketVerisi: Decodable {
    let templates: [Tanim]
    let sold: [Satilan]
    let services: [DVBFinSecenek]
    let accounts: [DVBFinSecenek]

    struct Tanim: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let totalSessions: Int
        let price: Double
        let validityDays: Int?
        let serviceId: Int?
        let service: String?
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, price, service
            case totalSessions = "total_sessions"
            case validityDays = "validity_days"
            case serviceId = "service_id"
            case isActive = "is_active"
        }
    }

    struct Satilan: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let patient: String?
        let totalSessions: Int
        let usedSessions: Int
        let price: Double
        let purchasedOn: String?
        let expiresOn: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case id, name, patient, price, status
            case totalSessions = "total_sessions"
            case usedSessions = "used_sessions"
            case purchasedOn = "purchased_on"
            case expiresOn = "expires_on"
        }
    }
}

struct DVBPaketlerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBPaketVerisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var tanimAcik = false
    @State private var duzenlenen: DVBPaketVerisi.Tanim?
    @State private var satisAcik = false

    var body: some View {
        Group {
            if let v = veri {
                List {
                    Section {
                        if v.templates.isEmpty { Text("Henüz paket tanımı yok.").foregroundColor(.secondary) }
                        ForEach(v.templates) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.subheadline.weight(.semibold)).foregroundColor(t.isActive ? .primary : .secondary)
                                    Text(DVBPaketMetni.tanim(t)).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(t.isActive ? "Kapat" : "Aç") { Task { await tanimDurum(t.id) } }.buttonStyle(.borderless).font(.caption)
                                Button("Düzenle") { duzenlenen = t }.buttonStyle(.borderless).font(.caption)
                            }
                        }
                        Button { tanimAcik = true } label: { Label("Paket tanımı ekle", systemImage: "plus.circle") }
                    } header: {
                        Text("Paket tanımları")
                    }
                    Section {
                        Button { satisAcik = true } label: { Label("Hastaya paket sat", systemImage: "cart.badge.plus") }
                            .disabled(v.templates.filter(\.isActive).isEmpty)
                        ForEach(v.sold) { p in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(p.patient ?? "Hasta").font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(p.usedSessions)/\(p.totalSessions)").font(.subheadline.monospacedDigit())
                                }
                                Text(DVBPaketMetni.satis(p)).font(.caption).foregroundColor(.secondary)
                                if p.status != "cancelled" && p.usedSessions < p.totalSessions {
                                    HStack(spacing: 16) {
                                        Button("Seans düş") { Task { await islem(p.id, "consume") } }
                                        Button("İptal et", role: .destructive) { Task { await islem(p.id, "cancel") } }
                                    }
                                    .buttonStyle(.borderless).font(.caption.weight(.semibold))
                                }
                            }
                        }
                    } header: {
                        Text("Satılan paketler")
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "square.stack.3d.up", title: "Paketler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Seans paketleri")
        .navigationBarTitleDisplayMode(.inline)
        .task { if veri == nil { await yukle() } }
        .alert("Paketler", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .sheet(isPresented: $tanimAcik) {
            DVBPaketTanimFormView(tanim: nil, hizmetler: veri?.services ?? []) { m in bilgi = m; Task { await yukle() } }.environmentObject(session)
        }
        .sheet(item: $duzenlenen) { t in
            DVBPaketTanimFormView(tanim: t, hizmetler: veri?.services ?? []) { m in bilgi = m; Task { await yukle() } }.environmentObject(session)
        }
        .sheet(isPresented: $satisAcik) {
            DVBPaketSatisView(tanimlar: (veri?.templates ?? []).filter(\.isActive), hesaplar: veri?.accounts ?? []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/packages", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func tanimDurum(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/packages/templates/\(id)/toggle", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func islem(_ id: Int, _ ad: String) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/packages/\(id)/\(ad)", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

private enum DVBPaketMetni {
    static func tanim(_ t: DVBPaketVerisi.Tanim) -> String {
        var s = "\(t.totalSessions) seans · " + DVBPara.bicim(t.price)
        if let g = t.validityDays { s += " · \(g) gün geçerli" }
        return s
    }

    static func satis(_ p: DVBPaketVerisi.Satilan) -> String {
        var parca: [String] = [p.name]
        if p.status == "cancelled" { parca.append("İptal") }
        if let e = p.expiresOn { parca.append("son gün " + DVBGunMetni.yaz(e, "d MMM yyyy")) }
        return parca.joined(separator: " · ")
    }
}

private struct DVBPaketTanimFormView: View {
    let tanim: DVBPaketVerisi.Tanim?
    let hizmetler: [DVBFinSecenek]
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var ad: String
    @State private var seans: Int
    @State private var fiyat: String
    @State private var gecerlilik: String
    @State private var hizmetId: Int?
    @State private var hata: String?
    @State private var calisiyor = false

    init(tanim: DVBPaketVerisi.Tanim?, hizmetler: [DVBFinSecenek], kaydedildi: @escaping (String) -> Void) {
        self.tanim = tanim
        self.hizmetler = hizmetler
        self.kaydedildi = kaydedildi
        _ad = State(initialValue: tanim?.name ?? "")
        _seans = State(initialValue: tanim?.totalSessions ?? 10)
        _fiyat = State(initialValue: tanim.map { String(format: "%.2f", $0.price).replacingOccurrences(of: ".", with: ",") } ?? "")
        _gecerlilik = State(initialValue: tanim?.validityDays.map(String.init) ?? "")
        _hizmetId = State(initialValue: tanim?.serviceId)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Paket adı (ör. 10 seans fizik tedavi)", text: $ad)
                Stepper("Seans: \(seans)", value: $seans, in: 1...1000)
                TextField("Fiyat (ör. 5.000,00)", text: $fiyat).keyboardType(.decimalPad)
                TextField("Geçerlilik (gün, isteğe bağlı)", text: $gecerlilik).keyboardType(.numberPad)
                Picker("Hizmet", selection: $hizmetId) {
                    Text("Seçilmedi").tag(Int?.none)
                    ForEach(hizmetler) { h in Text(h.name).tag(Int?.some(h.id)) }
                }
                if let hata { Text(hata).foregroundColor(.red).font(.subheadline) }
            }
            .navigationTitle(tanim == nil ? "Paket tanımı" : "Paketi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await kaydet() } } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(calisiyor || DVBYonBicim.kirp(ad).isEmpty || DVBPara.coz(fiyat) == nil)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token, let f = DVBPara.coz(fiyat) else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["name": DVBYonBicim.kirp(ad), "total_sessions": seans, "price": DVBPara.makine(f)]
        if let g = Int(gecerlilik.trimmingCharacters(in: .whitespaces)) { govde["validity_days"] = g }
        if let hizmetId { govde["appointment_type_id"] = hizmetId }
        do {
            let c: DVBYonCevap
            if let tanim {
                c = try await DVBAPI.shared.put("my/doctor/packages/templates/\(tanim.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/packages/templates", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBPaketHastaSonuclari: Decodable {
    let data: [DVBHekimHastaOzet]
}

private struct DVBPaketSatisView: View {
    let tanimlar: [DVBPaketVerisi.Tanim]
    let hesaplar: [DVBFinSecenek]
    var satildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var arama = ""
    @State private var sonuclar: [DVBHekimHastaOzet] = []
    @State private var hasta: DVBHekimHastaOzet?
    @State private var tanimId: Int?
    @State private var odemeAlindi = true
    @State private var hesapId: Int?
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationView {
            Form {
                Section("Hasta") {
                    if let h = hasta {
                        HStack {
                            Text(h.name ?? "Hasta")
                            Spacer()
                            Button("Değiştir") { hasta = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        TextField("Ad, telefon ya da hasta no", text: $arama)
                        ForEach(sonuclar) { h in
                            Button { hasta = h } label: {
                                VStack(alignment: .leading) {
                                    Text(h.name ?? "Hasta").foregroundColor(.primary)
                                    if let n = h.patientNo { Text(n).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                        }
                    }
                }
                Section("Paket") {
                    Picker("Paket", selection: $tanimId) {
                        Text("Seçin").tag(Int?.none)
                        ForEach(tanimlar) { t in Text("\(t.name) · \(DVBPara.bicim(t.price))").tag(Int?.some(t.id)) }
                    }
                    Toggle("Ödeme alındı (kasaya gelir yaz)", isOn: $odemeAlindi)
                    if odemeAlindi {
                        Picker("Hesap", selection: $hesapId) {
                            ForEach(hesaplar) { h in Text(h.name).tag(Int?.some(h.id)) }
                        }
                    }
                }
                if let hata { Section { Text(hata).foregroundColor(.red).font(.subheadline) } }
            }
            .navigationTitle("Paket sat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await sat() } } label: {
                        if calisiyor { ProgressView() } else { Text("Sat").bold() }
                    }
                    .disabled(calisiyor || hasta == nil || tanimId == nil)
                }
            }
            .task(id: arama) { await ara() }
            .onAppear { if hesapId == nil { hesapId = hesaplar.first?.id } }
        }
        .navigationViewStyle(.stack)
    }

    private func ara() async {
        let q = DVBYonBicim.kirp(arama)
        guard q.count >= 2, let token = session.token else { sonuclar = []; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        if let c: DVBPaketHastaSonuclari = try? await DVBAPI.shared.get("my/doctor/patients", query: ["q": q], token: token) {
            sonuclar = Array(c.data.prefix(8))
        }
    }

    private func sat() async {
        guard let token = session.token, let hasta, let tanimId else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["patient_id": hasta.id, "package_template_id": tanimId, "record_payment": odemeAlindi]
        if odemeAlindi, let hesapId { govde["cash_account_id"] = hesapId }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/packages/sell", body: govde, token: token)
            satildi(c.message ?? "Paket satışı kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Sabit giderler

private struct DVBSabitGiderVerisi: Decodable {
    let data: [Gider]
    let categories: [DVBFinSecenek]
    let accounts: [DVBFinSecenek]

    struct Gider: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let amount: Double
        let period: String
        let intervalDay: Int
        let financeCategoryId: Int?
        let category: String?
        let cashAccountId: Int?
        let account: String?
        let startOn: String?
        let endOn: String?
        let nextRunOn: String?
        let autoPost: Bool
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, amount, period, category, account
            case intervalDay = "interval_day"
            case financeCategoryId = "finance_category_id"
            case cashAccountId = "cash_account_id"
            case startOn = "start_on"
            case endOn = "end_on"
            case nextRunOn = "next_run_on"
            case autoPost = "auto_post"
            case isActive = "is_active"
        }
    }
}

enum DVBPeriyot {
    static func ad(_ p: String) -> String {
        switch p {
        case "weekly": return "Haftalık"
        case "yearly": return "Yıllık"
        default: return "Aylık"
        }
    }
}

struct DVBSabitGiderlerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBSabitGiderVerisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniAcik = false
    @State private var duzenlenen: DVBSabitGiderVerisi.Gider?
    @State private var silinecek: DVBSabitGiderVerisi.Gider?

    var body: some View {
        Group {
            if let v = veri {
                List {
                    Section {
                        if v.data.isEmpty { Text("Henüz sabit gider yok.").foregroundColor(.secondary) }
                        ForEach(v.data) { g in
                            Button { duzenlenen = g } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(g.name).font(.subheadline.weight(.semibold)).foregroundColor(g.isActive ? .primary : .secondary)
                                        Spacer()
                                        Text(DVBPara.bicim(g.amount)).font(.subheadline.monospacedDigit()).foregroundColor(.primary)
                                    }
                                    Text([DVBPeriyot.ad(g.period), g.account, g.nextRunOn.map { "sıradaki " + DVBGunMetni.yaz($0, "d MMM") }, g.isActive ? nil : "durduruldu"]
                                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { silinecek = g } label: { Label("Sil", systemImage: "trash") }
                                Button { Task { await durum(g.id) } } label: { Label(g.isActive ? "Durdur" : "Aç", systemImage: "pause") }
                            }
                        }
                    } footer: {
                        Text("Otomatik işlenen giderler zamanı gelince kasaya kendiliğinden yazılır.")
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "arrow.triangle.2.circlepath", title: "Sabit giderler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sabit giderler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { yeniAcik = true } label: { Label("Ekle", systemImage: "plus") }.disabled(veri == nil)
            }
        }
        .task { if veri == nil { await yukle() } }
        .alert("Sabit giderler", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .confirmationDialog("Sabit gider silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let g = silinecek { Task { await sil(g.id) } }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        }
        .sheet(isPresented: $yeniAcik) {
            DVBSabitGiderFormView(gider: nil, kategoriler: veri?.categories ?? [], hesaplar: veri?.accounts ?? []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
        .sheet(item: $duzenlenen) { g in
            DVBSabitGiderFormView(gider: g, kategoriler: veri?.categories ?? [], hesaplar: veri?.accounts ?? []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/recurring-expenses", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func durum(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/recurring-expenses/\(id)/toggle", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func sil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.delete("my/doctor/recurring-expenses/\(id)", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

private struct DVBSabitGiderFormView: View {
    let gider: DVBSabitGiderVerisi.Gider?
    let kategoriler: [DVBFinSecenek]
    let hesaplar: [DVBFinSecenek]
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var ad: String
    @State private var tutar: String
    @State private var periyot: String
    @State private var gun: Int
    @State private var kategoriId: Int?
    @State private var hesapId: Int?
    @State private var baslangic: Date
    @State private var bitisVar: Bool
    @State private var bitis: Date
    @State private var otomatik: Bool
    @State private var hata: String?
    @State private var calisiyor = false

    init(gider: DVBSabitGiderVerisi.Gider?, kategoriler: [DVBFinSecenek], hesaplar: [DVBFinSecenek], kaydedildi: @escaping (String) -> Void) {
        self.gider = gider
        self.kategoriler = kategoriler
        self.hesaplar = hesaplar
        self.kaydedildi = kaydedildi
        _ad = State(initialValue: gider?.name ?? "")
        _tutar = State(initialValue: gider.map { String(format: "%.2f", $0.amount).replacingOccurrences(of: ".", with: ",") } ?? "")
        _periyot = State(initialValue: gider?.period ?? "monthly")
        _gun = State(initialValue: gider?.intervalDay ?? 1)
        _kategoriId = State(initialValue: gider?.financeCategoryId)
        _hesapId = State(initialValue: gider?.cashAccountId ?? hesaplar.first?.id)
        _baslangic = State(initialValue: DVBYonBicim.tarih(gider?.startOn) ?? Date())
        _bitisVar = State(initialValue: gider?.endOn != nil)
        _bitis = State(initialValue: DVBYonBicim.tarih(gider?.endOn) ?? Date().addingTimeInterval(365 * 86400))
        _otomatik = State(initialValue: gider?.autoPost ?? true)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Ad (ör. Kira)", text: $ad)
                    TextField("Tutar (ör. 20.000,00)", text: $tutar).keyboardType(.decimalPad)
                    Picker("Sıklık", selection: $periyot) {
                        Text("Haftalık").tag("weekly")
                        Text("Aylık").tag("monthly")
                        Text("Yıllık").tag("yearly")
                    }
                    if periyot == "monthly" { Stepper("Ayın \(gun). günü", value: $gun, in: 1...31) }
                    Picker("Kategori", selection: $kategoriId) {
                        Text("Kategorisiz").tag(Int?.none)
                        ForEach(kategoriler) { k in Text(k.name).tag(Int?.some(k.id)) }
                    }
                    Picker("Hesap", selection: $hesapId) {
                        ForEach(hesaplar) { h in Text(h.name).tag(Int?.some(h.id)) }
                    }
                }
                Section {
                    DatePicker("Başlangıç", selection: $baslangic, displayedComponents: .date).environment(\.timeZone, DVBTime.klinik)
                    Toggle("Bitiş tarihi var", isOn: $bitisVar)
                    if bitisVar { DatePicker("Bitiş", selection: $bitis, displayedComponents: .date).environment(\.timeZone, DVBTime.klinik) }
                    Toggle("Zamanı gelince kasaya otomatik yaz", isOn: $otomatik)
                }
                if let hata { Section { Text(hata).foregroundColor(.red).font(.subheadline) } }
            }
            .navigationTitle(gider == nil ? "Sabit gider ekle" : "Sabit gideri düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await kaydet() } } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(calisiyor || DVBYonBicim.kirp(ad).isEmpty || DVBPara.coz(tutar) == nil || hesapId == nil)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token, let t = DVBPara.coz(tutar), let hesapId else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "name": DVBYonBicim.kirp(ad), "amount": DVBPara.makine(t), "period": periyot, "interval_day": gun,
            "cash_account_id": hesapId, "start_on": DVBYonBicim.ymd(baslangic), "auto_post": otomatik,
        ]
        if let kategoriId { govde["finance_category_id"] = kategoriId }
        if bitisVar { govde["end_on"] = DVBYonBicim.ymd(bitis) }
        do {
            let c: DVBYonCevap
            if let gider {
                c = try await DVBAPI.shared.put("my/doctor/recurring-expenses/\(gider.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/recurring-expenses", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Muhasebe tanımları

private struct DVBTanimVerisi: Decodable {
    let incomeCategories: [Kategori]
    let expenseCategories: [Kategori]
    let accounts: [Hesap]

    struct Kategori: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name
            case isActive = "is_active"
        }
    }

    struct Hesap: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let type: String
        let openingBalance: Double
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, type
            case openingBalance = "opening_balance"
            case isActive = "is_active"
        }
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case incomeCategories = "income_categories"
        case expenseCategories = "expense_categories"
    }
}

struct DVBMuhasebeTanimlariView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBTanimVerisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniKategori: String?
    @State private var kategoriAdi = ""
    @State private var hesapAcik = false
    @State private var hesapAdi = ""
    @State private var hesapTuru = "bank"
    @State private var acilis = ""

    var body: some View {
        Group {
            if let v = veri {
                List {
                    kategoriBolumu("Gelir kategorileri", v.incomeCategories, "income")
                    kategoriBolumu("Gider kategorileri", v.expenseCategories, "expense")
                    Section {
                        ForEach(v.accounts) { h in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(h.name).foregroundColor(h.isActive ? .primary : .secondary)
                                    Text(DVBHesapTuru.ad(h.type) + " · açılış " + DVBPara.bicim(h.openingBalance)).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(h.isActive ? "Kapat" : "Aç") { Task { await durum("accounts", h.id) } }.buttonStyle(.borderless).font(.caption)
                            }
                        }
                        Button { hesapAcik = true } label: { Label("Hesap ekle", systemImage: "plus.circle") }
                    } header: {
                        Text("Kasa ve hesaplar")
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "list.bullet.indent", title: "Tanımlar alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Muhasebe tanımları")
        .navigationBarTitleDisplayMode(.inline)
        .task { if veri == nil { await yukle() } }
        .alert("Muhasebe tanımları", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        // ⚠ Uyarı penceresindeki metin alanı iOS 16 ister; iOS 15'te görünmez → küçük sayfa.
        .sheet(isPresented: Binding(get: { yeniKategori != nil }, set: { if !$0 { yeniKategori = nil } })) {
            NavigationView {
                Form {
                    TextField("Kategori adı", text: $kategoriAdi)
                }
                .navigationTitle(yeniKategori == "income" ? "Gelir kategorisi" : "Gider kategorisi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { yeniKategori = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle") {
                            let tur = yeniKategori ?? "expense"
                            yeniKategori = nil
                            Task { await kategoriEkle(tur) }
                        }
                        .disabled(DVBYonBicim.kirp(kategoriAdi).isEmpty)
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $hesapAcik) {
            NavigationView {
                Form {
                    TextField("Hesap adı (ör. Ziraat Bankası)", text: $hesapAdi)
                    Picker("Tür", selection: $hesapTuru) {
                        Text("Nakit kasa").tag("cash")
                        Text("Banka hesabı").tag("bank")
                        Text("POS").tag("pos")
                    }
                    TextField("Açılış bakiyesi (isteğe bağlı)", text: $acilis).keyboardType(.decimalPad)
                }
                .navigationTitle("Hesap ekle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { hesapAcik = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle") { hesapAcik = false; Task { await hesapEkle() } }.disabled(DVBYonBicim.kirp(hesapAdi).isEmpty)
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func kategoriBolumu(_ baslik: String, _ liste: [DVBTanimVerisi.Kategori], _ tur: String) -> some View {
        Section {
            ForEach(liste) { k in
                HStack {
                    Text(k.name).foregroundColor(k.isActive ? .primary : .secondary)
                    Spacer()
                    Button(k.isActive ? "Kapat" : "Aç") { Task { await durum("categories", k.id) } }.buttonStyle(.borderless).font(.caption)
                }
            }
            Button { kategoriAdi = ""; yeniKategori = tur } label: { Label("Kategori ekle", systemImage: "plus.circle") }
        } header: {
            Text(baslik)
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/accounting/definitions", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func durum(_ tur: String, _ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/accounting/\(tur)/\(id)/toggle", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func kategoriEkle(_ tur: String) async {
        guard let token = session.token, !DVBYonBicim.kirp(kategoriAdi).isEmpty else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/accounting/categories", body: ["name": DVBYonBicim.kirp(kategoriAdi), "kind": tur], token: token)
            bilgi = c.message
            kategoriAdi = ""
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func hesapEkle() async {
        guard let token = session.token else { return }
        var govde: [String: Any] = ["name": DVBYonBicim.kirp(hesapAdi), "type": hesapTuru]
        if let a = DVBPara.coz(acilis) { govde["opening_balance"] = DVBPara.makine(a) }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/accounting/accounts", body: govde, token: token)
            bilgi = c.message
            hesapAdi = ""
            acilis = ""
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

enum DVBHesapTuru {
    static func ad(_ t: String?) -> String {
        switch t {
        case "bank": return "Banka"
        case "pos": return "POS"
        default: return "Nakit"
        }
    }
}

// MARK: - Gelen faturalar

private struct DVBGelenFaturaVerisi: Decodable {
    let configured: Bool
    let total: Double
    let count: Int
    let data: [Fatura]
    let page: Int
    let lastPage: Int

    struct Fatura: Decodable, Identifiable, Hashable {
        let id: Int
        let sender: String?
        let senderVkn: String?
        let documentNo: String?
        let type: String?
        let issueDate: String?
        let amount: Double
        let isNew: Bool

        enum CodingKeys: String, CodingKey {
            case id, sender, type, amount
            case senderVkn = "sender_vkn"
            case documentNo = "document_no"
            case issueDate = "issue_date"
            case isNew = "is_new"
        }
    }

    enum CodingKeys: String, CodingKey {
        case configured, total, count, data, page
        case lastPage = "last_page"
    }
}

struct DVBGelenFaturalarView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBGelenFaturaVerisi?
    @State private var faturalar: [DVBGelenFaturaVerisi.Fatura] = []
    @State private var arama = ""
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yenileniyor = false
    @State private var acilan: Int?
    @State private var onizlenen: DVBYerelDosya?

    var body: some View {
        Group {
            if let v = veri {
                List {
                    Section {
                        HStack {
                            Text("\(v.count) fatura")
                            Spacer()
                            Text(DVBPara.bicim(v.total)).monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        if !v.configured {
                            Text("Gelen faturaların otomatik çekilmesi için QNB e-Fatura bilgilerinizi web panelindeki Fatura Bilgilerim ekranında girin.")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    Section {
                        ForEach(faturalar) { f in
                            Button { Task { await pdfAc(f) } } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(f.sender ?? "Gönderen").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                            if f.isNew { Text("Yeni").font(.caption2.weight(.bold)).foregroundColor(DVBTheme.accent) }
                                        }
                                        Text([f.documentNo, f.type, f.issueDate.map { DVBGunMetni.yaz($0, "d MMM yyyy") }].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if acilan == f.id { ProgressView() } else {
                                        Text(DVBPara.bicim(f.amount)).font(.subheadline.monospacedDigit()).foregroundColor(.primary)
                                    }
                                }
                            }
                            .disabled(acilan != nil || !v.configured)
                        }
                        if v.page < v.lastPage {
                            Button("Daha fazla göster") { Task { await yukle(sayfa: v.page + 1) } }
                        }
                    } footer: {
                        Text("Faturaya dokunun; PDF açılır.")
                    }
                }
                .searchable(text: $arama, prompt: "Gönderen, VKN ya da belge no")
                .onSubmit(of: .search) { Task { await yukle(sayfa: 1) } }
                .refreshable { await yukle(sayfa: 1) }
            } else if let hata {
                DVBStateView(icon: "tray.and.arrow.down", title: "Gelen faturalar alınamadı", message: hata) { Task { await yukle(sayfa: 1) } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Gelen faturalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await yenile() } } label: {
                    if yenileniyor { ProgressView() } else { Label("QNB'den güncelle", systemImage: "arrow.clockwise") }
                }
                .disabled(yenileniyor || veri?.configured != true)
            }
        }
        .task { if veri == nil { await yukle(sayfa: 1) } }
        .alert("Gelen faturalar", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .sheet(item: $onizlenen) { d in DVBBelgeOnizleme(dosya: d.url, kapat: { onizlenen = nil }) }
    }

    private func yukle(sayfa: Int) async {
        guard let token = session.token else { return }
        var q = ["page": String(sayfa)]
        let a = DVBYonBicim.kirp(arama)
        if !a.isEmpty { q["q"] = a }
        do {
            let v: DVBGelenFaturaVerisi = try await DVBAPI.shared.get("my/doctor/incoming-invoices", query: q, token: token)
            veri = v
            faturalar = sayfa == 1 ? v.data : faturalar + v.data.filter { y in !faturalar.contains(where: { $0.id == y.id }) }
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func yenile() async {
        guard let token = session.token else { return }
        yenileniyor = true
        defer { yenileniyor = false }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/incoming-invoices/refresh", token: token)
            bilgi = c.message
            await yukle(sayfa: 1)
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func pdfAc(_ f: DVBGelenFaturaVerisi.Fatura) async {
        guard let token = session.token else { return }
        acilan = f.id
        defer { acilan = nil }
        do {
            let veri = try await DVBAPI.shared.veri("my/doctor/incoming-invoices/\(f.id)/pdf", token: token)
            let ad = "GelenFatura_" + (f.documentNo ?? String(f.id)).replacingOccurrences(of: "/", with: "-") + ".pdf"
            let yol = FileManager.default.temporaryDirectory.appendingPathComponent(ad)
            try veri.write(to: yol, options: .atomic)
            onizlenen = DVBYerelDosya(url: yol)
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Personel

struct DVBPersonelKarti: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let title: String?
    let phone: String?
    let email: String?
    let isBookable: Bool
    let commissionType: String
    let commissionRate: Double?
    let monthlySalary: Double?
    let hiredOn: String?
    let notes: String?
    let isActive: Bool
    let accruedCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, title, phone, email, notes
        case isBookable = "is_bookable"
        case commissionType = "commission_type"
        case commissionRate = "commission_rate"
        case monthlySalary = "monthly_salary"
        case hiredOn = "hired_on"
        case isActive = "is_active"
        case accruedCount = "accrued_count"
    }
}

private struct DVBPersonelListesi: Decodable {
    let data: [DVBPersonelKarti]
    let isTeam: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case isTeam = "is_team"
    }
}

struct DVBPersonelView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var liste: DVBPersonelListesi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniAcik = false

    var body: some View {
        Group {
            if let l = liste {
                List {
                    if l.data.isEmpty { Text("Henüz personel yok.").foregroundColor(.secondary) }
                    ForEach(l.data) { p in
                        NavigationLink(destination: DVBPersonelAyrintiView(personelId: p.id, ad: p.name) { Task { await yukle() } }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.weight(.semibold)).foregroundColor(p.isActive ? .primary : .secondary)
                                Text([p.title, p.monthlySalary.map { "maaş " + DVBPara.bicim($0) }, p.accruedCount > 0 ? "\(p.accruedCount) bekleyen prim" : nil, p.isActive ? nil : "pasif"]
                                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "person.3", title: "Personel alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Personel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { yeniAcik = true } label: { Label("Personel ekle", systemImage: "plus") } }
        }
        .task { await yukle() }
        .alert("Personel", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .sheet(isPresented: $yeniAcik) {
            DVBPersonelFormView(personel: nil) { m in bilgi = m; Task { await yukle() } }.environmentObject(session)
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            liste = try await DVBAPI.shared.get("my/doctor/staff", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

struct DVBPersonelFormView: View {
    let personel: DVBPersonelKarti?
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var ad: String
    @State private var unvan: String
    @State private var telefon: String
    @State private var eposta: String
    @State private var randevuAlir: Bool
    @State private var primTuru: String
    @State private var primOrani: String
    @State private var maas: String
    @State private var notlar: String
    @State private var hata: String?
    @State private var calisiyor = false

    init(personel: DVBPersonelKarti?, kaydedildi: @escaping (String) -> Void) {
        self.personel = personel
        self.kaydedildi = kaydedildi
        _ad = State(initialValue: personel?.name ?? "")
        _unvan = State(initialValue: personel?.title ?? "")
        _telefon = State(initialValue: personel?.phone ?? "")
        _eposta = State(initialValue: personel?.email ?? "")
        _randevuAlir = State(initialValue: personel?.isBookable ?? false)
        _primTuru = State(initialValue: personel?.commissionType ?? "none")
        _primOrani = State(initialValue: personel?.commissionRate.map { DVBSayi.yaz($0) } ?? "")
        _maas = State(initialValue: personel?.monthlySalary.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "")
        _notlar = State(initialValue: personel?.notes ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Ad soyad", text: $ad)
                    TextField("Görev (ör. Hemşire)", text: $unvan)
                    TextField("Telefon", text: $telefon).keyboardType(.phonePad)
                    TextField("E-posta", text: $eposta).keyboardType(.emailAddress).autocapitalization(.none)
                    Toggle("Randevu alan sağlayıcı", isOn: $randevuAlir)
                }
                Section("Ücret ve prim") {
                    TextField("Aylık maaş (isteğe bağlı)", text: $maas).keyboardType(.decimalPad)
                    Picker("Prim", selection: $primTuru) {
                        Text("Yok").tag("none")
                        Text("Yüzde").tag("percent")
                        Text("Sabit tutar").tag("fixed")
                    }
                    if primTuru != "none" {
                        TextField(primTuru == "percent" ? "Oran (%)" : "Tutar (₺)", text: $primOrani).keyboardType(.decimalPad)
                    }
                    TextField("Not", text: $notlar)
                }
                if let hata { Section { Text(hata).foregroundColor(.red).font(.subheadline) } }
            }
            .navigationTitle(personel == nil ? "Personel ekle" : "Personeli düzenle")
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
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "name": DVBYonBicim.kirp(ad), "title": DVBYonBicim.kirp(unvan), "phone": DVBYonBicim.kirp(telefon),
            "email": DVBYonBicim.kirp(eposta), "is_bookable": randevuAlir, "commission_type": primTuru, "notes": DVBYonBicim.kirp(notlar),
        ]
        if let m = DVBPara.coz(maas) { govde["monthly_salary"] = DVBPara.makine(m) }
        if primTuru != "none", let o = DVBPara.coz(primOrani) { govde["commission_rate"] = DVBPara.makine(o) }
        do {
            let c: DVBYonCevap
            if let personel {
                c = try await DVBAPI.shared.put("my/doctor/staff/\(personel.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/staff", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBPersonelAyrintisi: Decodable {
    let staff: DVBPersonelKarti
    let ledger: Defter
    let commissions: [Prim]
    let payments: [Odeme]
    let paymentTypes: [Tur]
    let accounts: [DVBFinSecenek]

    struct Defter: Decodable {
        let accrued: Double
        let paidCommission: Double
        let salaryPaid: Double
        let totalPaid: Double

        enum CodingKeys: String, CodingKey {
            case accrued
            case paidCommission = "paid_commission"
            case salaryPaid = "salary_paid"
            case totalPaid = "total_paid"
        }
    }

    struct Prim: Decodable, Hashable {
        let description: String?
        let amount: Double
        let status: String?
        let earnedOn: String?

        enum CodingKeys: String, CodingKey {
            case description, amount, status
            case earnedOn = "earned_on"
        }
    }

    struct Odeme: Decodable, Hashable {
        let type: String
        let amount: Double
        let description: String?
        let paidOn: String?

        enum CodingKeys: String, CodingKey {
            case type, amount, description
            case paidOn = "paid_on"
        }
    }

    struct Tur: Decodable, Hashable {
        let key: String
        let label: String
    }

    enum CodingKeys: String, CodingKey {
        case staff, ledger, commissions, payments, accounts
        case paymentTypes = "payment_types"
    }
}

private struct DVBPersonelAyrintiView: View {
    let personelId: Int
    let ad: String
    var degisti: () -> Void

    @EnvironmentObject private var session: DVBSession
    @State private var a: DVBPersonelAyrintisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var duzenleAcik = false
    @State private var odemeAcik = false
    @State private var primAcik = false
    @State private var hakedisOnayi = false

    var body: some View {
        Group {
            if let a {
                List {
                    Section {
                        satir("Bekleyen prim", DVBPara.bicim(a.ledger.accrued))
                        satir("Ödenen hakediş", DVBPara.bicim(a.ledger.paidCommission))
                        satir("Ödenen maaş/avans/prim", DVBPara.bicim(a.ledger.salaryPaid))
                        satir("Toplam ödenen", DVBPara.bicim(a.ledger.totalPaid))
                    } header: {
                        Text(a.staff.title ?? "Özet")
                    }
                    Section {
                        Button { odemeAcik = true } label: { Label("Ödeme kaydet (maaş/avans/prim)", systemImage: "banknote") }
                        Button { primAcik = true } label: { Label("Prim ekle", systemImage: "plus.circle") }
                        if a.ledger.accrued > 0 {
                            Button { hakedisOnayi = true } label: { Label("Bekleyen primi öde", systemImage: "checkmark.circle") }
                        }
                        Button { Task { await durum() } } label: { Label(a.staff.isActive ? "Pasife al" : "Etkinleştir", systemImage: "power") }
                    } footer: {
                        Text("Ödemeler kasaya gider olarak yazılır.")
                    }
                    if !a.payments.isEmpty {
                        Section("Ödemeler") {
                            ForEach(a.payments, id: \.self) { o in
                                satir("\(o.type) · \(DVBGunMetni.yaz(o.paidOn, "d MMM yyyy"))", DVBPara.bicim(o.amount))
                            }
                        }
                    }
                    if !a.commissions.isEmpty {
                        Section("Primler") {
                            ForEach(a.commissions, id: \.self) { p in
                                satir((p.description ?? "Prim") + (p.status == "accrued" ? " · bekliyor" : ""), DVBPara.bicim(p.amount))
                            }
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "person", title: "Personel alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Düzenle") { duzenleAcik = true }.disabled(a == nil) }
        }
        .task { await yukle() }
        .alert("Personel", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .alert("Bekleyen prim ödensin mi?", isPresented: $hakedisOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("Öde") { Task { await hakedisOde() } }
        } message: {
            Text("Bekleyen primlerin tamamı ödenmiş sayılır ve kasaya gider olarak yazılır.")
        }
        .sheet(isPresented: $duzenleAcik) {
            if let k = a?.staff {
                DVBPersonelFormView(personel: k) { m in bilgi = m; degisti(); Task { await yukle() } }.environmentObject(session)
            }
        }
        .sheet(isPresented: $odemeAcik) {
            DVBPersonelOdemeView(personelId: personelId, prim: false, turler: a?.paymentTypes ?? [], hesaplar: a?.accounts ?? []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
        .sheet(isPresented: $primAcik) {
            DVBPersonelOdemeView(personelId: personelId, prim: true, turler: [], hesaplar: []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
    }

    private func satir(_ e: String, _ d: String) -> some View {
        HStack { Text(e).font(.subheadline); Spacer(); Text(d).font(.subheadline.monospacedDigit()).foregroundColor(.secondary) }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            a = try await DVBAPI.shared.get("my/doctor/staff/\(personelId)", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func durum() async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/staff/\(personelId)/toggle", token: token)
            bilgi = c.message
            degisti()
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func hakedisOde() async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/staff/\(personelId)/pay-commissions", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

private struct DVBPersonelOdemeView: View {
    let personelId: Int
    let prim: Bool
    let turler: [DVBPersonelAyrintisi.Tur]
    let hesaplar: [DVBFinSecenek]
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var tur = "salary"
    @State private var tutar = ""
    @State private var tarih = Date()
    @State private var hesapId: Int?
    @State private var aciklama = ""
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationView {
            Form {
                if !prim {
                    Picker("Tür", selection: $tur) { ForEach(turler, id: \.key) { t in Text(t.label).tag(t.key) } }
                }
                TextField("Tutar (ör. 30.000,00)", text: $tutar).keyboardType(.decimalPad)
                DatePicker("Tarih", selection: $tarih, displayedComponents: .date).environment(\.timeZone, DVBTime.klinik)
                if !prim {
                    Picker("Hesap", selection: $hesapId) {
                        Text("Varsayılan").tag(Int?.none)
                        ForEach(hesaplar) { h in Text(h.name).tag(Int?.some(h.id)) }
                    }
                }
                TextField("Açıklama (isteğe bağlı)", text: $aciklama)
                if let hata { Text(hata).foregroundColor(.red).font(.subheadline) }
            }
            .navigationTitle(prim ? "Prim ekle" : "Ödeme kaydet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await kaydet() } } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(calisiyor || DVBPara.coz(tutar) == nil)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token, let t = DVBPara.coz(tutar) else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["amount": DVBPara.makine(t)]
        let a = DVBYonBicim.kirp(aciklama)
        if !a.isEmpty { govde["description"] = a }
        let yol: String
        if prim {
            govde["earned_on"] = DVBYonBicim.ymd(tarih)
            yol = "my/doctor/staff/\(personelId)/commissions"
        } else {
            govde["type"] = tur
            govde["paid_on"] = DVBYonBicim.ymd(tarih)
            if let hesapId { govde["cash_account_id"] = hesapId }
            yol = "my/doctor/staff/\(personelId)/payments"
        }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post(yol, body: govde, token: token)
            kaydedildi(c.message ?? "Kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
