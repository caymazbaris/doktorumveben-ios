import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000271 — HEKİM MODU, 3. AŞAMA: TAHSİLAT VE ÖDEME LİNKİ.
//
// Kullanıcı (30 Eyl 2026): "tamam tahsilat ve ödeme linki aşamasına geç ancak ödemeyi linki kesinlikle browserda
// açılır olsun onu unutma".
//
// ⛔ ÖDEME SAYFASI UYGULAMA İÇİNDE HİÇ ÇİZİLMEZ. Tek kapı `DVBOdemeAdresi`: ödeme adresleri sistem tarayıcısına
// (Safari) devredilir — bu ekrandaki "Tarayıcıda aç" düğmesi de, uygulama içi web görünümü (DVBWebSheet) de buradan
// geçer. Universal Link yok (sunucuda apple-app-site-association 404) → WhatsApp'tan gelen link zaten tarayıcıda açılır.
//
// ⛔ PARA (İksero §5.1): ekranda `1.500,50 ₺` (sunucunun ürettiği metin), sunucuya MAKİNE biçimi `1500.50`.
// "1.500" makinede 1,5 TL'dir — girdi `DVBPara.coz` ile çözülür, çözülemeyen girdi 0'a ÇEVRİLMEZ, gönderilmez.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Ödeme adresi kuralı (tek kapı)

enum DVBOdemeAdresi {
    /// Ödeme alınan / ödeme bilgisi gösterilen sayfalar (sunucu rotaları: pay.show, membership pay link,
    /// payment.create, payment.transfer, panel üyelik kart ödemesi).
    static func odemeSayfasiMi(_ url: URL) -> Bool {
        let host = url.host ?? ""
        guard host == "doktorumveben.com" || host.hasSuffix(".doktorumveben.com") else { return false }
        let yol = url.path
        return yol.hasPrefix("/ode/")
            || yol.hasPrefix("/uyelik-ode/")
            || yol.hasPrefix("/odeme/")
            || (yol.hasPrefix("/randevu/") && (yol.hasSuffix("/odeme") || yol.contains("/odeme/")))
            || yol.contains("/kart-odeme/")
    }

    /// Sistem tarayıcısında aç (uygulama içi web görünümü DEĞİL).
    static func tarayicidaAc(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - Para girişi

extension DVBPara {
    /// Kullanıcının yazdığı tutarı çözer (`1.500,50` · `1500,5` · `10.000` · `1500`). Sunucudaki `Para::coz` kuralı:
    /// iki ayraç varsa SONUNCUSU ondalık; tek tür ayraç birden çok kez geçiyorsa binlik; tek ayraç + ardından tam üç
    /// basamak → binlik, değilse ondalık. Çözülemezse nil (0 DEĞİL).
    static func coz(_ girdi: String) -> Decimal? {
        var s = girdi.replacingOccurrences(of: "₺", with: "")
            .replacingOccurrences(of: "TL", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }

        let noktaSayisi = s.filter { $0 == "." }.count
        let virgulSayisi = s.filter { $0 == "," }.count

        if noktaSayisi > 0 && virgulSayisi > 0 {
            let sonNokta = s.lastIndex(of: ".")!
            let sonVirgul = s.lastIndex(of: ",")!
            let ondalik: Character = sonNokta > sonVirgul ? "." : ","
            let binlik: Character = ondalik == "." ? "," : "."
            s = s.filter { $0 != binlik }
            s = s.replacingOccurrences(of: String(ondalik), with: ".")
        } else if noktaSayisi + virgulSayisi > 0 {
            let ayrac: Character = noktaSayisi > 0 ? "." : ","
            let adet = max(noktaSayisi, virgulSayisi)
            let parcalar = s.split(separator: ayrac, omittingEmptySubsequences: false)
            let ucluGruplar = parcalar.count > 1 && parcalar.dropFirst().allSatisfy { $0.count == 3 } && !(parcalar.first ?? "").isEmpty
            if adet > 1 {
                guard ucluGruplar else { return nil }
                s = s.filter { $0 != ayrac }
            } else if ucluGruplar {
                s = s.filter { $0 != ayrac }
            } else {
                s = s.replacingOccurrences(of: String(ayrac), with: ".")
            }
        }

        let parca = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parca.count <= 2, !(parca.first ?? "").isEmpty, (parca.count == 1 || (1...2).contains(parca[1].count)) else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Makine biçimi: `1500.50` (API, ödeme sağlayıcısı). Yerel ayardan BAĞIMSIZ.
    static func makine(_ tutar: Decimal) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: tutar as NSDecimalNumber) ?? "0.00"
    }

    static func bicim(_ tutar: Decimal) -> String {
        bicim((tutar as NSDecimalNumber).doubleValue)
    }
}

// MARK: - Modeller

struct DVBOdemeLinki: Decodable, Identifiable {
    let id: Int
    let url: String
    let amount: String
    let amountDisplay: String
    let description: String?
    let status: String
    let statusLabel: String?
    let patientName: String?
    let patientPhone: String?
    let expiresAt: Date?
    let paidAt: Date?
    let createdAt: Date?
    let shareText: String

