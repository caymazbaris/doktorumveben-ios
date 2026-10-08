import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000341 — HASTA TALEPLERİ (hekim).
//
// Kullanıcı (8 Eki 2026): "sitede olup ios app te olmayan diğer sayfa ve özellikleri de ekleyelim" → "3 günlük işleri de
// yapalm" (hasta talepleri, çalışma saatleri ve izinler, hizmetler, randevu taşıma).
//
// Web /panel/hasta-talepleri ile AYNI (HekimIsleriApiController): yalnız yönetici onaylı TALEP ERİŞİMİ olan hekimde açılır
// (DVB-000270 kararı: site talepleri merkezde kalır). Son 90 gün; açık talepler üstte. Hekim hastayı arar/yazar ve talebi
// "Görüşüldü / Tekrar aranacak / Kapat" diye işaretler. Talebi randevuya çevirmek için Ajanda'daki "Randevu ekle" kullanılır.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBHastaTalepleri: Decodable {
    let enabled: Bool
    let message: String?
    let statuses: [Secenek]?
    let waCategories: [Secenek]?
    let site: [SiteTalebi]
    let whatsapp: [WaTalebi]

    struct Secenek: Decodable, Hashable {
        let key: String
        let label: String
    }

    struct SiteTalebi: Decodable, Identifiable {
        let id: Int
        let refCode: String
        let name: String
        let topicLabel: String?
        let subject: String?
        let note: String?
        let status: String
        let statusLabel: String?
        let isOpen: Bool
        let createdAt: Date?
        let preferredDate: String?
        let preferredSlot: String?
        let service: String?
        let phone: String?
        let whatsappUrl: String?
        let email: String?
        let mhrsNotice: Bool?
        let appointment: Randevu?

        struct Randevu: Decodable {
            let no: String?
            let startsAt: Date?

            enum CodingKeys: String, CodingKey {
                case no
                case startsAt = "starts_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, subject, note, status, service, phone, email, appointment
            case refCode = "ref_code"
            case topicLabel = "topic_label"
            case statusLabel = "status_label"
            case isOpen = "is_open"
            case createdAt = "created_at"
            case preferredDate = "preferred_date"
            case preferredSlot = "preferred_slot"
            case whatsappUrl = "whatsapp_url"
            case mhrsNotice = "mhrs_notice"
        }
    }

    struct WaTalebi: Decodable, Identifiable {
        let id: Int
        let name: String
        let typeLabel: String?
        let message: String?
        let matchedAt: Date?
        let preferredAt: Date?
        let handled: Bool
        let handledLabel: String?
        let phone: String?
        let whatsappUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, name, message, handled, phone
            case typeLabel = "type_label"
            case matchedAt = "matched_at"
            case preferredAt = "preferred_at"
            case handledLabel = "handled_label"
            case whatsappUrl = "whatsapp_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case enabled, message, statuses, site, whatsapp
        case waCategories = "wa_categories"
    }
}

private struct DVBTalepIslemCevabi: Decodable {
    let ok: Bool
    let message: String?
}

