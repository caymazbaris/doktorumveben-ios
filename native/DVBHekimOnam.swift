import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000351 — ONAM FORMLARI VE UZAKTAN İMZA (hekim).
//
// Kullanıcı (9 Eki 2026): "Onam formları ve uzaktan imzalatma" + "3 ve 4 ü yap".
//
// Web paneliyle AYNI kurallar (sunucu: HekimOnamApiController ← Web\Panel\ConsentController):
//  · Onam formları: hekimin kendi metinleri (ekle / düzenle / yayına al-kaldır / sil) + hazır (global) metinler SALT OKUNUR.
//  · Hasta kartı → Onamlar: imzalı onamlar (PDF), bekleyen uzaktan talepler (geri çek), klinikte imza (hasta hekimin
//    cihazında parmağıyla imzalar → PNG), uzaktan imza bağlantısı (WhatsApp / e-posta / yalnız bağlantı).
//  · İmzalı metin SNAPSHOT olarak saklanır; şablon sonradan değişse de imzalı onam değişmez (sunucu).
//  · Gizli hastada numara maskeli kalır; WhatsApp yalnız hekimin açık onayıyla ("gizli numaraya gönderilsin").
//
// ⚠ Bu dosyanın tipleri yalnız uygulama hedefinde: DVBModels.swift widget hedefiyle paylaşılır, oraya eklenmez.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBOnamSablonu: Decodable, Identifiable {
    let id: Int
    let title: String
    let body: String?
    let isActive: Bool?
    let sortOrder: Int?
    let showOnBooking: Bool?
    let isGlobal: Bool?
    let editable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, body, editable
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case showOnBooking = "show_on_booking"
        case isGlobal = "is_global"
    }

    var duzenlenebilir: Bool { editable ?? false }
    var acik: Bool { isActive ?? true }
}

private struct DVBOnamSablonListesi: Decodable {
    let data: [DVBOnamSablonu]
}

private struct DVBOnamCevabi: Decodable {
    let ok: Bool?
    let message: String?
}

struct DVBImzaliOnam: Decodable, Identifiable {
    let id: Int
    let title: String?
    let signedAt: Date?
    let method: String?
    let methodLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, title, method
        case signedAt = "signed_at"
        case methodLabel = "method_label"
    }
}

struct DVBOnamTalebi: Decodable, Identifiable {
    let id: Int
    let title: String?
    let statusLabel: String?
    let sentVia: String?
    let sentViaLabel: String?
    let createdAt: Date?
    let expiresAt: Date?
    let openedAt: Date?
    let isOpen: Bool?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id, title, url
        case statusLabel = "status_label"
        case sentVia = "sent_via"
        case sentViaLabel = "sent_via_label"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case openedAt = "opened_at"
        case isOpen = "is_open"
    }
}

private struct DVBHastaOnamlari: Decodable {
    let patient: Hasta?
    let consents: [DVBImzaliOnam]
    let requests: [DVBOnamTalebi]
    let templates: [DVBOnamSablonu]

    struct Hasta: Decodable {
        let id: Int
        let isPrivate: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case isPrivate = "is_private"
        }
    }
}

private struct DVBOnamGonderCevabi: Decodable {
    let ok: Bool?
    let message: String?
    let sentVia: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case ok, message, url
        case sentVia = "sent_via"
    }
}

private struct DVBOnamPaylasimOgesi: Identifiable {
    let id = UUID()
    let metin: String
}

private enum DVBOnamTarih {
    static func gun(_ d: Date?) -> String {
        guard let d else { return "—" }
        return DVBSaat.gun(d, "d MMM yyyy")
    }

    static func gunSaat(_ d: Date?) -> String {
        guard let d else { return "—" }
        return DVBSaat.gun(d, "d MMM yyyy HH:mm")
    }
}

private func dvbOnamCip(_ metin: String, _ renk: Color) -> some View {
    Text(metin).font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(renk.opacity(0.15)).foregroundColor(renk)
        .clipShape(Capsule())
}

// MARK: - Onam formları (şablonlar)