    var bekliyor: Bool { status == "pending" }

    var durumRengi: Color {
        switch status {
        case "paid": return DVBTheme.accent
        case "pending": return .orange
        default: return .secondary
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, url, amount, description, status
        case amountDisplay = "amount_display"
        case statusLabel = "status_label"
        case patientName = "patient_name"
        case patientPhone = "patient_phone"
        case expiresAt = "expires_at"
        case paidAt = "paid_at"
        case createdAt = "created_at"
        case shareText = "share_text"
    }
}

private struct DVBOdemeLinkiSayfasi: Decodable {
    let data: [DVBOdemeLinki]
    let page: Int
    let lastPage: Int
    enum CodingKeys: String, CodingKey { case data, page; case lastPage = "last_page" }
}

private struct DVBOdemeLinkiCevabi: Decodable {
    let link: DVBOdemeLinki
    let message: String?
}

struct DVBTahsilat: Decodable, Identifiable {
    let id: Int
    let paidAt: Date?
    let payer: String?
    let amountDisplay: String
    let pspFeeDisplay: String
    let commissionDisplay: String
    let payoutDisplay: String
    let refunded: Bool?
    let transfer: Gonderim

    struct Gonderim: Decodable {
        let code: String
        let label: String
        let date: Date?
        let note: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, payer, refunded, transfer
        case paidAt = "paid_at"
        case amountDisplay = "amount_display"
        case pspFeeDisplay = "psp_fee_display"
        case commissionDisplay = "commission_display"
        case payoutDisplay = "payout_display"
    }
}

private struct DVBTahsilatSayfasi: Decodable {
    let valorDays: Int
    let pendingTotal: String
    let pendingTotalDisplay: String
    let page: Int
    let lastPage: Int
    let data: [DVBTahsilat]

    enum CodingKeys: String, CodingKey {
        case page, data
        case valorDays = "valor_days"
        case pendingTotal = "pending_total"
        case pendingTotalDisplay = "pending_total_display"
        case lastPage = "last_page"
    }
}

/// Sistem paylaşım menüsü (iOS 15: ShareLink yok).
struct DVBPaylasim: UIViewControllerRepresentable {
    let ogeler: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct DVBPaylasimOgesi: Identifiable {
    let id = UUID()
    let metin: String
}

// MARK: - Tahsilat sekmesi

struct DVBHekimTahsilatView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    private enum Bolum: Hashable { case linkler, tahsilatlar }

    @State private var bolum: Bolum = .linkler
    @State private var linkler: [DVBOdemeLinki] = []
    @State private var linkSayfa = 0
    @State private var linkSonSayfa = 1
    @State private var tahsilatlar: [DVBTahsilat] = []
    @State private var tahsilatSayfa = 0
    @State private var tahsilatSonSayfa = 1
    @State private var bekleyenToplam: String?
    @State private var valorGun: Int?
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var mesaj: String?
    @State private var yeniAcik = false
    @State private var paylasilan: DVBPaylasimOgesi?
    @State private var iptalEdilecek: DVBOdemeLinki?

