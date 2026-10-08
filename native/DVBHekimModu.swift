import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000267 — HEKİM MODU, 1. AŞAMA: RANDEVULAR VE TAKVİM.
//
// Kullanıcı (30 Eyl 2026): "doktor tarafı da ayrıca o şekilde olacak" → "tamam hekim tarafına geç". Öncelik sırası:
// randevular ve takvim → hastalar ve talepler → tahsilat ve ödeme linki → mesajlar ve bildirimler.
//
// Hekim hesabıyla giriş yapılınca uygulama hekim sekmelerine geçer (DVBRootView). Görünürlük ve işlemler sunucuda web
// paneliyle AYNI servislerden geçer; hangi düğmelerin görüneceği de sunucudan gelir (`actions`) — istemcide ikinci bir
// kural kopyası YOK.
//
// ⚠ Hasta adı/telefonu burada AÇIK (kilitli uygulama içi ekran). Ana ekran widget'ı bilerek MASKELİ; ikisi ayrı uçlar.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBHekimBilgisi: Decodable {
    let doctor: Hekim
    let isProvider: Bool?
    let billingOnly: Bool?
    let todayCount: Int?
    let pendingCancels: Int?
    /// DVB-000270 — muhasebe görünümü: randevular yalnız okunur, hasta bölümü kapalı.
    let readOnly: Bool?
    let features: Ozellikler?

    struct Ozellikler: Decodable {
        let patients: Bool?
        let questions: Bool?
        let payments: Bool?
        let messages: Bool?
        // DVB-000341 — hekimin günlük işleri (eski sunucuda yok → nil → gösterilmez).
        let patientRequests: Bool?
        let schedule: Bool?
        let services: Bool?
        // DVB-000343 — profil, muhasebe, e-Fatura.
        let profile: Bool?
        let accounting: Bool?
        let invoices: Bool?
        // DVB-000344 — fatura bilgilerim + banka hesabım.
        let billing: Bool?
        // DVB-000345 — kalan bölümler (Klinik yönetimi ekranı).
        let locations: Bool?
        let insurances: Bool?
        let bookingSettings: Bool?
        let bookingPage: Bool?
        let nps: Bool?
        let reports: Bool?
        let issues: Bool?
        let packages: Bool?
        let recurring: Bool?
        let accountingSetup: Bool?
        let incomingInvoices: Bool?
        let staff: Bool?
        let leads: Bool?
        let secretaries: Bool?

        enum CodingKeys: String, CodingKey {
            case patients, questions, payments, messages, schedule, services, profile, accounting, invoices, billing
            case locations, insurances, nps, reports, issues, packages, recurring, staff, leads, secretaries
            case patientRequests = "patient_requests"
            case bookingSettings = "booking_settings"
            case bookingPage = "booking_page"
            case accountingSetup = "accounting_setup"
            case incomingInvoices = "incoming_invoices"
        }
    }

    /// DVB-000272 — rozetler: görünen sohbetlerde okunmamış hasta mesajı / zil (mesaj bildirimleri hariç).
    let unreadMessages: Int?
    let unreadNotifications: Int?

    var mesajlarAcik: Bool { features?.messages ?? false }

    var hastalarAcik: Bool { features?.patients ?? false }
    var sorularAcik: Bool { features?.questions ?? false }
    var odemelerAcik: Bool { features?.payments ?? false }
    var taleplerAcik: Bool { features?.patientRequests ?? false }
    var calismaSaatleriAcik: Bool { features?.schedule ?? false }
    var hizmetlerAcik: Bool { features?.services ?? false }
    var profilAcik: Bool { features?.profile ?? false }
    var muhasebeAcik: Bool { features?.accounting ?? false }
    var faturalarAcik: Bool { features?.invoices ?? false }
    var odemeFaturaBilgileriAcik: Bool { features?.billing ?? false }
    /// DVB-000345 — "Klinik yönetimi" ekranında en az bir bölüm açık mı.
    var yonetimAcik: Bool {
        guard let f = features else { return false }
        return [f.locations, f.insurances, f.bookingSettings, f.bookingPage, f.nps, f.reports, f.issues, f.packages,
                f.recurring, f.accountingSetup, f.incomingInvoices, f.staff, f.leads, f.secretaries].contains { $0 == true }
    }

    struct Hekim: Decodable {
        let id: Int
        let name: String?
        let slug: String?
        let specialty: String?
        let avatar: String?
    }

    enum CodingKeys: String, CodingKey {
        case doctor
        case isProvider = "is_provider"
        case billingOnly = "billing_only"
        case todayCount = "today_count"
        case pendingCancels = "pending_cancels"
        case readOnly = "read_only"
        case features
        case unreadMessages = "unread_messages"
        case unreadNotifications = "unread_notifications"
    }
}

