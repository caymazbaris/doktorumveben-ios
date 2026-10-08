import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000341 — HİZMETLER (hekim).
//
// Kullanıcı (8 Eki 2026): "3 günlük işleri de yapalm" (hasta talepleri, çalışma saatleri ve izinler, hizmetler, randevu taşıma).
//
// Web /panel/hizmetler tanım bölümüyle AYNI kurallar (HekimIsleriApiController, ServiceController::validateService):
// ad, fiyat (+ isteğe bağlı aralık), süre, görüşme şekli, randevuya açık mı, KDV. Hekim/sahip her zaman; sekreter web'deki
// "muhasebe" izniyle; muhasebe görünümü asla. Hizmet SATIŞI (kasa kaydı) web panelinde kalır.
//
// ⚠ Fiyatlar 10.000,00 biçiminde gösterilir (İksero para biçimi standardı); giriş alanında binlik ayracı kullanılmaz.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBHekimHizmet: Decodable, Identifiable {
    let id: Int
    let name: String
    let category: String?
    let price: Double
    let priceMin: Double?
    let priceMax: Double?
    let durationMinutes: Int
    let description: String?
    let channel: String
    let sessionCount: Int?
    let vatRate: Double?
    let priceIncludesVat: Bool?
    let isBookable: Bool
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, category, price, description, channel
        case priceMin = "price_min"
        case priceMax = "price_max"
        case durationMinutes = "duration_minutes"
        case sessionCount = "session_count"
        case vatRate = "vat_rate"
        case priceIncludesVat = "price_includes_vat"
        case isBookable = "is_bookable"
        case isActive = "is_active"
    }

    var kanalEtiketi: String {
        switch channel {
        case "online": return "Online"
        case "both": return "Yüz yüze + online"
        default: return "Yüz yüze"
        }
    }
}

private struct DVBHizmetListesi: Decodable {
    let data: [DVBHekimHizmet]
}

private struct DVBHizmetCevabi: Decodable {
    let ok: Bool
    let message: String?
}

/// Düzenleme alanına konacak metin: binlik ayraçsız, virgül ondalık ("1500,00"). Gösterim `DVBPara.bicim`, çözüm
/// `DVBPara.coz`, API'ye giden `DVBPara.makine` (ortak para yardımcıları; İksero para biçimi standardı).
private func dvbHizmetTutarAlani(_ tutar: Double?) -> String {
    guard let tutar else { return "" }
    return String(format: "%.2f", tutar).replacingOccurrences(of: ".", with: ",")
}

