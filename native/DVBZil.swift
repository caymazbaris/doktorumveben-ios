import SwiftUI

/// DVB-000264 — BİLDİRİMLER ARTIK SEKME DEĞİL, ZİL.
///
/// Kullanıcı (30 Eyl 2026, gerçek iPhone): "altta bildirimler sekmesi çok yersiz". Alt çubukta dört sekmeden biri
/// yalnız bir listeye ayrılmıştı. Bildirimler artık arama ekranının başlığındaki rozetli zilden ve Hesabım'dan açılır
/// (sayfa olarak — `DVBNotificationsView` kendi NavigationView'ını kurduğu için içe itilmez, çift başlık olurdu).
struct DVBZilDugmesi: View {
    @EnvironmentObject private var session: DVBSession
    @State private var acik = false

    var body: some View {
        Button {
            acik = true
        } label: {
            if session.unreadCount > 0 {
                Image(systemName: "bell.badge")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.red, DVBTheme.brand)
            } else {
                Image(systemName: "bell")
            }
        }
        .accessibilityLabel(session.unreadCount > 0
                            ? "Bildirimler, \(session.unreadCount) okunmamış"
                            : "Bildirimler")
        .sheet(isPresented: $acik, onDismiss: { Task { await session.okunmamisiYenile() } }) {
            DVBNotificationsView().environmentObject(session)
        }
        .task { await session.okunmamisiYenile() }
    }
}

extension DVBSession {
    /// Okunmamış bildirim sayısı. Eskiden yalnız Bildirimler SEKMESİ açılınca güncelleniyordu; sekme kalkınca zil
    /// rozeti bayat kalırdı. Hata/iptal sessiz: rozet bir süre eski sayıyı gösterir, ekran hata vermez.
    func okunmamisiYenile() async {
        guard let token else { unreadCount = 0; return }
        // DVB-000272 — hekimde zil = panel zili kümesi (mesaj bildirimleri Gelen Kutusu rozetinde).
        let yol = hekim != nil ? "my/doctor/notifications" : "my/notifications"
        if let sayfa: DVBNotificationPage = try? await DVBAPI.shared.get(yol, query: ["limit": "1"], token: token) {
            unreadCount = sayfa.meta?.unread ?? 0
        }
    }
}
