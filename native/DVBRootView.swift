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

    /// DVB-000109 — dokunulan bildirimin açtığı adres (web sayfası olarak).
    @State private var pushAdresi: DVBIdentifiableURL?

    /// DVB-000272 — hekim hesabında push dokunuşu yerli ekrana gidebilir.
    @State private var pushHedefi: DVBHedefSunumu?

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
            // DVB-000267 — hekim hesabı: ilk sekme kendi ajandası. Hasta "Randevularım" hekimde anlamsız
            // (hekimin kendi hasta randevusu yoksa boş liste) — onun yerine Ajanda gelir.
            if let hekim = session.hekim {
                DVBHekimAjandaView()
                    .tabItem { Label("Ajanda", systemImage: "calendar.badge.clock") }

                // DVB-000270 — sekmeler sunucunun `features` bilgisine göre (muhasebe görünümünde hasta bölümü yok).
                if hekim.hastalarAcik {
                    DVBHekimHastalarView()
                        .tabItem { Label("Hastalar", systemImage: "person.2") }
                }

                // DVB-000272 — "Talepler" → "Gelen Kutusu" (Mesajlar · İptaller · Sorular); 5 sekme sınırı yüzünden Mesajlar
                // ayrı sekme değil. Rozet: okunmamış hasta mesajı + bekleyen iptal talebi.
                DVBHekimTaleplerView()
                    .tabItem { Label("Gelen Kutusu", systemImage: "tray") }
                    .badge((hekim.unreadMessages ?? 0) + (hekim.pendingCancels ?? 0))

                // DVB-000271 — web'deki Ödeme Linki / Tahsilatlarım ile aynı kapı (`features.payments`).
                if hekim.odemelerAcik {
                    DVBHekimTahsilatView()
                        .tabItem { Label("Tahsilat", systemImage: "creditcard") }
                }
            }

            // DVB-000271 — hekim modunda 5 sekme sınırı (Ajanda, Hastalar, Gelen Kutusu, Tahsilat, Hesabım): 6. sekme iOS'ta
            // "Diğer" menüsüne düşer ve Hesabım gizlenir. Hekim arama sekmesi yalnız sekme sayısı 6 olacaksa kalkar.
            if !(session.hekim?.odemelerAcik ?? false) || !(session.hekim?.hastalarAcik ?? false) {
                DVBSearchView()
                    .tabItem { Label("Ara", systemImage: "magnifyingglass") }
            }

            if session.hekim == nil {
                DVBAppointmentsView()
                    .tabItem { Label("Randevularım", systemImage: "calendar") }
            }

            // DVB-000264 — Bildirimler sekmesi kaldırıldı (kullanıcı: "altta bildirimler sekmesi çok yersiz").
            // Bildirimler arama ekranının başlığındaki zilden ve Hesabım'dan açılır (DVBZil.swift).

            DVBAccountView()
                .tabItem { Label("Hesabım", systemImage: "person.crop.circle") }
        }
        .tint(DVBTheme.brand)
        .environmentObject(session)
        .environmentObject(lock)
        .task { await session.restore() }
        // DVB-000109 — bildirime dokunulunca payload'daki adres açılır.
        .onReceive(NotificationCenter.default.publisher(for: DVBPush.acilacakURL)) { bildirim in
            if let url = bildirim.object as? URL { Task { await pushAc(url) } }
        }
        .sheet(item: $pushAdresi) { DVBWebSheet(url: $0.url, title: "Doktorum Ve Ben") }
        // DVB-000111 — kilit perdesi EN DIŞTA: sekme çubuğu dahil her şeyi örtmeli.
        .dvbKilit(lock)
        // İkinci sayfa ayrı görünüm katmanında (aynı görünüme iki `sheet` eski iOS'ta birini susturuyordu).
        .sheet(item: $pushHedefi) { DVBHekimHedefSayfasi(hedef: $0.hedef).environmentObject(session).environmentObject(lock) }
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

extension DVBRootView {
    /// DVB-000272 — push adresini aç. Hekim hesabında hedef SUNUCUNUN eşlemesinden (bildirim listesindeki aynı adres)
    /// bulunur — istemcide adres→ekran kuralının ikinci kopyası yok. Bulunamazsa eskisi gibi web sayfası.
    @MainActor
    func pushAc(_ url: URL) async {
        if session.hekim != nil, let token = session.token,
           let sayfa: DVBNotificationPage = try? await DVBAPI.shared.get("my/doctor/notifications", query: ["limit": "30"], token: token),
           let hedef = sayfa.data.first(where: { n in
               guard let raw = n.url, let adres = URL(string: raw, relativeTo: DVBConfig.webBase) else { return false }
               return adres.path == url.path
           })?.target {
            pushHedefi = DVBHedefSunumu(hedef: hedef)
            return
        }
        pushAdresi = DVBIdentifiableURL(url: url)
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
