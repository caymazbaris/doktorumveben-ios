import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000286 — HEKİMİN TAKVİM EKRANI.
//
// Kullanıcı (2 Eki 2026): "google takvim hatası var ona tıklayınca bu bölüm hesabınızda etkin değil gibi bi uyarı
// geliyor bunu düzenle google ve apple takvim senkronu da yapabilir olsun"; 6 Eki: "yap bunu da ekle".
//
// Kurallar sunucuda (HekimTakvimApiController, web takvim sayfasıyla aynı): uygulama durumu GÖSTERİR ve ELLE EŞİTLER.
// · Apple Takvim: hekimin ICS akışına `webcal://` ile tek dokunuşla abonelik (iOS kendi sorar, kendisi yeniler).
// · Google Takvim: izin SAFARİ'de verilir (Google gömülü web görünümünde OAuth'a izin vermez); Safari tek kullanımlık
//   giriş adresiyle (DVB-000273 köprüsü) panelin Google bağlantı adımına gider. Dönünce ekran kendini yeniler.
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

    enum CodingKeys: String, CodingKey {
        case enabled, message, feeds, connections
        case googleAvailable = "google_available"
        case googlePath = "google_path"
        case managePath = "manage_path"
    }
}

private struct DVBTakvimEsitlemeCevabi: Decodable {
    let ok: Bool
    let message: String
    let connection: DVBTakvimDurumu.Baglanti
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
        // Safari'de Google bağlandıktan sonra uygulamaya dönülünce durum tazelensin.
        .onChange(of: scenePhase) { yeni in
            if yeni == .active { Task { await yukle() } }
        }
        .alert("Takvim", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
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
                    ForEach(d.connections) { baglantiSatiri($0) }
                }
            } header: {
                Text("Bağlı takvimler")
            } footer: {
                Text("Bağlı takvimdeki dolu saatleriniz randevuya kapanır; yeni randevularınız o takvime yazılır.")
            }

            if d.googleAvailable == true, let yol = d.googlePath {
                Section {
                    Button {
                        Task { await safarideAc(yol) }
                    } label: {
                        HStack {
                            Label(d.connections.contains(where: { $0.provider == "google" }) ? "Google Takvim'i yeniden bağla" : "Google Takvim'i bağla",
                                  systemImage: "link")
                            if safariHazirlaniyor { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(safariHazirlaniyor)
                } footer: {
                    Text("Google izni güvenlik gereği Safari'de verilir. Bağladıktan sonra uygulamaya dönün; durum burada güncellenir.")
                }
            }

            if let yol = d.managePath {
                Section {
                    Button {
                        Task { await safarideAc(yol) }
                    } label: {
                        Label("Diğer ayarlar (Outlook, iCloud, takvim kaldırma)", systemImage: "safari")
                    }
                    .disabled(safariHazirlaniyor)
                }
            }
        }
        .refreshable { await yukle() }
    }

    private func baglantiSatiri(_ b: DVBTakvimDurumu.Baglanti) -> some View {
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
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
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
