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
//
// DVB-000494/495 — ANA HATTAN (WhatsApp) GELEN TALEPLER HEKİME GÖSTERİLMEZ (kullanıcı, 24 Kas 2026: "doktorlar ana hatta geleni
// göremiyor"). "WhatsApp'tan gelen" bölümü, satırı ve işaretleme çağrısı kalktı; sunucu `whatsapp` alanını eski sürümler için
// boş liste olarak göndermeye devam eder, bu sürüm o alanı hiç okumaz. Site listesini sunucu süzer (AppointmentRequest::hekimeAcik).
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBHastaTalepleri: Decodable {
    let enabled: Bool
    let message: String?
    let statuses: [Secenek]?
    let site: [SiteTalebi]

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

    enum CodingKeys: String, CodingKey {
        case enabled, message, statuses, site
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
            } footer: {
                Text("WhatsApp'tan gelen talepleri merkez ekibimiz yürütür. Talebi randevuya çevirmek için Ajanda'daki \"Randevu ekle\"yi kullanın.")
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
                // DVB-000367 — kanonik 90… numara "+" olmadan aranıyordu (tel:905…, yurt içinde geçersiz).
                if let u = DVBTelefon.araAdresi(t.phone) {
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

    private func ozet(_ t: DVBHastaTalepleri.SiteTalebi) -> String {
        var parcalar: [String] = []
        if let c = t.createdAt { parcalar.append(DVBSaat.gun(c, "d MMMM yyyy, HH:mm")) }
        if let g = t.preferredDate {
            // DVB-000367 — sunucu tarihi "2026-10-15" diye yollar; ekranda web'deki gibi okunur: "15 Ekim · Sabah (…)".
            // Okunamazsa geldiği gibi yazılır.
            let ymd = String(g.prefix(10))
            let okunur = DVBGunMetni.yaz(ymd, "d MMMM")
            var tercih = "tercih: " + (okunur == ymd ? g : okunur)
            if let dilim = t.preferredSlot, !dilim.isEmpty { tercih += " · " + dilim }
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
}
