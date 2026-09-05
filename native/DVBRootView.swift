import SwiftUI

/// Tur 235 — Uygulamanın native kökü.
///
/// App Store 4.2'nin cevabı buradan başlıyor: uygulama artık siteyi açan bir kabuk
/// değil, kendi gezinme yapısı olan native bir istemci. Web içeriği yalnız gerçekten
/// web olması gereken yerlerde (hekim paneli, yasal metinler) kullanılır.
struct DVBRootView: View {

    @StateObject private var session = DVBSession()

    /// DVB-000111 — biyometrik kilit. Varsayılan kapalı; kullanıcı Hesabım'dan açar.
    @StateObject private var lock = DVBBiometricLock()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Tur 241 — CI'da mağaza görüntüsü alınırken kök devralınır (bkz. DVBScreenshot.swift).
        // Argüman yalnız Codemagic'ten gelir; normal kullanımda bu dal HİÇ çalışmaz.
        if let ekran = DVBScreenshotMode.ekran {
            DVBScreenshotHost(ekran: ekran, slug: DVBScreenshotMode.slug)
        } else {
            sekmeler
        }
    }

    private var sekmeler: some View {
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
        .environmentObject(lock)
        .task { await session.restore() }
        // DVB-000111 — kilit perdesi EN DIŞTA: sekme çubuğu dahil her şeyi örtmeli.
        .dvbKilit(lock)
        // ⚠ TEK PARAMETRELİ onChange BİLEREK: iki parametreli biçim (oldValue, newValue)
        // iOS 17+ İSTER. Projenin deployment target'ı Capacitor şablonundan geliyor ve
        // depoda sabitlenmiş değil; daha düşükse iki parametreli biçim DERLEME HATASI verir.
        // Tek parametreli biçim iOS 17'de yalnızca "deprecated" uyarısı üretir — uyarı
        // derlemeyi durdurmaz, hata durdurur. Bilinmeyen hedefte uyarıyı seçiyoruz.
        .onChange(of: scenePhase) { yeni in
            // Uygulama arka plana veya görev değiştiriciye geçtiğinde yeniden kilitle.
            // .inactive de dahil: görev değiştirici önizlemesi ekranın fotoğrafını çeker.
            if yeni != .active { lock.arkaPlanaGitti() }
        }
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

/// Tur 241 — Randevu saatleri KLİNİK saatiyle gösterilir.
///
/// Sunucu slotları doğru ofsetle gönderiyor ("…T11:00:00+03:00"), ama `DateFormatter`
/// timeZone verilmezse CİHAZIN saat dilimine göre yazar. Türkiye'deki bir hastada
/// sonuç doğru çıkıyor; yurt dışındaki cihazda (ve UTC'de çalışan CI simülatöründe)
/// aynı randevu kayıyor — web hep Türkiye saatini gösterdiği için site ile uygulama
/// birbirini tutmuyordu. Muayene saati klinik yerel saatidir: sabitliyoruz.
enum DVBTime {
    static let klinik: TimeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
}

extension Date {
    /// "1 Ağustos 2026, 11:00" — hasta için okunur; saat KLİNİK saati (bkz. DVBTime).
    var dvbLong: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "d MMMM yyyy, HH:mm"
        return f.string(from: self)
    }
}