struct DVBHekimOnamFormlariView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var sablonlar: [DVBOnamSablonu]?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniAcik = false
    @State private var duzenlenen: DVBOnamSablonu?
    @State private var silinecek: DVBOnamSablonu?
    @State private var degistirilen: Int?

    var body: some View {
        Group {
            if let liste = sablonlar {
                let kendi = liste.filter { $0.duzenlenebilir }
                let hazir = liste.filter { !$0.duzenlenebilir }
                List {
                    Section {
                        if kendi.isEmpty {
                            Text("Henüz kendi onam metniniz yok. Sağ üstteki + ile ekleyebilirsiniz.").foregroundColor(.secondary)
                        } else {
                            ForEach(kendi) { kendiSatir($0) }
                        }
                    } header: {
                        Text("Kendi metinlerim")
                    } footer: {
                        Text("Yayından kaldırılan metin hastaya imzalatılamaz. Silinen metinle daha önce imzalanmış onamlar etkilenmez.")
                    }

                    if !hazir.isEmpty {
                        Section {
                            ForEach(hazir) { s in
                                NavigationLink(destination: DVBOnamMetniView(sablon: s)) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.title).font(.subheadline.weight(.semibold))
                                        Text(ozet(s.body)).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Text("Hazır metinler")
                        } footer: {
                            Text("Hazır metinler tüm hekimler için ortaktır; değiştirilemez ama hastalarınıza imzalatabilirsiniz.")
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "signature", title: "Onam formları alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Onam formları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    yeniAcik = true
                } label: {
                    Label("Onam metni ekle", systemImage: "plus")
                }
                .disabled(sablonlar == nil)
            }
        }
        .task { await yukle() }
        .alert("Onam formları", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .confirmationDialog("Onam metni silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let s = silinecek { Task { await sil(s.id) } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu metinle daha önce imzalanmış onamlar silinmez.")
        }
        .sheet(isPresented: $yeniAcik) {
            DVBOnamSablonFormView(sablon: nil) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
        .sheet(item: $duzenlenen) { s in
            DVBOnamSablonFormView(sablon: s) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func kendiSatir(_ s: DVBOnamSablonu) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.subheadline.weight(.semibold))
                    .foregroundColor(s.acik ? .primary : .secondary)
                Text(ozet(s.body)).font(.caption).foregroundColor(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    if !s.acik { dvbOnamCip("Yayında değil", .secondary) }
                    if s.showOnBooking == true && s.acik { dvbOnamCip("Online randevuda", DVBTheme.accent) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Düzenle") { duzenlenen = s }
                    .font(.caption.weight(.semibold))
                Button {
                    Task { await durumDegistir(s.id) }
                } label: {
                    if degistirilen == s.id { ProgressView() } else { Text(s.acik ? "Kaldır" : "Yayına al").font(.caption.weight(.semibold)) }
                }
                .disabled(degistirilen != nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { silinecek = s } label: { Label("Sil", systemImage: "trash") }
        }
    }

    private func ozet(_ metin: String?) -> String {
        (metin ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBOnamSablonListesi = try await DVBAPI.shared.get("my/doctor/consent-templates", token: token)
            sablonlar = c.data
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
            let c: DVBOnamCevabi = try await DVBAPI.shared.post("my/doctor/consent-templates/\(id)/toggle", token: token)
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func sil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBOnamCevabi = try await DVBAPI.shared.delete("my/doctor/consent-templates/\(id)", token: token)
            bilgi = c.message ?? "Onam metni silindi."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

/// Hazır (global) metnin salt okunur görünümü.
struct DVBOnamMetniView: View {
    let sablon: DVBOnamSablonu

    var body: some View {
        ScrollView {
            Text(sablon.body ?? "")
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(sablon.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Şablon ekleme / düzenleme formu

struct DVBOnamSablonFormView: View {
    let sablon: DVBOnamSablonu?
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var baslik: String
    @State private var metin: String
    @State private var randevudaGoster: Bool
    @State private var calisiyor = false
    @State private var hata: String?

    init(sablon: DVBOnamSablonu?, kaydedildi: @escaping (String) -> Void) {
        self.sablon = sablon
        self.kaydedildi = kaydedildi
        _baslik = State(initialValue: sablon?.title ?? "")
        _metin = State(initialValue: sablon?.body ?? "")
        _randevudaGoster = State(initialValue: sablon?.showOnBooking ?? false)
    }

    private var hazir: Bool {
        let b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        return !b.isEmpty && b.count <= 150 && !m.isEmpty && m.count <= 8000
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Başlık (ör. Botoks Uygulama Onamı)", text: $baslik)
                } header: {
                    Text("Başlık")
                } footer: {
                    Text("En çok 150 karakter.")
                }

                Section {
                    TextEditor(text: $metin).frame(minHeight: 220)
                } header: {
                    Text("Onam metni")
                } footer: {
                    Text("\(metin.count) / 8000 karakter. Hasta imzalarken bu metni okur; imzalanan metin o anki haliyle saklanır.")
                }

                Section {
                    Toggle("Online randevuda hastaya onaylat", isOn: $randevudaGoster)
                } footer: {
                    Text("Açıksa hasta online randevu alırken bu metni onaylar.")
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle(sablon == nil ? "Yeni onam metni" : "Onam metnini düzenle")
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
        guard let token = session.token, hazir, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        let govde: [String: Any] = [
            "title": baslik.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": metin.trimmingCharacters(in: .whitespacesAndNewlines),
            "show_on_booking": randevudaGoster,
            // Sıra web panelinden yönetilir; düzenlemede mevcut sıra korunur.
            "sort_order": sablon?.sortOrder ?? 0,
        ]
        do {
            let c: DVBOnamCevabi
            if let sablon {
                c = try await DVBAPI.shared.put("my/doctor/consent-templates/\(sablon.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/consent-templates", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Onam metni kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Hastanın onamları

struct DVBHekimHastaOnamlariView: View {
    let hastaId: Int
    let ad: String

    @EnvironmentObject private var session: DVBSession

    @State private var veri: DVBHastaOnamlari?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var imzaAcik = false
    @State private var gonderAcik = false
    @State private var geriCekilecek: DVBOnamTalebi?
    @State private var paylasilan: DVBOnamPaylasimOgesi?
    @State private var onizlenen: DVBYerelDosya?
    @State private var acilanPdf: Int?

    var body: some View {
        List {
            if let v = veri {
                Section {
                    Button {
                        imzaAcik = true
                    } label: {
                        Label("Klinikte imzalat", systemImage: "signature")
                    }
                    .disabled(v.templates.isEmpty)
                    Button {
                        gonderAcik = true
                    } label: {
                        Label("Uzaktan imza gönder", systemImage: "paperplane")
                    }
                    .disabled(v.templates.isEmpty)
                    if v.templates.isEmpty {
                        NavigationLink(destination: DVBHekimOnamFormlariView()) {
                            Label("Önce bir onam metni ekleyin", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("İmza al")
                } footer: {
                    Text("Hasta yanınızdaysa telefonunuzda parmağıyla imzalar. Yanınızda değilse süreli, tek kullanımlık bir imza bağlantısı gönderin.")
                }

                if !v.requests.isEmpty {
                    Section {
                        ForEach(v.requests) { talepSatiri($0) }
                    } header: {
                        Text("Bekleyen imza talepleri")
                    }
                }

                Section {
                    if v.consents.isEmpty {
                        Text("İmzalı onam yok.").foregroundColor(.secondary)
                    } else {
                        ForEach(v.consents) { c in
                            Button {
                                Task { await pdfAc(c) }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.title ?? "Onam").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                        Text([DVBOnamTarih.gunSaat(c.signedAt), c.methodLabel].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if acilanPdf == c.id {
                                        ProgressView()
                                    } else {
                                        Label("PDF", systemImage: "doc.richtext").font(.caption.weight(.semibold))
                                    }
                                }
                            }
                            .disabled(acilanPdf != nil)
                        }
                    }
                } header: {
                    Text("İmzalı onamlar")
                } footer: {
                    Text("PDF imza anındaki metinden üretilir; açılması hasta dosyası erişim kaydına yazılır.")
                }
            } else if let hata {
                DVBStateView(icon: "signature", title: "Onamlar alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Onamlar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await yukle() }
        .task { await yukle() }
        .alert("Onamlar", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .confirmationDialog("İmza bağlantısı geri çekilsin mi?", isPresented: Binding(get: { geriCekilecek != nil }, set: { if !$0 { geriCekilecek = nil } }), titleVisibility: .visible) {
            Button("Geri çek", role: .destructive) {
                if let t = geriCekilecek { Task { await geriCek(t.id) } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bağlantı hemen geçersiz olur; hasta artık imzalayamaz.")
        }
        .sheet(isPresented: $imzaAcik) {
            DVBKlinikImzaView(hastaId: hastaId, ad: ad, sablonlar: veri?.templates ?? []) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $gonderAcik) {
            DVBUzaktanOnamView(hastaId: hastaId, ad: ad, sablonlar: veri?.templates ?? [], gizliHasta: veri?.patient?.isPrivate ?? false) {
                Task { await yukle() }
            }
            .environmentObject(session)
        }
        .sheet(item: $paylasilan) { DVBPaylasim(ogeler: [$0.metin]) }
        .sheet(item: $onizlenen) { d in DVBBelgeOnizleme(dosya: d.url, kapat: { onizlenen = nil }) }
    }

    private func talepSatiri(_ t: DVBOnamTalebi) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t.title ?? "Onam").font(.subheadline.weight(.semibold))
            Text(talepAlt(t)).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 16) {
                if let url = t.url {
                    Button {
                        UIPasteboard.general.string = url
                        bilgi = "Bağlantı kopyalandı."
                    } label: {
                        Label("Kopyala", systemImage: "doc.on.doc")
                    }
                    Button {
                        paylasilan = DVBOnamPaylasimOgesi(metin: url)
                    } label: {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    geriCekilecek = t
                } label: {
                    Text("Geri çek")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    private func talepAlt(_ t: DVBOnamTalebi) -> String {
        var p: [String] = []
        if let s = t.statusLabel { p.append(s) }
        if let k = t.sentViaLabel { p.append(k) }
        if let e = t.expiresAt { p.append(DVBOnamTarih.gun(e) + " tarihine kadar") }
        return p.joined(separator: " · ")
    }

    // MARK: Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHastaOnamlari = try await DVBAPI.shared.get("my/doctor/patients/\(hastaId)/consents", token: token)
            veri = c
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func geriCek(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBOnamCevabi = try await DVBAPI.shared.post("my/doctor/consent-requests/\(id)/revoke", token: token)
            bilgi = c.message ?? "Onam bağlantısı geri çekildi."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func pdfAc(_ c: DVBImzaliOnam) async {
        guard let token = session.token, acilanPdf == nil else { return }
        acilanPdf = c.id
        defer { acilanPdf = nil }
        do {
            let veri = try await DVBAPI.shared.veri("my/doctor/consents/\(c.id)/pdf", token: token)
            let yol = FileManager.default.temporaryDirectory.appendingPathComponent("Onam_\(c.id).pdf")
            try veri.write(to: yol, options: .atomic)
            onizlenen = DVBYerelDosya(url: yol)
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Klinikte imza

struct DVBKlinikImzaView: View {
    let hastaId: Int
    let ad: String
    let sablonlar: [DVBOnamSablonu]
    var imzalandi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var seciliId: Int
    @State private var cizgiler: [[CGPoint]] = []
    @State private var alanBoyutu: CGSize = .zero
    @State private var calisiyor = false
    @State private var hata: String?

    init(hastaId: Int, ad: String, sablonlar: [DVBOnamSablonu], imzalandi: @escaping (String) -> Void) {
        self.hastaId = hastaId
        self.ad = ad
        self.sablonlar = sablonlar
        self.imzalandi = imzalandi
        _seciliId = State(initialValue: sablonlar.first?.id ?? 0)
    }

    private var secili: DVBOnamSablonu? { sablonlar.first { $0.id == seciliId } }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Onam metni").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Picker("Onam metni", selection: $seciliId) {
                        ForEach(sablonlar) { s in Text(s.title).tag(s.id) }
                    }
                    .pickerStyle(.menu)
                }

                ScrollView {
                    Text(secili?.body ?? "")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("\(ad) metni okuduktan sonra aşağıdaki alana parmağıyla imzalasın.")
                    .font(.caption).foregroundColor(.secondary)

                DVBImzaAlani(cizgiler: $cizgiler, boyut: $alanBoyutu)
                    .frame(height: 200)

                if let hata {
                    Text(hata).font(.subheadline).foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button {
                        cizgiler = []
                    } label: {
                        Text("Temizle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(cizgiler.isEmpty || calisiyor)

                    Button {
                        Task { await imzala() }
                    } label: {
                        Group {
                            if calisiyor { ProgressView() } else { Text("Onayla ve imzala").bold() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cizgiler.isEmpty || secili == nil || calisiyor)
                }
            }
            .padding()
            .navigationTitle("Klinikte imza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        // İmza atarken aşağı çekme sayfayı kapatmasın.
        .interactiveDismissDisabled(true)
        .onChange(of: seciliId) { _ in cizgiler = [] }
    }

    private func imzala() async {
        guard let token = session.token, !calisiyor, let s = secili else { return }
        guard let png = DVBImzaAlani.png(cizgiler, boyut: alanBoyutu) else {
            hata = "İmza alınamadı. Lütfen tekrar imzalayın."
            return
        }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let c: DVBOnamCevabi = try await DVBAPI.shared.post(
                "my/doctor/patients/\(hastaId)/consents/sign",
                body: ["consent_template_id": s.id, "signature": png],
                token: token
            )
            imzalandi(c.message ?? "Onam imzalandı.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

/// Parmakla imza alanı (iOS 15: PencilKit'e gerek yok). Çizgiler alan koordinatında tutulur; PNG beyaz zemine siyah
/// mürekkeple, alanın kendi boyutunda üretilir (koyu görünümde de imza okunur kalsın diye zemin sabit beyaz).
struct DVBImzaAlani: View {
    @Binding var cizgiler: [[CGPoint]]
    @Binding var boyut: CGSize

    @State private var ciziyor = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                if cizgiler.isEmpty {
                    Text("İmza alanı").font(.subheadline).foregroundColor(.gray)
                }
                DVBImzaCizimi(cizgiler: cizgiler)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { d in
                        let p = CGPoint(x: min(max(d.location.x, 0), geo.size.width),
                                        y: min(max(d.location.y, 0), geo.size.height))
                        if !ciziyor || cizgiler.isEmpty {
                            cizgiler.append([p])
                            ciziyor = true
                        } else {
                            cizgiler[cizgiler.count - 1].append(p)
                        }
                    }
                    .onEnded { _ in ciziyor = false }
            )
            .onAppear { boyut = geo.size }
            .onChange(of: geo.size) { yeni in boyut = yeni }
        }
        .accessibilityLabel("İmza alanı")
    }

    /// "data:image/png;base64,…" — sunucu sınırı 300.000 karakter; sığmazsa düşük çözünürlükle yeniden üretilir.
    static func png(_ cizgiler: [[CGPoint]], boyut: CGSize) -> String? {
        guard !cizgiler.isEmpty, boyut.width > 0, boyut.height > 0 else { return nil }
        for olcek in [2.0, 1.0] as [CGFloat] {
            let bicim = UIGraphicsImageRendererFormat()
            bicim.scale = olcek
            bicim.opaque = true
            let ciz = UIGraphicsImageRenderer(size: boyut, format: bicim)
            let resim = ciz.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: boyut))
                let yol = UIBezierPath()
                yol.lineWidth = 2.5
                yol.lineCapStyle = .round
                yol.lineJoinStyle = .round
                for cizgi in cizgiler {
                    guard let ilk = cizgi.first else { continue }
                    yol.move(to: ilk)
                    if cizgi.count == 1 {
                        yol.addLine(to: CGPoint(x: ilk.x + 0.5, y: ilk.y + 0.5))
                    } else {
                        for n in cizgi.dropFirst() { yol.addLine(to: n) }
                    }
                }
                UIColor.black.setStroke()
                yol.stroke()
            }
            guard let veri = resim.pngData() else { continue }
            let metin = "data:image/png;base64," + veri.base64EncodedString()
            if metin.count <= 290_000 { return metin }
        }
        return nil
    }
}

private struct DVBImzaCizimi: Shape {
    let cizgiler: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var yol = Path()
        for cizgi in cizgiler {
            guard let ilk = cizgi.first else { continue }
            yol.move(to: ilk)
            if cizgi.count == 1 {
                yol.addLine(to: CGPoint(x: ilk.x + 0.5, y: ilk.y + 0.5))
            } else {
                for n in cizgi.dropFirst() { yol.addLine(to: n) }
            }
        }
        return yol
    }
}

// MARK: - Uzaktan imza bağlantısı

struct DVBUzaktanOnamView: View {
    let hastaId: Int
    let ad: String
    let sablonlar: [DVBOnamSablonu]
    let gizliHasta: Bool
    var gonderildi: () -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var seciliId: Int
    @State private var kanal = "whatsapp"
    @State private var gun = 7
    @State private var gizliNumaraOnay = false
    @State private var calisiyor = false
    @State private var hata: String?
    @State private var sonucMesaji: String?
    @State private var baglanti: String?
    @State private var paylasilan: DVBOnamPaylasimOgesi?
    @State private var kopyalandi = false

    init(hastaId: Int, ad: String, sablonlar: [DVBOnamSablonu], gizliHasta: Bool, gonderildi: @escaping () -> Void) {
        self.hastaId = hastaId
        self.ad = ad
        self.sablonlar = sablonlar
        self.gizliHasta = gizliHasta
        self.gonderildi = gonderildi
        _seciliId = State(initialValue: sablonlar.first?.id ?? 0)
    }

    private var gonderildiMi: Bool { baglanti != nil }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Onam metni", selection: $seciliId) {
                        ForEach(sablonlar) { s in Text(s.title).tag(s.id) }
                    }
                    Picker("Gönderim", selection: $kanal) {
                        Text("WhatsApp").tag("whatsapp")
                        Text("E-posta").tag("email")
                        Text("Bağlantı").tag("link")
                    }
                    .pickerStyle(.segmented)
                    Picker("Geçerlilik", selection: $gun) {
                        Text("3 gün").tag(3)
                        Text("7 gün").tag(7)
                        Text("14 gün").tag(14)
                    }
                } header: {
                    Text(ad)
                } footer: {
                    Text(kanalAciklamasi)
                }
                .disabled(gonderildiMi)

                if gizliHasta && kanal == "whatsapp" {
                    Section {
                        Toggle("Gizli numaraya WhatsApp gönderilsin", isOn: $gizliNumaraOnay)
                    } footer: {
                        Text("Bu hasta gizli kayıtlı; numarası maskeli tutuluyor. İşaretlemezseniz yalnız bağlantı üretilir, siz iletirsiniz.")
                    }
                    .disabled(gonderildiMi)
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }

                if let baglanti {
                    Section {
                        if let m = sonucMesaji {
                            Text(m).font(.subheadline)
                        }
                        Text(baglanti)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = baglanti
                            kopyalandi = true
                        } label: {
                            Label(kopyalandi ? "Kopyalandı" : "Bağlantıyı kopyala", systemImage: kopyalandi ? "checkmark" : "doc.on.doc")
                        }
                        Button {
                            paylasilan = DVBOnamPaylasimOgesi(metin: baglanti)
                        } label: {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("İmza bağlantısı")
                    } footer: {
                        Text("Bağlantı tek kullanımlıktır; hasta imzalayınca onam bu hastanın kartına düşer.")
                    }
                }
            }
            .navigationTitle("Uzaktan imza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(gonderildiMi ? "Kapat" : "Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await gonder() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Gönder").bold() }
                    }
                    .disabled(gonderildiMi || calisiyor || sablonlar.isEmpty)
                }
            }
            .sheet(item: $paylasilan) { DVBPaylasim(ogeler: [$0.metin]) }
        }
        .navigationViewStyle(.stack)
    }

    private var kanalAciklamasi: String {
        switch kanal {
        case "email":
            return "Bağlantı hastanın e-posta adresine gider. E-postası yoksa yalnız bağlantı üretilir; kopyalayıp kendiniz iletebilirsiniz."
        case "link":
            return "Yalnız bağlantı üretilir; kopyalayıp ya da paylaşarak hastaya kendiniz iletirsiniz."
        default:
            return "Bağlantı hastanın WhatsApp numarasına gider. WhatsApp ile gönderilemezse e-postaya, o da yoksa yalnız bağlantıya düşer."
        }
    }

    private func gonder() async {
        guard let token = session.token, !calisiyor, seciliId != 0 else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "consent_template_id": seciliId,
            "channel": kanal,
            "days": gun,
        ]
        if gizliHasta && kanal == "whatsapp" { govde["private_phone_ok"] = gizliNumaraOnay }
        do {
            let c: DVBOnamGonderCevabi = try await DVBAPI.shared.post("my/doctor/patients/\(hastaId)/consents/send", body: govde, token: token)
            hata = nil
            sonucMesaji = c.message
            baglanti = c.url ?? ""
            gonderildi()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