    var body: some View {
        NavigationView {
            List {
                Picker("Bölüm", selection: $bolum) {
                    Text("Ödeme linkleri").tag(Bolum.linkler)
                    Text("Tahsilatlarım").tag(Bolum.tahsilatlar)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let mesaj {
                    Text(mesaj).font(.subheadline).foregroundColor(DVBTheme.accent)
                }

                if let hata, (bolum == .linkler ? linkler.isEmpty : tahsilatlar.isEmpty) {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Bilgiler alınamadı", message: hata) {
                        Task { await yenile() }
                    }
                } else if bolum == .linkler {
                    linkBolumu
                } else {
                    tahsilatBolumu
                }
            }
            .refreshable { await yenile() }
            .navigationTitle("Tahsilat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { yeniAcik = true } label: { Label("Yeni ödeme linki", systemImage: "plus") }
                }
            }
            .task(id: bolum) { await yenile() }
            .sheet(isPresented: $yeniAcik) {
                DVBOdemeLinkiFormu { yeni in
                    linkler.insert(yeni, at: 0)
                    bolum = .linkler
                    mesaj = "Ödeme linki oluşturuldu: \(yeni.amountDisplay)"
                    paylasilan = DVBPaylasimOgesi(metin: yeni.shareText)
                }
                .environmentObject(session)
            }
            .sheet(item: $paylasilan) { DVBPaylasim(ogeler: [$0.metin]) }
            .alert("Ödeme linki iptal edilsin mi?",
                   isPresented: Binding(get: { iptalEdilecek != nil }, set: { if !$0 { iptalEdilecek = nil } })) {
                Button("Vazgeç", role: .cancel) { iptalEdilecek = nil }
                Button("İptal et", role: .destructive) {
                    if let l = iptalEdilecek { Task { await iptal(l) } }
                    iptalEdilecek = nil
                }
            } message: {
                Text("\(iptalEdilecek?.amountDisplay ?? "") tutarlı link artık ödenemez.")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Ödeme linkleri

    @ViewBuilder private var linkBolumu: some View {
        Section {
            if yukleniyor && linkler.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if linkler.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Henüz ödeme linki oluşturmadınız.").foregroundColor(.secondary)
                    Button { yeniAcik = true } label: { Label("Ödeme linki oluştur", systemImage: "plus.circle.fill") }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(linkler) { l in
                    linkSatiri(l)
                        .onAppear { if l.id == linkler.last?.id { Task { await linkleriYukle(sayfa: linkSayfa + 1) } } }
                }
            }
        } footer: {
            Text("Linke dokunduğunuzda ödeme sayfası her zaman tarayıcıda açılır. Hasta ödeyince tutar Tahsilatlarım'a düşer.")
        }
    }

    private func linkSatiri(_ l: DVBOdemeLinki) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.amountDisplay).font(.headline).monospacedDigit()
                Spacer()
                Text(l.statusLabel ?? l.status).font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(l.durumRengi.opacity(0.15)).foregroundColor(l.durumRengi)
                    .clipShape(Capsule())
            }
            if let a = l.description, !a.isEmpty { Text(a).font(.subheadline) }
            HStack(spacing: 8) {
                if let h = l.patientName { Label(h, systemImage: "person").labelStyle(.titleAndIcon) }
                if let t = l.createdAt { Text(DVBSaat.gun(t, "d MMM HH:mm")) }
                if l.bekliyor, let s = l.expiresAt { Text("Son gün \(DVBSaat.gun(s, "d MMM"))") }
            }
            .font(.caption).foregroundColor(.secondary)

            if l.bekliyor {
                HStack(spacing: 14) {
                    Button { whatsapp(l) } label: { Label("WhatsApp", systemImage: "message") }
                    Button { paylasilan = DVBPaylasimOgesi(metin: l.shareText) } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                    Button { if let u = URL(string: l.url) { DVBOdemeAdresi.tarayicidaAc(u) } } label: { Label("Tarayıcıda aç", systemImage: "safari") }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button { UIPasteboard.general.string = l.url; mesaj = "Link kopyalandı." } label: { Label("Linki kopyala", systemImage: "doc.on.doc") }
            if l.bekliyor {
                Button(role: .destructive) { iptalEdilecek = l } label: { Label("İptal et", systemImage: "xmark.circle") }
            }
        }
        .swipeActions {
            if l.bekliyor {
                Button(role: .destructive) { iptalEdilecek = l } label: { Label("İptal", systemImage: "xmark.circle") }
            }
        }
    }

    /// Hasta seçiliyse doğrudan onun numarasına, değilse kişi seçtiren genel WhatsApp paylaşımı. WhatsApp uygulaması
    /// açılır; ödeme sayfası orada da tarayıcıda açılır.
    private func whatsapp(_ l: DVBOdemeLinki) {
        var bilesen = URLComponents(string: "https://wa.me/")!
        if let tel = l.patientPhone?.filter(\.isNumber), !tel.isEmpty { bilesen.path = "/" + tel }
        bilesen.queryItems = [URLQueryItem(name: "text", value: l.shareText)]
        if let u = bilesen.url { openURL(u) }
    }

