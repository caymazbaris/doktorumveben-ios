import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000343 — e-FATURA (hekim).
//
// Kullanıcı (8 Eki 2026): "profil düzenleme, muhasebe ve e-Fatura. da yapalım".
//
// Kurallar sunucuda ve web /panel/faturalar ile ORTAK (HekimFaturaApiController → InvoiceController::kesmeKurallari,
// kesimVerisi, FaturaPdf): VKN/TCKN algoritma denetimi, kalem adında harf şartı, ön kontrol, GİB'e gitmiş belgenin yerelde
// iptal edilememesi. Belge türü (e-Fatura / e-Arşiv / Serbest Meslek Makbuzu) sistemce belirlenir.
// · Fatura önce TASLAK olarak oluşur; GİB'e gönderme ayrı ve onay isteyen bir adımdır (yasal belge, geri alınamaz).
// · Muhasebeci hesabı faturaları görür, kesemez (sunucu `can_create`).
// · "Fatura bilgilerim" (ünvan, VKN, vergi dairesi, adres) web panelinde; eksikse Safari'de açılır.
// · Birim fiyatlar KDV HARİÇ girilir (web formu ile aynı). Tutarlar 10.000,00 ₺ biçiminde.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBFaturaOzeti: Decodable, Identifiable {
    let id: Int
    let documentNo: String?
    let typeLabel: String?
    let customerName: String?
    let issuedOn: String?
    let total: Double
    let state: String
    let stateLabel: String
    let einvoiceLabel: String?

    var durumRengi: Color {
        switch state {
        case "issued": return DVBTheme.accent
        case "cancelled": return .red
        default: return .orange
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, total, state
        case documentNo = "document_no"
        case typeLabel = "type_label"
        case customerName = "customer_name"
        case issuedOn = "issued_on"
        case stateLabel = "state_label"
        case einvoiceLabel = "einvoice_label"
    }
}

struct DVBFaturaAyrintisi: Decodable {
    let id: Int
    let documentNo: String?
    let typeLabel: String?
    let customerName: String?
    let issuedOn: String?
    let total: Double
    let state: String
    let stateLabel: String
    let einvoiceLabel: String?
    let customerTaxNo: String?
    let customerAddress: String?
    let amount: Double
    let vatAmount: Double
    let incomeWithholdingAmount: Double?
    let withholdingVatAmount: Double?
    let netPayable: Double?
    let einvoiceError: String?
    let ettn: String?
    let patientEmail: String?
    let appointmentNo: String?
    let canSend: Bool
    let canCancel: Bool
    let items: [Kalem]

    struct Kalem: Decodable, Hashable {
        let name: String
        let quantity: Double
        let unitPrice: Double
        let vatRate: Double
        let lineTotal: Double

        enum CodingKeys: String, CodingKey {
            case name, quantity
            case unitPrice = "unit_price"
            case vatRate = "vat_rate"
            case lineTotal = "line_total"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, total, state, amount, ettn, items
        case documentNo = "document_no"
        case typeLabel = "type_label"
        case customerName = "customer_name"
        case issuedOn = "issued_on"
        case stateLabel = "state_label"
        case einvoiceLabel = "einvoice_label"
        case customerTaxNo = "customer_tax_no"
        case customerAddress = "customer_address"
        case vatAmount = "vat_amount"
        case incomeWithholdingAmount = "income_withholding_amount"
        case withholdingVatAmount = "withholding_vat_amount"
        case netPayable = "net_payable"
        case einvoiceError = "einvoice_error"
        case patientEmail = "patient_email"
        case appointmentNo = "appointment_no"
        case canSend = "can_send"
        case canCancel = "can_cancel"
    }
}

private struct DVBFaturaListesi: Decodable {
    let canCreate: Bool
    let billingProfileComplete: Bool
    let billingProfilePath: String?
    let data: [DVBFaturaOzeti]
    let page: Int
    let lastPage: Int

    enum CodingKeys: String, CodingKey {
        case data, page
        case canCreate = "can_create"
        case billingProfileComplete = "billing_profile_complete"
        case billingProfilePath = "billing_profile_path"
        case lastPage = "last_page"
    }
}

private struct DVBFaturaCevabi: Decodable {
    let ok: Bool?
    let message: String?
    let invoice: DVBFaturaAyrintisi?
}

/// Safari'de web paneli sayfası (tek kullanımlık giriş köprüsüyle).
@MainActor
enum DVBPanelSafari {
    static func ac(_ yol: String, _ openURL: OpenURLAction) async {
        guard let hedef = URL(string: yol, relativeTo: DVBConfig.webBase)?.absoluteURL else { return }
        let adres = await DVBWebOturum.kopruAdresi(hedef) ?? hedef
        openURL(adres)
    }
}

// MARK: - Liste

struct DVBHekimFaturalarView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var liste: DVBFaturaListesi?
    @State private var faturalar: [DVBFaturaOzeti] = []
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniAcik = false
    @State private var dahaYukleniyor = false

