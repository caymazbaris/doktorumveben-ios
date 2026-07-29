import SwiftUI

/// Tur 235 — Uygulamanın native kökü.
///
/// App Store 4.2'nin cevabı buradan başlıyor: uygulama artık siteyi açan bir kabuk
/// değil, kendi gezinme yapısı olan native bir istemci. Web içeriği yalnız gerçekten
/// web olması gereken yerlerde (hekim paneli, yasal metinler) kullanılır.
struct DVBRootView: View {

    @StateObject private var session = DVBSession()

    var body: some View {
        TabView {
            DVBSearchView()
                .tabItem { Label("Ara", systemImage: "magnifyingglass") }

            DVBAppointmentsView()
                .tabItem { Label("Randevularım", systemImage: "calendar") }

            DVBNotificationsView()
                .tabItem { Label("Bildirimler", systemImage: "bell") }
                .badge(session.unreadCount)

            DVBAccountView()
                .tabItem { Label("Hesabım", systemImage: "person.crop.circle") }
        }
        .tint(DVBTheme.brand)
        .environmentObject(session)
        .task { await session.restore() }
    }
}

enum DVBTheme {
    /// Marka teali — ikon/açılış ekranıyla aynı (#0891B2).
    static let brand = Color(red: 0x08 / 255, green: 0x91 / 255, blue: 0xB2 / 255)
}

// MARK: - Ortak parçalar

/// Boş liste / hata durumları için tek görsel dil. Her ekranda ayrı ayrı
/// "yükleniyor…" yazmak yerine tek yerden.
struct DVBStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button("Tekrar dene", action: retry)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

/// Giriş gerektiren sekmelerde tekrar eden kapı.
struct DVBLoginGate: View {
    let title: String

    var body: some View {
        DVBStateView(
            icon: "lock",
            title: title,
            message: "Görmek için Hesabım sekmesinden giriş yapın."
        )
    }
}

extension Date {
    /// "1 Ağustos 2026, 11:00" — hasta için okunur, cihazın diline saygılı.
    var dvbLong: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy, HH:mm"
        return f.string(from: self)
    }
}