    // MARK: Tahsilatlar

    @ViewBuilder private var tahsilatBolumu: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let t = bekleyenToplam {
                    HStack {
                        Text("Gönderim bekleyen").foregroundColor(.secondary)
                        Spacer()
                        Text(t).font(.headline).monospacedDigit()
                    }
                }
                if let v = valorGun {
                    Text("Kartla yapılan tahsilatta PayTR komisyonu ve hizmet bedeli düşülür; kalan tutarın gönderim talebi tahsilattan \(v + 1) gün sonra ödeme hesabınızdaki IBAN'a otomatik oluşturulur.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }

        Section {
            if yukleniyor && tahsilatlar.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if tahsilatlar.isEmpty {
                Text("Henüz tahsilat yok.").foregroundColor(.secondary)
            } else {
                ForEach(tahsilatlar) { t in
                    tahsilatSatiri(t)
                        .onAppear { if t.id == tahsilatlar.last?.id { Task { await tahsilatlariYukle(sayfa: tahsilatSayfa + 1) } } }
                }
            }
        }
    }

    private func tahsilatSatiri(_ t: DVBTahsilat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.payer ?? "—").font(.subheadline.weight(.semibold))
                Spacer()
                Text(t.amountDisplay).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            HStack {
                Text(t.paidAt.map { DVBSaat.gun($0, "d MMM yyyy HH:mm") } ?? "—")
                Spacer()
                Text("Size gidecek: \(t.payoutDisplay)").monospacedDigit()
            }
            .font(.caption).foregroundColor(.secondary)
            Text("PayTR: \(t.pspFeeDisplay) · Hizmet bedeli: \(t.commissionDisplay)")
                .font(.caption2).foregroundColor(.secondary).monospacedDigit()
            HStack(spacing: 6) {
                Text(t.transfer.code == "gonderildi" ? "✓ \(t.transfer.label)" : t.transfer.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(gonderimRengi(t.transfer.code).opacity(0.15))
                    .foregroundColor(gonderimRengi(t.transfer.code))
                    .clipShape(Capsule())
                if let n = t.transfer.note { Text(n).font(.caption2).foregroundColor(.secondary) }
            }
        }
        .padding(.vertical, 3)
    }

    private func gonderimRengi(_ kod: String) -> Color {
        switch kod {
        case "gonderildi": return DVBTheme.accent
        case "bekliyor": return .orange
        default: return .secondary
        }
    }

    // MARK: Veri

    private func yenile() async {
        if bolum == .linkler {
            linkSayfa = 0; linkSonSayfa = 1
            await linkleriYukle(sayfa: 1)
        } else {
            tahsilatSayfa = 0; tahsilatSonSayfa = 1
            await tahsilatlariYukle(sayfa: 1)
        }
    }