    var body: some View {
        Group {
            if let l = liste {
                icerik(l)
            } else if let hata {
                DVBStateView(icon: "doc.text.magnifyingglass", title: "Faturalar alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Faturalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if liste?.canCreate == true {
                    Button { yeniAcik = true } label: { Label("Fatura kes", systemImage: "plus") }
                }
            }
        }
        .task { await yukle() }
        .alert("Faturalar", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .sheet(isPresented: $yeniAcik) {
            DVBFaturaKesView { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func icerik(_ l: DVBFaturaListesi) -> some View {
        List {
            if l.canCreate && !l.billingProfileComplete, let yol = l.billingProfilePath {
                Section {
                    Button {
                        Task { await DVBPanelSafari.ac(yol, openURL) }
                    } label: {
                        Label("Fatura bilgilerinizi tamamlayın", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                } footer: {
                    Text("GİB'e gönderebilmek için ünvan, VKN/TCKN, vergi dairesi ve adres gerekir. Bilgiler web panelinde Safari'de açılır.")
                }
            }

            Section {
                if faturalar.isEmpty {
                    Text("Henüz fatura yok.").foregroundColor(.secondary)
                } else {
                    ForEach(faturalar) { f in
                        NavigationLink(destination: DVBFaturaDetayView(faturaId: f.id, degisti: { Task { await yukle() } })) {
                            satir(f)
                        }
                    }
                    if l.page < l.lastPage {
                        Button {
                            Task { await dahaFazla(l.page + 1) }
                        } label: {
                            if dahaYukleniyor { ProgressView().frame(maxWidth: .infinity) } else { Text("Daha fazla göster").frame(maxWidth: .infinity) }
                        }
                        .disabled(dahaYukleniyor)
                    }
                }
            }
        }
        .refreshable { await yukle() }
    }

    private func satir(_ f: DVBFaturaOzeti) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f.customerName ?? "—").font(.subheadline.weight(.semibold))
                Text([f.documentNo, f.typeLabel, DVBGunMetni.yaz(f.issuedOn, "d MMM yyyy")].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(DVBPara.bicim(f.total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(f.stateLabel).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(f.durumRengi.opacity(0.15)).foregroundColor(f.durumRengi)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let l: DVBFaturaListesi = try await DVBAPI.shared.get("my/doctor/invoices", token: token)
            liste = l
            faturalar = l.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func dahaFazla(_ sayfa: Int) async {
        guard let token = session.token, !dahaYukleniyor else { return }
        dahaYukleniyor = true
        defer { dahaYukleniyor = false }
        do {
            let l: DVBFaturaListesi = try await DVBAPI.shared.get("my/doctor/invoices", query: ["page": String(sayfa)], token: token)
            liste = l
            faturalar.append(contentsOf: l.data.filter { yeni in !faturalar.contains(where: { $0.id == yeni.id }) })
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Ayrıntı

struct DVBFaturaDetayView: View {
    let faturaId: Int
    var degisti: () -> Void = {}

    @EnvironmentObject private var session: DVBSession

    @State private var fatura: DVBFaturaAyrintisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var calisiyor = false
    @State private var onizlenen: DVBYerelDosya?
    @State private var gonderOnayi = false
    @State private var iptalOnayi = false
    @State private var epostaAcik = false
    @State private var eposta = ""
    @State private var epostaNotu = ""

    var body: some View {
        Group {
            if let f = fatura {
                icerik(f)
            } else if let hata {
                DVBStateView(icon: "doc.text", title: "Fatura alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(fatura?.documentNo ?? "Fatura")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .alert("Fatura", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .alert("Fatura GİB'e gönderilsin mi?", isPresented: $gonderOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("GİB'e gönder") { Task { await islem("send") } }
        } message: {
            Text("Gönderilen fatura yasal belge olur; uygulamadan ya da panelden geri alınamaz. Bilgileri kontrol ettiyseniz gönderin.")
        }
        .alert("Taslak iptal edilsin mi?", isPresented: $iptalOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("İptal et", role: .destructive) { Task { await islem("cancel") } }
        } message: {
            Text("Fatura henüz GİB'e gönderilmedi; iptal edilince kullanılamaz.")
        }
        .sheet(item: $onizlenen) { d in
            DVBBelgeOnizleme(dosya: d.url, kapat: { onizlenen = nil })
        }
        .sheet(isPresented: $epostaAcik) {
            NavigationView {
                Form {
                    Section {
                        TextField("E-posta adresi", text: $eposta)
                            .keyboardType(.emailAddress).autocapitalization(.none).disableAutocorrection(true)
                        TextField("Not (isteğe bağlı)", text: $epostaNotu)
                    } footer: {
                        Text("Fatura PDF olarak eklenir.")
                    }
                }
                .navigationTitle("E-postayla gönder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { epostaAcik = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gönder") {
                            epostaAcik = false
                            Task { await epostaGonder() }
                        }
                        .disabled(!eposta.contains("@"))
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private func icerik(_ f: DVBFaturaAyrintisi) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.customerName ?? "—").font(.title3.bold())
                    Text([f.typeLabel, DVBGunMetni.yaz(f.issuedOn)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text(f.stateLabel).font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(renk(f.state).opacity(0.15)).foregroundColor(renk(f.state))
                            .clipShape(Capsule())
                        if let e = f.einvoiceLabel { Text("GİB: " + e).font(.caption).foregroundColor(.secondary) }
                    }
                }
                .padding(.vertical, 4)
                if let hataMetni = f.einvoiceError, !hataMetni.isEmpty {
                    Text(hataMetni).font(.caption).foregroundColor(.red)
                }
            }

            Section("Alıcı") {
                bilgiSatiri("VKN / TCKN", f.customerTaxNo)
                bilgiSatiri("Adres", f.customerAddress)
                bilgiSatiri("Randevu", f.appointmentNo)
                bilgiSatiri("ETTN", f.ettn)
            }

            Section("Kalemler") {
                ForEach(f.items, id: \.self) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(k.name).font(.subheadline)
                            Spacer()
                            Text(DVBPara.bicim(k.lineTotal)).font(.subheadline).monospacedDigit()
                        }
                        Text("\(DVBSayi.yaz(k.quantity)) × \(DVBPara.bicim(k.unitPrice)) · KDV %\(DVBSayi.yaz(k.vatRate))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Section("Tutar") {
                tutarSatiri("Ara toplam", f.amount)
                tutarSatiri("KDV", f.vatAmount)
                if let s = f.incomeWithholdingAmount, s > 0 { tutarSatiri("Gelir vergisi stopajı", -s) }
                if let t = f.withholdingVatAmount, t > 0 { tutarSatiri("KDV tevkifatı", -t) }
                tutarSatiri("Toplam", f.total).font(.subheadline.weight(.bold))
                if let n = f.netPayable, n != f.total { tutarSatiri("Ödenecek", n) }
            }

            Section {
                Button { Task { await pdfAc() } } label: { Label("PDF'i aç / paylaş", systemImage: "doc.richtext") }
                Button {
                    eposta = f.patientEmail ?? ""
                    epostaAcik = true
                } label: { Label("E-postayla gönder", systemImage: "envelope") }
                if f.canSend {
                    Button { gonderOnayi = true } label: { Label("GİB'e gönder", systemImage: "paperplane") }
                }
                if f.canCancel {
                    Button(role: .destructive) { iptalOnayi = true } label: { Label("Taslağı iptal et", systemImage: "xmark.circle") }
                }
            } footer: {
                if calisiyor { ProgressView() }
            }
            .disabled(calisiyor)
        }
        .refreshable { await yukle() }
    }

    private func renk(_ durum: String) -> Color {
        switch durum {
        case "issued": return DVBTheme.accent
        case "cancelled": return .red
        default: return .orange
        }
    }

    private func bilgiSatiri(_ etiket: String, _ deger: String?) -> some View {
        Group {
            if let deger, !deger.isEmpty {
                HStack(alignment: .top) {
                    Text(etiket).foregroundColor(.secondary)
                    Spacer()
                    Text(deger).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
    }

    private func tutarSatiri(_ etiket: String, _ tutar: Double) -> some View {
        HStack {
            Text(etiket)
            Spacer()
            Text(DVBPara.bicim(tutar)).monospacedDigit()
        }
        .font(.subheadline)
    }

    // MARK: - Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBFaturaCevabi = try await DVBAPI.shared.get("my/doctor/invoices/\(faturaId)", token: token)
            fatura = c.invoice
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func islem(_ ad: String) async {
        guard let token = session.token, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let c: DVBFaturaCevabi = try await DVBAPI.shared.post("my/doctor/invoices/\(faturaId)/\(ad)", token: token)
            if let yeni = c.invoice { fatura = yeni }
            bilgi = c.message
            degisti()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func epostaGonder() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["email": eposta.trimmingCharacters(in: .whitespacesAndNewlines)]
        let n = epostaNotu.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { govde["note"] = n }
        do {
            let c: DVBFaturaCevabi = try await DVBAPI.shared.post("my/doctor/invoices/\(faturaId)/email", body: govde, token: token)
            bilgi = c.message
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func pdfAc() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let veri = try await DVBAPI.shared.veri("my/doctor/invoices/\(faturaId)/pdf", token: token)
            let ad = "Fatura_" + (fatura?.documentNo ?? String(faturaId)).replacingOccurrences(of: "/", with: "-") + ".pdf"
            let yol = FileManager.default.temporaryDirectory.appendingPathComponent(ad)
            try veri.write(to: yol, options: .atomic)
            onizlenen = DVBYerelDosya(url: yol)
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

/// Adet/oran gösterimi: tam sayıysa ondalıksız ("1", "10"), değilse virgüllü ("1,5").
enum DVBSayi {
    static func yaz(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.2f", d).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Fatura kesme

private struct DVBFaturaSecenekleri: Decodable {
    let docIsIndividual: Bool
    let billingProfileComplete: Bool
    let services: [Hizmet]
    let exemptions: [Kod]
    let withholdings: [Kod]

    struct Hizmet: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let netPrice: Double
        let vatRate: Double

        enum CodingKeys: String, CodingKey {
            case id, name
            case netPrice = "net_price"
            case vatRate = "vat_rate"
        }
    }

    struct Kod: Decodable, Hashable {
        let code: String
        let label: String
    }

    enum CodingKeys: String, CodingKey {
        case services, exemptions, withholdings
        case docIsIndividual = "doc_is_individual"
        case billingProfileComplete = "billing_profile_complete"
    }
}

private struct DVBAliciSonucu: Decodable {
    let checked: Bool?
    let channel: String?
    let label: String?
    let note: String?
}

private struct DVBFaturaKalemi: Identifiable {
    let id = UUID()
    var hizmetId: Int?
    var ad: String
    var adet: String
    var birimFiyat: String
    var kdv: String
}

struct DVBFaturaKesView: View {
    var kesildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var secenekler: DVBFaturaSecenekleri?
    @State private var musteri = ""
    @State private var vergiNo = ""
    @State private var adres = ""
    @State private var tarih = Date()
    @State private var istisna: String?
    @State private var stopaj = ""
    @State private var kalemler: [DVBFaturaKalemi] = []
    @State private var aliciNotu: String?
    @State private var sorgulaniyor = false
    @State private var calisiyor = false
    @State private var hata: String?

    private var hazir: Bool {
        !musteri.trimmingCharacters(in: .whitespaces).isEmpty
            && kalemler.contains { !$0.ad.trimmingCharacters(in: .whitespaces).isEmpty && DVBPara.coz($0.birimFiyat) != nil }
    }

    var body: some View {
        NavigationView {
            Form {
                if let s = secenekler {
                    Section {
                        TextField("Ad soyad / ünvan", text: $musteri)
                        HStack {
                            TextField("TCKN / VKN (isteğe bağlı)", text: $vergiNo).keyboardType(.numberPad)
                            Button {
                                Task { await aliciSorgula() }
                            } label: {
                                if sorgulaniyor { ProgressView() } else { Text("Sorgula") }
                            }
                            .buttonStyle(.borderless)
                            .disabled(vergiNo.filter(\.isNumber).count < 10 || sorgulaniyor)
                        }
                        if let aliciNotu { Text(aliciNotu).font(.caption).foregroundColor(.secondary) }
                        TextField("Adres (isteğe bağlı)", text: $adres)
                    } header: {
                        Text("Alıcı")
                    } footer: {
                        Text("Belge türü (e-Fatura, e-Arşiv ya da serbest meslek makbuzu) alıcıya göre sistemce belirlenir.")
                    }

                    Section {
                        ForEach($kalemler) { $k in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Kalem adı (ör. Muayene)", text: $k.ad)
                                HStack {
                                    TextField("Adet", text: $k.adet).keyboardType(.decimalPad).frame(maxWidth: 60)
                                    TextField("Birim fiyat (KDV hariç)", text: $k.birimFiyat).keyboardType(.decimalPad)
                                    TextField("KDV %", text: $k.kdv).keyboardType(.numberPad).frame(maxWidth: 60)
                                }
                                .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { kalemler.remove(atOffsets: $0) }
                        Menu {
                            ForEach(s.services) { h in
                                Button(h.name) { hizmetEkle(h) }
                            }
                            Button("Elle kalem ekle") {
                                kalemler.append(DVBFaturaKalemi(hizmetId: nil, ad: "", adet: "1", birimFiyat: "", kdv: "10"))
                            }
                        } label: {
                            Label("Kalem ekle", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Kalemler")
                    } footer: {
                        Text("Silmek için kalemi sola kaydırın. Birim fiyatı KDV hariç yazın.")
                    }

                    Section {
                        DatePicker("Düzenleme tarihi", selection: $tarih, in: ...Date(), displayedComponents: .date)
                            .environment(\.timeZone, DVBTime.klinik)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                        Picker("KDV istisnası", selection: $istisna) {
                            Text("Yok").tag(String?.none)
                            ForEach(s.exemptions, id: \.code) { k in Text(k.label).tag(String?.some(k.code)) }
                        }
                        if s.docIsIndividual {
                            TextField("Gelir vergisi stopajı % (şirkete kesiliyorsa, ör. 20)", text: $stopaj).keyboardType(.numberPad)
                        }
                    } header: {
                        Text("Ayrıntılar")
                    }

                    if let hata {
                        Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                    }
                } else if let hata {
                    Text(hata).foregroundColor(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Fatura kes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await kes() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Oluştur").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
            .task { await seceneklerYukle() }
        }
        .navigationViewStyle(.stack)
    }

    private func hizmetEkle(_ h: DVBFaturaSecenekleri.Hizmet) {
        kalemler.append(DVBFaturaKalemi(
            hizmetId: h.id, ad: h.name, adet: "1",
            birimFiyat: String(format: "%.2f", h.netPrice).replacingOccurrences(of: ".", with: ","),
            kdv: DVBSayi.yaz(h.vatRate)
        ))
    }

    private func seceneklerYukle() async {
        guard let token = session.token, secenekler == nil else { return }
        do {
            let s: DVBFaturaSecenekleri = try await DVBAPI.shared.get("my/doctor/invoices/options", token: token)
            secenekler = s
            if kalemler.isEmpty {
                if let ilk = s.services.first { hizmetEkle(ilk) } else {
                    kalemler = [DVBFaturaKalemi(hizmetId: nil, ad: "", adet: "1", birimFiyat: "", kdv: "10")]
                }
            }
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func aliciSorgula() async {
        guard let token = session.token else { return }
        sorgulaniyor = true
        defer { sorgulaniyor = false }
        do {
            let c: DVBAliciSonucu = try await DVBAPI.shared.post(
                "my/doctor/invoices/check-recipient", body: ["tax_no": vergiNo.filter(\.isNumber)], token: token
            )
            aliciNotu = [c.label.map { "Belge türü: " + $0 }, c.note].compactMap { $0 }.joined(separator: " · ")
        } catch {
            if let m = DVBError.mesaj(error) { aliciNotu = m }
        }
    }

    private func kes() async {
        guard let token = session.token, hazir, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }

        let satirlar: [[String: Any]] = kalemler.compactMap { k in
            let ad = k.ad.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ad.isEmpty, let fiyat = DVBPara.coz(k.birimFiyat) else { return nil }
            var r: [String: Any] = ["name": ad, "unit_price": DVBPara.makine(fiyat)]
            if let h = k.hizmetId { r["service_id"] = h }
            if let a = DVBPara.coz(k.adet) { r["quantity"] = DVBPara.makine(a) }
            if let v = DVBPara.coz(k.kdv) { r["vat_rate"] = DVBPara.makine(v) }
            return r
        }
        var govde: [String: Any] = [
            "customer_name": musteri.trimmingCharacters(in: .whitespacesAndNewlines),
            "issued_on": DVBSaat.anahtar(tarih),
            "items": satirlar,
        ]
        let no = vergiNo.filter(\.isNumber)
        if !no.isEmpty { govde["customer_tax_no"] = no }
        let a = adres.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { govde["customer_address"] = a }
        if let istisna { govde["kdv_exemption_code"] = istisna }
        if let s = DVBPara.coz(stopaj) { govde["income_withholding_rate"] = DVBPara.makine(s) }

        do {
            let c: DVBFaturaCevabi = try await DVBAPI.shared.post("my/doctor/invoices", body: govde, token: token)
            kesildi(c.message ?? "Fatura oluşturuldu.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