struct DVBHekimHizmetlerView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var hizmetler: [DVBHekimHizmet]?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var duzenlenen: DVBHekimHizmet?
    @State private var yeniAcik = false
    @State private var degistirilen: Int?

    var body: some View {
        Group {
            if let liste = hizmetler {
                List {
                    Section {
                        if liste.isEmpty {
                            Text("Henüz hizmet yok.").foregroundColor(.secondary)
                        } else {
                            ForEach(liste) { satir($0) }
                        }
                    } footer: {
                        Text("Randevuya açık ve etkin hizmetler hastaların randevu ekranında görünür. Hizmet satışı ve kasa kayıtları web panelinde.")
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "list.bullet.rectangle", title: "Hizmetler alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Hizmetler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    yeniAcik = true
                } label: {
                    Label("Hizmet ekle", systemImage: "plus")
                }
                .disabled(hizmetler == nil)
            }
        }
        .task { await yukle() }
        .alert("Hizmetler", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .sheet(isPresented: $yeniAcik) {
            DVBHizmetFormView(hizmet: nil) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
        .sheet(item: $duzenlenen) { h in
            DVBHizmetFormView(hizmet: h) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func satir(_ h: DVBHekimHizmet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(h.name).font(.subheadline.weight(.semibold))
                    .foregroundColor(h.isActive ? .primary : .secondary)
                Text(altSatir(h)).font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if !h.isActive { cip("Kapalı", .secondary) }
                    if h.isBookable && h.isActive { cip("Randevuya açık", DVBTheme.accent) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Düzenle") { duzenlenen = h }
                    .font(.caption.weight(.semibold))
                Button {
                    Task { await durumDegistir(h.id) }
                } label: {
                    if degistirilen == h.id { ProgressView() } else { Text(h.isActive ? "Kapat" : "Aç").font(.caption.weight(.semibold)) }
                }
                .disabled(degistirilen != nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    private func altSatir(_ h: DVBHekimHizmet) -> String {
        var p: [String] = [DVBPara.bicim(h.price)]
        if h.durationMinutes > 0 { p.append("\(h.durationMinutes) dk") }
        p.append(h.kanalEtiketi)
        if let k = h.category, !k.isEmpty { p.append(k) }
        return p.joined(separator: " · ")
    }

    private func cip(_ metin: String, _ renk: Color) -> some View {
        Text(metin).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(renk.opacity(0.15)).foregroundColor(renk)
            .clipShape(Capsule())
    }

    // MARK: - Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHizmetListesi = try await DVBAPI.shared.get("my/doctor/services", token: token)
            hizmetler = c.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func durumDegistir(_ id: Int) async {
        guard let token = session.token, degistirilen == nil else { return }
        degistirilen = id
        defer { degistirilen = nil }
        do {
            let c: DVBHizmetCevabi = try await DVBAPI.shared.post("my/doctor/services/\(id)/toggle", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Ekleme / düzenleme formu

struct DVBHizmetFormView: View {
    let hizmet: DVBHekimHizmet?
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var ad: String
    @State private var kategori: String
    @State private var fiyat: String
    @State private var fiyatMin: String
    @State private var fiyatMax: String
    @State private var sure: Int
    @State private var kanal: String
    @State private var randevuyaAcik: Bool
    @State private var aciklama: String
    @State private var kdv: String
    @State private var kdvDahil: Bool
    @State private var calisiyor = false
    @State private var hata: String?

    init(hizmet: DVBHekimHizmet?, kaydedildi: @escaping (String) -> Void) {
        self.hizmet = hizmet
        self.kaydedildi = kaydedildi
        _ad = State(initialValue: hizmet?.name ?? "")
        _kategori = State(initialValue: hizmet?.category ?? "")
        _fiyat = State(initialValue: dvbHizmetTutarAlani(hizmet?.price))
        _fiyatMin = State(initialValue: dvbHizmetTutarAlani(hizmet?.priceMin))
        _fiyatMax = State(initialValue: dvbHizmetTutarAlani(hizmet?.priceMax))
        _sure = State(initialValue: hizmet?.durationMinutes ?? 30)
        _kanal = State(initialValue: hizmet?.channel ?? "in_person")
        _randevuyaAcik = State(initialValue: hizmet?.isBookable ?? true)
        _aciklama = State(initialValue: hizmet?.description ?? "")
        _kdv = State(initialValue: String(Int(hizmet?.vatRate ?? 20)))
        _kdvDahil = State(initialValue: hizmet?.priceIncludesVat ?? false)
    }

    private var hazir: Bool {
        !ad.trimmingCharacters(in: .whitespaces).isEmpty && DVBPara.coz(fiyat) != nil
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Hizmet adı (ör. Muayene)", text: $ad)
                    TextField("Kategori (isteğe bağlı)", text: $kategori)
                    Picker("Görüşme", selection: $kanal) {
                        Text("Yüz yüze").tag("in_person")
                        Text("Online").tag("online")
                        Text("Yüz yüze + online").tag("both")
                    }
                    Stepper("Süre: \(sure) dk", value: $sure, in: 0...600, step: 5)
                    Toggle("Randevuya açık", isOn: $randevuyaAcik)
                } header: {
                    Text("Hizmet")
                } footer: {
                    Text("Online görüşme için \"Online\" seçin; hastaya görüşme bağlantısı kendiliğinden gider.")
                }

                Section {
                    TextField("Fiyat (ör. 1500,00)", text: $fiyat)
                        .keyboardType(.decimalPad)
                    TextField("En düşük (isteğe bağlı)", text: $fiyatMin)
                        .keyboardType(.decimalPad)
                    TextField("En yüksek (isteğe bağlı)", text: $fiyatMax)
                        .keyboardType(.decimalPad)
                    TextField("KDV oranı (%)", text: $kdv)
                        .keyboardType(.numberPad)
                    Toggle("Fiyata KDV dahil", isOn: $kdvDahil)
                } header: {
                    Text("Fiyat")
                } footer: {
                    Text("Fiyat aralığı girilirse profilde aralık gösterilir.")
                }

                Section("Açıklama") {
                    TextEditor(text: $aciklama).frame(minHeight: 80)
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle(hizmet == nil ? "Yeni hizmet" : "Hizmeti düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await kaydet() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token, hazir, !calisiyor, let fiyatSayi = DVBPara.coz(fiyat) else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "name": ad.trimmingCharacters(in: .whitespacesAndNewlines),
            "price": DVBPara.makine(fiyatSayi),
            "duration_minutes": sure,
            "channel": kanal,
            "is_bookable": randevuyaAcik,
            "price_includes_vat": kdvDahil,
        ]
        // Boş bırakılan alan da gider: sunucu boş metni null'a çevirir, düzenlemede silinen kategori/açıklama silinsin.
        govde["category"] = kategori.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = DVBPara.coz(fiyatMin) { govde["price_min"] = DVBPara.makine(v) }
        if let v = DVBPara.coz(fiyatMax) { govde["price_max"] = DVBPara.makine(v) }
        if let v = DVBPara.coz(kdv) { govde["vat_rate"] = DVBPara.makine(v) }
        govde["description"] = aciklama.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = hizmet?.sessionCount { govde["session_count"] = s }

        do {
            let c: DVBHizmetCevabi
            if let hizmet {
                c = try await DVBAPI.shared.put("my/doctor/services/\(hizmet.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/services", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Hizmet kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