struct DVBHastaTalepleriView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var veri: DVBHastaTalepleri?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var calisan: String?

    var body: some View {
        Group {
            if let v = veri {
                if v.enabled { liste(v) } else {
                    DVBStateView(icon: "tray", title: "Hasta talepleri kapalı",
                                 message: v.message ?? "Hasta talepleri bu hesapta açık değil.")
                }
            } else if let hata {
                DVBStateView(icon: "exclamationmark.triangle", title: "Talepler alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Hasta talepleri")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .alert("Hasta talepleri", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
    }

    private func liste(_ v: DVBHastaTalepleri) -> some View {
        List {
            Section {
                if v.site.isEmpty {
                    Text("Son 90 günde siteden gelen talep yok.").foregroundColor(.secondary)
                } else {
                    ForEach(v.site) { siteSatiri($0, durumlar: v.statuses ?? []) }
                }
            } header: {
                Text("Siteden gelen · son 90 gün")
            }

            Section {
                if v.whatsapp.isEmpty {
                    Text("Son 90 günde WhatsApp'tan gelen talep yok.").foregroundColor(.secondary)
                } else {
                    ForEach(v.whatsapp) { waSatiri($0, kategoriler: v.waCategories ?? []) }
                }
            } header: {
                Text("WhatsApp'tan gelen · son 90 gün")
            } footer: {
                Text("Talebi randevuya çevirmek için Ajanda'daki \"Randevu ekle\"yi kullanın.")
            }
        }
        .refreshable { await yukle() }
    }

    private func siteSatiri(_ t: DVBHastaTalepleri.SiteTalebi, durumlar: [DVBHastaTalepleri.Secenek]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                cip(t.statusLabel ?? t.status, renk: t.isOpen ? .orange : (t.status == "scheduled" ? DVBTheme.accent : .secondary))
            }
            if let k = t.topicLabel { Text(k).font(.caption).foregroundColor(DVBTheme.brand) }
            Text(ozet(t)).font(.caption).foregroundColor(.secondary)
            if let n = t.note, !n.isEmpty {
                Text(n).font(.caption).lineLimit(4)
            }
            if t.mhrsNotice == true {
                Text("Hastaya MHRS yönlendirmesi gösterildi").font(.caption2).foregroundColor(.orange)
            }
            if let r = t.appointment, let no = r.no {
                Text(randevuMetni(no, r.startsAt))
                    .font(.caption).foregroundColor(DVBTheme.accent)
            }
            HStack(spacing: 16) {
                if let tel = t.phone, let u = URL(string: "tel:\(tel.filter(\.isNumber))") {
                    Button { openURL(u) } label: { Label("Ara", systemImage: "phone") }
                }
                if let w = t.whatsappUrl, let u = URL(string: w) {
                    Button { openURL(u) } label: { Label("WhatsApp", systemImage: "message") }
                }
                if let e = t.email, !e.isEmpty, let u = URL(string: "mailto:\(e)") {
                    Button { openURL(u) } label: { Label("E-posta", systemImage: "envelope") }
                }
                Spacer(minLength: 0)
                if t.isOpen && !durumlar.isEmpty {
                    Menu {
                        ForEach(durumlar, id: \.key) { d in
                            Button(d.label) { Task { await siteDurum(t.refCode, d.key) } }
                        }
                    } label: {
                        if calisan == t.refCode { ProgressView() } else { Label("İşaretle", systemImage: "checkmark.circle") }
                    }
                    .disabled(calisan != nil)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func waSatiri(_ l: DVBHastaTalepleri.WaTalebi, kategoriler: [DVBHastaTalepleri.Secenek]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                cip(l.handledLabel ?? (l.handled ? "İşlendi" : "Yanıt bekliyor"), renk: l.handled ? .secondary : .orange)
            }
            if let k = l.typeLabel { Text(k).font(.caption).foregroundColor(DVBTheme.brand) }
            Text(waOzet(l))
                .font(.caption).foregroundColor(.secondary)
            if let m = l.message, !m.isEmpty {
                Text(m).font(.caption).lineLimit(4)
            }
            HStack(spacing: 16) {
                if let tel = l.phone, let u = URL(string: "tel:+\(tel.filter(\.isNumber))") {
                    Button { openURL(u) } label: { Label("Ara", systemImage: "phone") }
                }
                if let w = l.whatsappUrl, let u = URL(string: w) {
                    Button { openURL(u) } label: { Label("WhatsApp", systemImage: "message") }
                }
                Spacer(minLength: 0)
                if !l.handled && !kategoriler.isEmpty {
                    Menu {
                        ForEach(kategoriler, id: \.key) { k in
                            Button(k.label) { Task { await waDurum(l.id, k.key) } }
                        }
                    } label: {
                        if calisan == "wa-\(l.id)" { ProgressView() } else { Label("İşaretle", systemImage: "checkmark.circle") }
                    }
                    .disabled(calisan != nil)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func cip(_ metin: String, renk: Color) -> some View {
        Text(metin).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(renk.opacity(0.15)).foregroundColor(renk)
            .clipShape(Capsule())
    }

    private func randevuMetni(_ no: String, _ baslangic: Date?) -> String {
        guard let baslangic else { return "Randevu " + no }
        return "Randevu " + no + " · " + DVBSaat.gun(baslangic, "d MMMM HH:mm")
    }

    private func waOzet(_ l: DVBHastaTalepleri.WaTalebi) -> String {
        var parcalar: [String] = []
        if let m = l.matchedAt { parcalar.append(DVBSaat.gun(m, "d MMMM yyyy, HH:mm")) }
        if let p = l.preferredAt { parcalar.append("tercih: " + DVBSaat.gun(p, "d MMMM, HH:mm")) }
        return parcalar.joined(separator: " · ")
    }

    private func ozet(_ t: DVBHastaTalepleri.SiteTalebi) -> String {
        var parcalar: [String] = []
        if let c = t.createdAt { parcalar.append(DVBSaat.gun(c, "d MMMM yyyy, HH:mm")) }
        if let g = t.preferredDate {
            var tercih = "tercih: " + g
            if let dilim = t.preferredSlot { tercih += " " + dilim }
            parcalar.append(tercih)
        }
        if let s = t.service { parcalar.append(s) }
        if let k = t.subject { parcalar.append(k) }
        return parcalar.joined(separator: " · ")
    }

    // MARK: - Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/patient-requests", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func siteDurum(_ ref: String, _ durum: String) async {
        guard let token = session.token, calisan == nil else { return }
        calisan = ref
        defer { calisan = nil }
        do {
            let c: DVBTalepIslemCevabi = try await DVBAPI.shared.post(
                "my/doctor/patient-requests/\(ref)/status", body: ["status": durum], token: token
            )
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func waDurum(_ id: Int, _ kategori: String) async {
        guard let token = session.token, calisan == nil else { return }
        calisan = "wa-\(id)"
        defer { calisan = nil }
        do {
            let c: DVBTalepIslemCevabi = try await DVBAPI.shared.post(
                "my/doctor/patient-requests/whatsapp/\(id)/status", body: ["category": kategori], token: token
            )
            bilgi = c.message
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}
