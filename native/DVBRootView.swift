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

    /// DVB-000109 (2 Eki 2026) — hasta hesabında da bilinen adresler yerli ekranda açılır.
    @State private var hastaHedefi: DVBHastaHedefSunumu?

    /// DVB-000109 — seçili sekme. Bildirim hedefi AYRI SAYFADA değil, ilgili sekmenin kendi gezinmesinde açılır.
    @State private var sekme: DVBSekme = .ara

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
        TabView(selection: $sekme) {
            // DVB-000267 — hekim hesabı: ilk sekme kendi ajandası. Hasta "Randevularım" hekimde anlamsız
            // (hekimin kendi hasta randevusu yoksa boş liste) — onun yerine Ajanda gelir.
            if let hekim = session.hekim {
                DVBHekimAjandaView()
                    .tabItem { Label("Ajanda", systemImage: "calendar.badge.clock") }
                    .tag(DVBSekme.ajanda)

                // DVB-000270 — sekmeler sunucunun `features` bilgisine göre (muhasebe görünümünde hasta bölümü yok).
                if hekim.hastalarAcik {
                    DVBHekimHastalarView()
                        .tabItem { Label("Hastalar", systemImage: "person.2") }
                        .tag(DVBSekme.hastalar)
                }

                // DVB-000272 — "Talepler" → "Gelen Kutusu" (Mesajlar · İptaller · Sorular); 5 sekme sınırı yüzünden Mesajlar
                // ayrı sekme değil. Rozet: okunmamış hasta mesajı + bekleyen iptal talebi.
                DVBHekimTaleplerView()
                    .tabItem { Label("Gelen Kutusu", systemImage: "tray") }
                    .badge((hekim.unreadMessages ?? 0) + (hekim.pendingCancels ?? 0))
                    .tag(DVBSekme.gelenKutusu)

                // DVB-000271 — web'deki Ödeme Linki / Tahsilatlarım ile aynı kapı (`features.payments`).
                if hekim.odemelerAcik {
                    DVBHekimTahsilatView()
                        .tabItem { Label("Tahsilat", systemImage: "creditcard") }
                        .tag(DVBSekme.tahsilat)
                }
            }

            // DVB-000271 — hekim modunda 5 sekme sınırı (Ajanda, Hastalar, Gelen Kutusu, Tahsilat, Hesabım): 6. sekme iOS'ta
            // "Diğer" menüsüne düşer ve Hesabım gizlenir. Hekim arama sekmesi yalnız sekme sayısı 6 olacaksa kalkar.
            if !(session.hekim?.odemelerAcik ?? false) || !(session.hekim?.hastalarAcik ?? false) {
                DVBSearchView()
                    .tabItem { Label("Ara", systemImage: "magnifyingglass") }
                    .tag(DVBSekme.ara)
            }

            if session.hekim == nil {
                DVBAppointmentsView()
                    .tabItem { Label("Randevularım", systemImage: "calendar") }
                    .tag(DVBSekme.randevular)
            }

            // DVB-000264 — Bildirimler sekmesi kaldırıldı (kullanıcı: "altta bildirimler sekmesi çok yersiz").
            // Bildirimler arama ekranının başlığındaki zilden ve Hesabım'dan açılır (DVBZil.swift).

            DVBAccountView()
                .tabItem { Label("Hesabım", systemImage: "person.crop.circle") }
                .tag(DVBSekme.hesabim)
        }
        // Hekim modu açılınca/kapanınca seçili sekme o moddaki ilk sekmeye geçer (seçim kaybolan sekmede kalmasın).
        .onChange(of: session.hekim != nil) { hekimMi in
            sekme = hekimMi ? .ajanda : .ara
        }
        .tint(DVBTheme.brand)
        // DVB-000109 — üçüncü sayfa da AYRI katmanda (aynı görünüme iki `sheet` eski iOS'ta birini susturuyordu).
        .sheet(item: $hastaHedefi) { s in
            DVBHastaHedefSayfasi(hedef: s.hedef).environmentObject(session).environmentObject(lock)
        }
        .environmentObject(session)
        .environmentObject(lock)
        .task {
            await session.restore()
            // DVB-000109 — soğuk açılışta bekleyen dokunuş: oturum (ve hekim modu) kurulduktan SONRA açılır.
            if let bilgi = DVBPush.bekleyenDokunus, let url = DVBPush.adres(bilgi) {
                DVBPush.bekleyenDokunus = nil
                await pushAc(url, hedef: DVBPush.hedef(bilgi))
            }
        }
        // DVB-000109 — bildirime dokunulunca payload'daki hedef (yoksa adres) açılır.
        .onReceive(NotificationCenter.default.publisher(for: DVBPush.acilacakURL)) { bildirim in
            guard let url = bildirim.object as? URL else { return }
            DVBPush.bekleyenDokunus = nil
            let hedef = bildirim.userInfo.flatMap { DVBPush.hedef($0) }
            Task { await pushAc(url, hedef: hedef) }
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
    func pushAc(_ url: URL, hedef: DVBHekimHedef? = nil) async {
        // DVB-000109 — sunucu hedefi payload'da gönderdiyse doğrudan yerli ekran. Hedef yalnız hekim adreslerinde
        // (/panel/...) konur; hekim modu henüz yüklenmemiş olsa da (soğuk açılış) oturum varsa açılır.
        if let hedef, session.isLoggedIn {
            hekimHedefineGit(hedef)
            return
        }
        if session.hekim != nil, let token = session.token,
           let sayfa: DVBNotificationPage = try? await DVBAPI.shared.get("my/doctor/notifications", query: ["limit": "30"], token: token),
           let hedef = sayfa.data.first(where: { n in
               guard let raw = n.url, let adres = URL(string: raw, relativeTo: DVBConfig.webBase) else { return false }
               return adres.path == url.path
           })?.hedef {
            hekimHedefineGit(hedef)
            return
        }
        // DVB-000109 — Kullanıcı (2 Eki 2026): "bildirimde mesaj içeriği de gönder ona tıklayınca onla ilgili yere
        // gitsin". Hasta bildirimi web sayfası açıyordu; iki adımlı doğrulaması açık hesapta oturum köprüsü bilerek
        // açılmadığı için sayfa giriş ekranına düşüyor, içerik görünmüyordu. Bilinen adres yerli ekranda açılır.
        if session.hekim == nil, let hedef = DVBHastaHedefi(url: url) {
            // Sekmesi olan hedef kendi sekmesinde açılır; bildirim listesinin sekmesi yok → sayfa.
            switch hedef {
            case .randevular: sekme = .randevular
            case .hesabim:
                sekme = .hesabim
                // DVB-000352 — /hesabim/profil, /odemeler, /puanlarim… Hesabım'ın kökü değil, ilgili yerli ekran.
                DVBGezinme.shared.hastaHesapEkrani = DVBHastaHesapEkrani(yol: url.path)
            case .bildirimler: hastaHedefi = DVBHastaHedefSunumu(hedef: hedef)
            // DVB-000290 — hekimden gelen mesaj: Hesabım sekmesinde, Mesajlarım'dan açılmış gibi yerli sohbet.
            case .mesaj(let id):
                sekme = .hesabim
                DVBGezinme.shared.hastaSohbet = id
            case .mesajlar:
                sekme = .hesabim
                DVBGezinme.shared.hastaMesajlar = true
            }
            return
        }
        pushAdresi = DVBIdentifiableURL(url: url)
    }

    /// DVB-000109 — Kullanıcı (2 Eki 2026): "yine ayrı sayfa gibi açıyor doğrudan uygulamanın altındaki gelen kutusu
    /// tıkladığımdaki gibi görünmüyor". Hekim hedefi artık İLGİLİ SEKMEYE geçip o sekmenin gezinmesinde açılır (geri tuşu,
    /// sekme çubuğu aynı). Sekme bu hesapta yoksa (özellik kapalı) ya da hekim modu henüz yüklenmediyse eski davranış: sayfa.
    @MainActor
    func hekimHedefineGit(_ hedef: DVBHekimHedef) {
        guard let hekim = session.hekim else {
            pushHedefi = DVBHedefSunumu(hedef: hedef)
            return
        }
        let gezinme = DVBGezinme.shared
        switch hedef.screen {
        case "conversation":
            sekme = .gelenKutusu
            gezinme.gelenBolum = .mesajlar
            gezinme.sohbet = hedef.id
        case "messages":
            sekme = .gelenKutusu
            gezinme.gelenBolum = .mesajlar
        case "questions":
            sekme = .gelenKutusu
            gezinme.gelenBolum = .sorular
        case "patient" where hekim.hastalarAcik:
            sekme = .hastalar
            gezinme.hasta = hedef.id
        case "payments" where hekim.odemelerAcik:
            sekme = .tahsilat
        case "agenda":
            sekme = .ajanda
        // DVB-000286 — takvim bağlantıları (takvim hatası bildirimi): Hesabım sekmesinde yerli ekran.
        case "calendar" where hekim.readOnly != true:
            sekme = .hesabim
            gezinme.takvim = true
        default:
            pushHedefi = DVBHedefSunumu(hedef: hedef)
        }
    }
}