struct DVBHekimRandevu: Decodable, Identifiable {
    let id: Int
    let appointmentNo: String?
    let startsAt: Date?
    let endsAt: Date?
    let status: String?
    let statusLabel: String?
    let channel: String?
    let paymentStatus: String?
    let isFirstVisit: Bool?
    let cancelRequested: Bool?
    let patientName: String?
    let patientPhone: String?
    let service: String?
    let actions: [String]?
    /// DVB-000341 — taşıma ekranı boş saatleri bu hizmetin süresiyle ister; online görüşmenin yönetici bağlantısı.
    let serviceId: Int?
    let onlineMeeting: DVBOnlineGorusme?
    // Yalnız detayda gelir.
    let notes: String?
    let cancelReason: String?
    let patientEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, status, channel, service, actions, notes
        case appointmentNo = "appointment_no"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case statusLabel = "status_label"
        case paymentStatus = "payment_status"
        case isFirstVisit = "is_first_visit"
        case cancelRequested = "cancel_requested"
        case patientName = "patient_name"
        case patientPhone = "patient_phone"
        case cancelReason = "cancel_reason"
        case patientEmail = "patient_email"
        case serviceId = "service_id"
        case onlineMeeting = "online_meeting"
    }

    /// DVB-000341 — taşınabilir mi (web ile aynı: yalnız etkin randevu; muhasebe görünümüne işlem sunulmaz → actions boş).
    var tasinabilir: Bool {
        guard let status, ["pending", "confirmed", "arrived"].contains(status) else { return false }
        return !(actions ?? []).isEmpty
    }

    /// Durum rengi — anlamsal (yeşil/turuncu/kırmızı), marka renginden ayrı.
    var durumRengi: Color {
        switch status {
        case "confirmed", "arrived": return DVBTheme.accent
        case "completed": return .secondary
        case "cancelled", "no_show": return .red
        default: return .orange   // pending
        }
    }
}

struct DVBHekimRandevuListesi: Decodable {
    let data: [DVBHekimRandevu]
}

private struct DVBHekimRandevuCevabi: Decodable {
    let appointment: DVBHekimRandevu
    let message: String?
}

enum DVBSaat {
    static func saat(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func gun(_ d: Date, _ bicim: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = DVBTime.klinik
        f.dateFormat = bicim
        return f.string(from: d)
    }

    /// Sunucu `from`/`to` için klinik gününü ister (yyyy-MM-dd).
    static func anahtar(_ d: Date) -> String { gun(d, "yyyy-MM-dd") }

    static var takvim: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DVBTime.klinik
        c.locale = Locale(identifier: "tr_TR")
        c.firstWeekday = 2   // Pazartesi
        return c
    }
}

/// İşlem düğmesi etiketleri — sunucudaki işlem adlarıyla BİREBİR.
private enum DVBHekimIslem {
    static func etiket(_ i: String) -> String {
        switch i {
        case "confirm": return "Onayla"
        case "arrive": return "Hasta geldi"
        case "complete": return "Tamamlandı"
        case "no-show": return "Gelmedi"
        case "cancel": return "İptal et"
        case "approve-cancel": return "İptal talebini onayla"
        case "paid-in-person": return "Elden ödendi"
        case "send-payment-link": return "Ödeme bağlantısını WhatsApp'tan gönder"
        default: return i
        }
    }

    static func simge(_ i: String) -> String {
        switch i {
        case "confirm": return "checkmark.circle"
        case "arrive": return "figure.walk"
        case "complete": return "checkmark.seal"
        case "no-show": return "person.fill.xmark"
        case "cancel": return "xmark.circle"
        case "approve-cancel": return "calendar.badge.minus"
        case "paid-in-person": return "banknote"
        case "send-payment-link": return "creditcard"
        default: return "circle"
        }
    }

    /// Geri alınamaz/hastaya bildirim gönderen işlemler onay ister.
    static func onayIster(_ i: String) -> Bool { ["cancel", "no-show", "approve-cancel", "send-payment-link"].contains(i) }

    /// Kırmızı çizilecek (geri alınamaz, randevuyu bozan) işlemler. Ödeme bağlantısı onay ister ama yıkıcı değildir.
    static func yikiciMi(_ i: String) -> Bool { ["cancel", "no-show", "approve-cancel"].contains(i) }