    private func linkleriYukle(sayfa: Int) async {
        guard let token = session.token, sayfa <= linkSonSayfa, !(yukleniyor && sayfa > 1) else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let s: DVBOdemeLinkiSayfasi = try await DVBAPI.shared.get("my/doctor/payment-links", query: ["page": String(sayfa)], token: token)
            linkler = sayfa == 1 ? s.data : linkler + s.data
            linkSayfa = s.page; linkSonSayfa = s.lastPage
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func tahsilatlariYukle(sayfa: Int) async {
        guard let token = session.token, sayfa <= tahsilatSonSayfa, !(yukleniyor && sayfa > 1) else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let s: DVBTahsilatSayfasi = try await DVBAPI.shared.get("my/doctor/collections", query: ["page": String(sayfa)], token: token)
            tahsilatlar = sayfa == 1 ? s.data : tahsilatlar + s.data
            tahsilatSayfa = s.page; tahsilatSonSayfa = s.lastPage
            bekleyenToplam = s.pendingTotalDisplay
            valorGun = s.valorDays
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func iptal(_ l: DVBOdemeLinki) async {
        guard let token = session.token else { return }
        do {
            let c: DVBOdemeLinkiCevabi = try await DVBAPI.shared.post("my/doctor/payment-links/\(l.id)/cancel", token: token)
            if let i = linkler.firstIndex(where: { $0.id == l.id }) { linkler[i] = c.link }
            mesaj = c.message
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Yeni ödeme linki

private struct DVBOdemeLinkiFormu: View {
    var olusturuldu: (DVBOdemeLinki) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var tutarMetni = ""
    @State private var aciklama = ""
    @State private var sureGun = 7
    @State private var hasta: DVBHekimHastaOzet?
    @State private var hastaSeciliyor = false
    @State private var onayAcik = false
    @State private var gonderiliyor = false
    @State private var hata: String?

    private var tutar: Decimal? {
        guard let d = DVBPara.coz(tutarMetni), d >= 1, d <= 9_999_999 else { return nil }
        return d
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Tutar (örn. 1.500,00)", text: $tutarMetni)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                } header: {
                    Text("Tutar")
                } footer: {
                    if tutarMetni.isEmpty {
                        Text("Hastanın ödeyeceği toplam tutar.")
                    } else if let t = tutar {
                        Text("Hasta \(DVBPara.bicim(t)) ödeyecek.").foregroundColor(DVBTheme.accent)
                    } else {
                        Text("Tutar okunamadı. Örnek: 1.500,00").foregroundColor(.red)
                    }
                }

                Section("Açıklama") {
                    TextField("Örn. Kontrol muayenesi", text: $aciklama)
                }

                Section {
                    Button { hastaSeciliyor = true } label: {
                        HStack {
                            Text("Hasta").foregroundColor(.primary)
                            Spacer()
                            Text(hasta?.name ?? "Seçilmedi").foregroundColor(.secondary)
                        }
                    }
                    if hasta != nil {
                        Button("Hastayı kaldır", role: .destructive) { hasta = nil }
                    }
                    Picker("Geçerlilik", selection: $sureGun) {
                        Text("1 gün").tag(1)
                        Text("3 gün").tag(3)
                        Text("7 gün").tag(7)
                        Text("30 gün").tag(30)
                        Text("90 gün").tag(90)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hasta seçerseniz WhatsApp düğmesi doğrudan onun numarasını açar.")
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle("Ödeme linki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") { onayAcik = true }
                        .disabled(tutar == nil || gonderiliyor)
                }
            }
            // Para işlemi: tutar gösterim biçiminde bir kez daha onaylatılır (1.500 ↔ 15,00 karışmasın).
            .alert("\(tutar.map { DVBPara.bicim($0) } ?? "") tutarlı ödeme linki oluşturulsun mu?", isPresented: $onayAcik) {
                Button("Vazgeç", role: .cancel) {}
                Button("Oluştur") { Task { await olustur() } }
            }
            .sheet(isPresented: $hastaSeciliyor) {
                DVBHastaSecici { secilen in hasta = secilen }
                    .environmentObject(session)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func olustur() async {
        guard let token = session.token, let t = tutar else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        var govde: [String: Any] = ["amount": DVBPara.makine(t), "expires_days": sureGun]
        let a = aciklama.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { govde["description"] = a }
        if let h = hasta { govde["patient_id"] = h.id }
        do {
            let c: DVBOdemeLinkiCevabi = try await DVBAPI.shared.post("my/doctor/payment-links", body: govde, token: token)
            olusturuldu(c.link)
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

/// Ödeme linki için hasta seçimi — Hastalar sekmesiyle AYNI uç (aynı görünürlük kuralı + erişim kaydı).
private struct DVBHastaSecici: View {
    var secildi: (DVBHekimHastaOzet) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var arama = ""
    @State private var sonuclar: [DVBHekimHastaOzet] = []
    @State private var hata: String?

    private struct Sayfa: Decodable { let data: [DVBHekimHastaOzet] }

    var body: some View {
        NavigationView {
            List {
                if let hata { Text(hata).foregroundColor(.red) }
                ForEach(sonuclar) { h in
                    Button {
                        secildi(h)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name ?? "—").foregroundColor(.primary)
                            if let no = h.patientNo { Text(no).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ad, telefon veya hasta no")
            .navigationTitle("Hasta seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .task(id: arama) {
                try? await Task.sleep(nanoseconds: arama.isEmpty ? 0 : 350_000_000)
                if Task.isCancelled { return }
                await ara()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ara() async {
        guard let token = session.token else { return }
        var q: [String: String] = [:]
        let t = arama.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { q["q"] = t }
        do {
            let s: Sayfa = try await DVBAPI.shared.get("my/doctor/patients", query: q, token: token)
            sonuclar = s.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