// MARK: - Sekmeler ve bildirimden gezinme (DVB-000109)

enum DVBSekme: Hashable {
    case ajanda, hastalar, gelenKutusu, tahsilat, ara, randevular, hesabim
}

/// Bildirimden gelen hedefin sekme İÇİNDE açılması için ortak istek kutusu. Kök görünüm sekmeyi seçip isteği yazar;
/// sekmedeki ekran isteği okuyup kendi gezinme yığınında açar ve isteği siler (bir kez açılır).
@MainActor
final class DVBGezinme: ObservableObject {
    static let shared = DVBGezinme()

    /// Gelen Kutusu'nda açılacak sohbet kimliği.
    @Published var sohbet: Int?
    /// Gelen Kutusu'nda seçilecek bölüm.
    @Published var gelenBolum: DVBGelenBolum?
    /// Hastalar sekmesinde açılacak hasta kartı kimliği.
    @Published var hasta: Int?
    /// DVB-000290 — hasta hesabı: Hesabım sekmesinde açılacak sohbet kimliği.
    @Published var hastaSohbet: Int?
    /// DVB-000290 — hasta hesabı: Hesabım sekmesinde Mesajlarım listesi açılsın.
    @Published var hastaMesajlar = false
    /// DVB-000286 — hekim hesabı: Hesabım sekmesinde takvim bağlantıları açılsın.
    @Published var takvim = false
    /// DVB-000352 — hasta hesabı: Hesabım sekmesinde açılacak yerli ekran (profil, ödemeler, puanlar, sigortalar…).
    @Published var hastaHesapEkrani: DVBHastaHesapEkrani?
}