    /// Onay sorusunun açıklaması — hastaya mesaj giden işlemde ne olacağı açıkça yazılır.
    static func onayAciklamasi(_ i: String) -> String {
        i == "send-payment-link"
            ? "Hastaya Doktorum Ve Ben WhatsApp hattından ödeme bağlantısı gönderilir. Hasta bağlantıyı tarayıcıda açıp öder."
            : "Bu işlem hastaya bildirilebilir ve geri alınamaz."
    }
}

// MARK: - Ajanda

struct DVBHekimAjandaView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var seciliGun = DVBSaat.takvim.startOfDay(for: Date())
    @State private var haftaBasi = DVBSaat.takvim.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    @State private var randevular: [DVBHekimRandevu] = []
    @State private var yukleniyor = false
    @State private var hata: String?
    /// DVB-000289 — "Yeni randevu" formu (muhasebe görünümü randevu ekleyemez → düğme de yok).
    @State private var yeniRandevuAcik = false

    private var ekleyebilir: Bool { session.hekim.map { $0.readOnly != true } ?? false }

    private var hafta: [Date] {
        (0..<7).compactMap { DVBSaat.takvim.date(byAdding: .day, value: $0, to: haftaBasi) }
    }

    private var gununRandevulari: [DVBHekimRandevu] {
        randevular.filter { r in
            guard let s = r.startsAt else { return false }
            return DVBSaat.takvim.isDate(s, inSameDayAs: seciliGun)
        }
    }

    var body: some View {
        NavigationView {
            List {
                if let h = session.hekim {
                    Section {
                        HStack(spacing: 16) {
                            ozet("Bugün", "\(h.todayCount ?? 0) randevu", "calendar")
                            if let iptal = h.pendingCancels, iptal > 0 {
                                ozet("İptal talebi", "\(iptal)", "exclamationmark.circle")
                            }
                        }
                    }
                }

                Section {
                    haftaSeridi
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section {
                    if yukleniyor && randevular.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let hata, randevular.isEmpty {
                        DVBStateView(icon: "wifi.exclamationmark", title: "Ajanda alınamadı", message: hata) { Task { await yukle() } }
                    } else if gununRandevulari.isEmpty {
                        Text("Bu gün randevu yok.").foregroundColor(.secondary)
                        if ekleyebilir && seciliGun >= DVBSaat.takvim.startOfDay(for: Date()) {
                            Button { yeniRandevuAcik = true } label: {
                                Label("Bu güne randevu ekle", systemImage: "plus.circle")
                            }
                        }
                    } else {
                        ForEach(gununRandevulari) { r in
                            NavigationLink(destination: DVBHekimRandevuDetayView(randevuId: r.id, ozet: r) { Task { await yukle() } }) {
                                satir(r)
                            }
                        }
                    }
                } header: {
                    Text(DVBSaat.gun(seciliGun, "d MMMM EEEE"))
                }
            }
            .refreshable { await yukle(); await session.hekimiYukle() }
            .navigationTitle(session.hekim?.doctor.name ?? "Ajanda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { DVBZilDugmesi() }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Bugün") {
                        seciliGun = DVBSaat.takvim.startOfDay(for: Date())
                        haftaBasi = DVBSaat.takvim.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
                        Task { await yukle() }
                    }
                    if ekleyebilir {
                        Button { yeniRandevuAcik = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Yeni randevu")
                    }
                }
            }
            .task { await yukle() }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $yeniRandevuAcik) {
            DVBHekimRandevuEkleView(gun: seciliGun) { g in
                // Eklenen randevunun günü ajandada seçilsin: hekim kaydı hemen listede görür.
                seciliGun = DVBSaat.takvim.startOfDay(for: g)
                haftaBasi = DVBSaat.takvim.dateInterval(of: .weekOfYear, for: g)?.start ?? g
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func ozet(_ baslik: String, _ deger: String, _ simge: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: simge).foregroundColor(DVBTheme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(baslik).font(.caption).foregroundColor(.secondary)
                Text(deger).font(.subheadline.weight(.semibold))
            }
        }
    }

    private var haftaSeridi: some View {
        HStack(spacing: 4) {
            Button { haftaDegistir(-7) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).accessibilityLabel("Önceki hafta")
            ForEach(hafta, id: \.self) { g in
                let secili = DVBSaat.takvim.isDate(g, inSameDayAs: seciliGun)
                let sayi = gunSayisi(g)
                Button { seciliGun = g } label: {
                    VStack(spacing: 3) {
                        Text(DVBSaat.gun(g, "EEE")).font(.caption2)
                        Text(DVBSaat.gun(g, "d")).font(.headline)
                        Circle().fill(sayi > 0 ? (secili ? Color.white : DVBTheme.brand) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(secili ? DVBTheme.brand : Color.clear)
                    .foregroundColor(secili ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(DVBSaat.gun(g, "d MMMM EEEE")), \(sayi) randevu")
            }
            Button { haftaDegistir(7) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).accessibilityLabel("Sonraki hafta")
        }
    }

    /// Şeritteki nokta: o gün iptal olmayan randevu var mı.
    private func gunSayisi(_ g: Date) -> Int {
        randevular.filter { r in
            guard let s = r.startsAt, r.status != "cancelled" else { return false }
            return DVBSaat.takvim.isDate(s, inSameDayAs: g)
        }.count
    }

    private func satir(_ r: DVBHekimRandevu) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(DVBSaat.saat(r.startsAt)).font(.headline).monospacedDigit()
                Text(DVBSaat.saat(r.endsAt)).font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.patientName ?? "—").font(.subheadline.weight(.semibold))
                if let s = r.service { Text(s).font(.caption).foregroundColor(.secondary) }
                HStack(spacing: 6) {
                    Text(r.statusLabel ?? "").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(r.durumRengi.opacity(0.15)).foregroundColor(r.durumRengi)
                        .clipShape(Capsule())
                    if r.cancelRequested == true {
                        Text("İptal talebi").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15)).foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                    if r.channel == "online" {
                        Image(systemName: "video").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func haftaDegistir(_ gun: Int) {
        guard let yeni = DVBSaat.takvim.date(byAdding: .day, value: gun, to: haftaBasi) else { return }
        haftaBasi = yeni
        seciliGun = yeni
        Task { await yukle() }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        let son = DVBSaat.takvim.date(byAdding: .day, value: 6, to: haftaBasi) ?? haftaBasi
        do {
            let l: DVBHekimRandevuListesi = try await DVBAPI.shared.get(
                "my/doctor/appointments",
                query: ["from": DVBSaat.anahtar(haftaBasi), "to": DVBSaat.anahtar(son)],
                token: token
            )
            randevular = l.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Randevu detayı + işlemler

struct DVBHekimRandevuDetayView: View {
    let randevuId: Int
    /// Listeden gelen özet — detay yüklenene kadar ekran boş kalmasın.
    let ozet: DVBHekimRandevu
    var degisti: () -> Void = {}

    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var detay: DVBHekimRandevu?
    @State private var calisiyor = false
    @State private var mesaj: String?
    @State private var hata: String?
    @State private var onayBekleyen: String?
    @State private var iptalAcik = false
    @State private var iptalNedeni = ""
    /// DVB-000341 — randevu taşıma sayfası + online görüşme düğmesinin saatle güncellenmesi.
    @State private var tasimaAcik = false
    @State private var simdi = Date()
    let saatSayaci = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var r: DVBHekimRandevu { detay ?? ozet }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.patientName ?? "—").font(.title3.bold())
                    if let s = r.startsAt {
                        Text("\(DVBSaat.gun(s, "d MMMM EEEE")) · \(DVBSaat.saat(r.startsAt))–\(DVBSaat.saat(r.endsAt))")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(r.statusLabel ?? "").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(r.durumRengi.opacity(0.15)).foregroundColor(r.durumRengi)
                            .clipShape(Capsule())
                        if r.cancelRequested == true {
                            Text("Hasta iptal istiyor").font(.caption.weight(.semibold)).foregroundColor(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Randevu") {
                if let s = r.service { bilgi("Hizmet", s) }
                bilgi("Görüşme", r.channel == "online" ? "Online" : "Yüz yüze")
                if r.isFirstVisit == true { bilgi("İlk gelişi", "Evet") }
                bilgi("Ödeme", r.paymentStatus == "paid" ? "Ödendi" : "Ödenmedi")
                if let no = r.appointmentNo { bilgi("Randevu no", no) }
                if let n = detay?.notes, !n.isEmpty { bilgi("Not", n) }
                if let c = detay?.cancelReason, !c.isEmpty { bilgi("İptal nedeni", c) }
            }

            // DVB-000341 — hekim online görüşmeyi telefondan yönetir. Kullanıcı (8 Eki 2026): "online görüşmeyi mobilden de
            // yapılabilsin doktor". Yönetici bağlantısı Safari'de açılır; hasta bekleme odasına gelince "İçeri al" denir.
            if let g = r.onlineMeeting, !g.bittiMi(simdi), let url = URL(string: g.joinUrl) {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        Label(g.acikMi(simdi) ? "Görüşmeyi başlat" : "Görüşme odasını aç", systemImage: "video.fill")
                            .font(.body.weight(.semibold))
                    }
                    if !g.acikMi(simdi), let acilis = g.opensAt {
                        Text("Odanın açılış saati: \(DVBOnlineSaat.saat(acilis)). Hastaya 15 dakika kala bağlantı gider.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Online görüşme")
                } footer: {
                    Text(g.hint ?? "Hastanız bekleme odasına geldiğinde görüşme ekranındaki bildirimden \"İçeri al\" ile kabul edin.")
                }
            }

            if r.tasinabilir {
                Section {
                    Button {
                        tasimaAcik = true
                    } label: {
                        Label("Randevuyu taşı", systemImage: "calendar.badge.clock")
                    }
                    .disabled(calisiyor)
                } footer: {
                    Text("Yeni gün ve saat seçin; hastaya bilgi gider.")
                }
            }

            if let tel = r.patientPhone, !tel.isEmpty {
                Section("Hastaya ulaş") {
                    Button { if let u = URL(string: "tel:+\(tel.filter(\.isNumber))") { openURL(u) } } label: {
                        Label("Ara", systemImage: "phone")
                    }
                    Button { if let u = URL(string: "https://wa.me/\(tel.filter(\.isNumber))") { openURL(u) } } label: {
                        Label("WhatsApp'tan yaz", systemImage: "message")
                    }
                }
            }

            if let islemler = r.actions, !islemler.isEmpty {
                Section {
                    ForEach(islemler, id: \.self) { i in
                        Button(role: DVBHekimIslem.yikiciMi(i) ? .destructive : nil) {
                            if i == "cancel" { iptalAcik = true }
                            else if DVBHekimIslem.onayIster(i) { onayBekleyen = i }
                            else { Task { await uygula(i) } }
                        } label: {
                            Label(DVBHekimIslem.etiket(i), systemImage: DVBHekimIslem.simge(i))
                        }
                        .disabled(calisiyor)
                    }
                } header: {
                    Text("İşlemler")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let mesaj { Text(mesaj).foregroundColor(DVBTheme.accent) }
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
        }
        .navigationTitle("Randevu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .onReceive(saatSayaci) { simdi = $0 }
        .sheet(isPresented: $tasimaAcik) {
            DVBHekimTasimaView(randevu: r) { m in
                mesaj = m
                hata = nil
                Task {
                    await yukle()
                    degisti()
                    await session.hekimiYukle()
                }
            }
            .environmentObject(session)
        }
        .alert(onayBekleyen.map { DVBHekimIslem.etiket($0) + "?" } ?? "",
               isPresented: Binding(get: { onayBekleyen != nil }, set: { if !$0 { onayBekleyen = nil } })) {
            Button("Vazgeç", role: .cancel) { onayBekleyen = nil }
            Button("Evet", role: DVBHekimIslem.yikiciMi(onayBekleyen ?? "") ? .destructive : nil) {
                if let i = onayBekleyen { Task { await uygula(i) } }
                onayBekleyen = nil
            }
        } message: {
            Text(DVBHekimIslem.onayAciklamasi(onayBekleyen ?? ""))
        }
        .sheet(isPresented: $iptalAcik) {
            NavigationView {
                Form {
                    Section {
                        TextField("İptal nedeni (isteğe bağlı)", text: $iptalNedeni)
                    } footer: {
                        Text("Hastaya randevunun iptal edildiği bildirilir.")
                    }
                }
                .navigationTitle("Randevuyu iptal et")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { iptalAcik = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("İptal et", role: .destructive) {
                            iptalAcik = false
                            Task { await uygula("cancel", neden: iptalNedeni) }
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func bilgi(_ etiket: String, _ deger: String) -> some View {
        HStack(alignment: .top) {
            Text(etiket).foregroundColor(.secondary)
            Spacer()
            Text(deger).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHekimRandevuCevabi = try await DVBAPI.shared.get("my/doctor/appointments/\(randevuId)", token: token)
            detay = c.appointment
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func uygula(_ islem: String, neden: String = "") async {
        guard let token = session.token else { return }
        calisiyor = true; hata = nil; mesaj = nil
        defer { calisiyor = false }
        var govde: [String: Any] = [:]
        if !neden.trimmingCharacters(in: .whitespaces).isEmpty { govde["reason"] = neden }
        do {
            let c: DVBHekimRandevuCevabi = try await DVBAPI.shared.post(
                "my/doctor/appointments/\(randevuId)/\(islem)", body: govde, token: token
            )
            mesaj = c.message
            await yukle()   // notlar/iptal nedeni detayla birlikte gelir
            degisti()
            await session.hekimiYukle()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
