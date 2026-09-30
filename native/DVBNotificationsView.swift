import SwiftUI

/// Tur 235 — Bildirim merkezi.
///
/// Push ile bu liste AYRI şeylerdir: push kaçabilir (uygulama kapalı, izin yok,
/// cihaz çevrimdışı), burası kalıcı geçmiştir. Sekme rozeti sunucudan gelen
/// `meta.unread` ile beslenir.
@MainActor
struct DVBNotificationsView: View {

    @EnvironmentObject private var session: DVBSession

    @State private var items: [DVBNotification] = []
    @State private var loading = false
    @State private var error: String?
    @State private var openURL: URL?
    /// DVB-000272 — hekim bildirimi yerli ekrana gidiyorsa.
    @State private var hedefSunumu: DVBHedefSunumu?

    /// DVB-000272 — hekim hesabı: panel ZİLİ kümesi (mesaj bildirimleri Gelen Kutusu'nda) + yerli hedefler.
    private var hekimModu: Bool { session.hekim != nil }

    var body: some View {
        NavigationView {
            Group {
                if !session.isLoggedIn {
                    DVBLoginGate(title: "Bildirimleriniz için giriş yapın")
                } else if loading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, items.isEmpty {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Bildirimler alınamadı", message: error) {
                        Task { await load() }
                    }
                } else if items.isEmpty {
                    DVBStateView(icon: "bell", title: "Bildiriminiz yok")
                } else {
                    List(items) { n in
                        Button { Task { await open(n) } } label: { row(n) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Bildirimler")
            .toolbar {
                if session.isLoggedIn && session.unreadCount > 0 {
                    Button("Tümünü okundu") { Task { await readAll() } }
                }
            }
            .task { await load() }
            .sheet(item: Binding(
                get: { openURL.map { DVBIdentifiableURL(url: $0) } },
                set: { openURL = $0?.url }
            )) { wrapper in
                DVBWebSheet(url: wrapper.url, title: "Doktorumveben")
            }
        }
        .navigationViewStyle(.stack)
        // İkinci sayfa DIŞ görünümde: aynı görünüme iki `sheet` bağlamak eski iOS sürümlerinde birini susturuyordu.
        .sheet(item: $hedefSunumu, onDismiss: { Task { await load() } }) { s in
            DVBHekimHedefSayfasi(hedef: s.hedef).environmentObject(session)
        }
    }

    private func row(_ n: DVBNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(n.isRead == true ? Color.clear : DVBTheme.brand)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title ?? "—")
                    .font(.subheadline.weight(n.isRead == true ? .regular : .semibold))
                if let body = n.body, !body.isEmpty {
                    Text(body).font(.footnote).foregroundColor(.secondary)
                }
                if let created = n.createdAt {
                    Text(created.dvbLong).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard session.isLoggedIn, let token = session.token else { items = []; return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let page: DVBNotificationPage = try await DVBAPI.shared.get(hekimModu ? "my/doctor/notifications" : "my/notifications", token: token)
            items = page.data
            session.unreadCount = page.meta?.unread ?? 0
        } catch DVBError.unauthorized {
            session.signOut()
        } catch {
            // DVB-000264 — İPTAL (sekme değişimi/yeniden çizim) hata DEĞİL: ekrandakini koru, "internet yok" deme.
            guard let mesaj = DVBError.mesaj(error) else { return }
            items = []
            self.error = mesaj
        }
    }

    private func open(_ n: DVBNotification) async {
        guard let token = session.token else { return }
        if n.isRead != true {
            if hekimModu {
                if let r: DVBHekimOkunduCevabi = try? await DVBAPI.shared.post(
                    "my/doctor/notifications/\(n.id)/read", token: token
                ) {
                    session.unreadCount = r.meta?.unread ?? session.unreadCount
                    if let i = items.firstIndex(where: { $0.id == n.id }) { items[i] = n.okunmus }
                }
            } else if let page: DVBNotificationReadResponse = try? await DVBAPI.shared.post(
                "my/notifications/\(n.id)/read", token: token
            ) {
                session.unreadCount = page.meta?.unread ?? session.unreadCount
                if let i = items.firstIndex(where: { $0.id == n.id }) { items[i] = page.data }
            }
        }
        // DVB-000272 — hekim bildirimi: bilinen hedef yerli ekranda (panel oturumu uygulamada yok).
        if hekimModu, let hedef = n.target {
            hedefSunumu = DVBHedefSunumu(hedef: hedef)
            return
        }
        if let raw = n.url, let url = URL(string: raw, relativeTo: DVBConfig.webBase)?.absoluteURL {
            openURL = url
        }
    }

    private func readAll() async {
        guard let token = session.token else { return }
        // DVB-000272 — hekimde panel "Tümünü okundu" ile aynı: mesaj bildirimleri sohbet açılınca düşer.
        let _: DVBMessage? = try? await DVBAPI.shared.post(hekimModu ? "my/doctor/notifications/read-all" : "my/notifications/read-all", token: token)
        await load()
    }
}

struct DVBNotificationReadResponse: Decodable {
    let data: DVBNotification
    let meta: DVBNotificationPage.Meta?
}

/// DVB-000272 — hekim bildirim okundu yanıtı (yalnız zil sayacı).
struct DVBHekimOkunduCevabi: Decodable {
    let meta: DVBNotificationPage.Meta?
}

extension DVBNotification {
    var okunmus: DVBNotification {
        DVBNotification(id: id, type: type, title: title, body: body, url: url, isRead: true, createdAt: createdAt, target: target)
    }
}

struct DVBIdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