// MARK: - Hasta bildirim hedefleri (DVB-000109)

/// Hasta bildirimlerinin adresi → uygulamanın yerli ekranı. Sunucu adresleri `route()` ile tam adres gönderir
/// (https://doktorumveben.com/hesabim/randevular); yalnız YOL bakılır. Eşlenmeyen adres web sayfası olarak açılır.
enum DVBHastaHedefi: Equatable {
    case randevular
    case bildirimler
    case hesabim
    /// DVB-000290 — hekimden mesaj (`/hesabim/mesaj/{sohbet}`) ve mesaj listesi (`/hesabim/mesajlar`).
    case mesaj(Int)
    case mesajlar

    init?(url: URL) {
        let yol = url.path.hasSuffix("/") && url.path.count > 1 ? String(url.path.dropLast()) : url.path
        if yol.hasPrefix("/hesabim/mesaj/"), let id = Int(yol.dropFirst("/hesabim/mesaj/".count)) {
            // Yalnız sayı: "/hesabim/mesaj/baslat/…" (POST ucu) sohbet sanılmasın.
            self = .mesaj(id)
        } else if yol == "/hesabim/mesajlar" {
            self = .mesajlar
        } else if yol == "/hesabim/randevular" || yol.hasPrefix("/hesabim/randevu/") {
            self = .randevular
        } else if yol == "/hesabim/bildirimler" {
            self = .bildirimler
        } else if yol == "/hesabim" || DVBHastaHesapEkrani(yol: yol) != nil {
            // DVB-000352 — eşleme listesi DVBHastaHesapEkrani'nda (puanlarım, sigorta, veri indirme dahil).
            self = .hesabim
        } else {
            return nil
        }
    }
}

/// `sheet(item:)` için kimlik: aynı hedef art arda iki bildirimde de açılabilsin.
struct DVBHastaHedefSunumu: Identifiable {
    let id = UUID()
    let hedef: DVBHastaHedefi
}

/// Bildirimden açılan yerli ekran. Her ekran kendi gezinme çubuğunu taşır; sayfa aşağı kaydırılarak kapanır.
struct DVBHastaHedefSayfasi: View {
    let hedef: DVBHastaHedefi

    var body: some View {
        switch hedef {
        case .randevular:
            DVBAppointmentsView()
        case .bildirimler:
            DVBNotificationsView()
        case .hesabim:
            DVBAccountView()
        case .mesaj(let id):
            NavigationView { DVBHekimSohbetView(sohbetId: id, ad: "Mesaj", hastaModu: true) }
                .navigationViewStyle(.stack)
        case .mesajlar:
            NavigationView { DVBHastaMesajlarView() }
                .navigationViewStyle(.stack)
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
