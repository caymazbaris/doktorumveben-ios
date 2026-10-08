import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000344 — FATURA BİLGİLERİM + BANKA HESABIM (hekim), tek ekranda.
//
// Kullanıcı (9 Eki 2026): "faturada kesebilsin banka hesap bilgisi eklediği bölümde olsun".
//
// Kurallar sunucuda (HekimOdemeFaturaBilgileriApiController; web "Fatura Bilgilerim" + "Ödeme Hesabım" ile aynı):
// · fatura bilgileri faturadaki SATICI kimliğidir; eksikse fatura GİB'e gönderilemez;
// · banka hesabı (IBAN) kaydedilince yeniden ONAYA düşer — onaya kadar kart ödemeleri eski yöntemle işler;
//   uygulamadan IBAN'ı yalnız hekimin kendisi değiştirir (sekreter değiştiremez);
// · e-Fatura entegratör kullanıcı adı/şifresi ve logo/kaşe/imza web panelinde kalır.
// ═══════════════════════════════════════════════════════════════════════════════

private struct DVBOdemeFaturaBilgileri: Decodable {
    let billing: Fatura
    let payout: Hesap?
    let canEditPayout: Bool
    let accountTypes: [Secenek]
    let webPath: String?

    struct Fatura: Decodable {
        let invoiceTitle: String?
        let invoiceTaxpayerType: String
        let taxNo: String?
        let taxOffice: String?
        let taxOfficeCode: String?
        let invoiceAddress: String?
        let invoicePhone: String?
        let invoiceEmail: String?
        let isEinvoicePayer: Bool
        let einvoiceAlias: String?
        let invoiceDefaultVat: Double?
        let invoiceNote: String?
        let complete: Bool

        enum CodingKeys: String, CodingKey {
            case complete
            case invoiceTitle = "invoice_title"
            case invoiceTaxpayerType = "invoice_taxpayer_type"
            case taxNo = "tax_no"
            case taxOffice = "tax_office"
            case taxOfficeCode = "tax_office_code"
            case invoiceAddress = "invoice_address"
            case invoicePhone = "invoice_phone"
            case invoiceEmail = "invoice_email"
            case isEinvoicePayer = "is_einvoice_payer"
            case einvoiceAlias = "einvoice_alias"
            case invoiceDefaultVat = "invoice_default_vat"
            case invoiceNote = "invoice_note"
        }
    }

    struct Hesap: Decodable {
        let accountType: String?
        let legalName: String?
        let idOrTaxNo: String?
        let taxOffice: String?
        let iban: String?
        let phone: String?
        let email: String?
        let address: String?
        let status: String?
        let statusLabel: String?
        let rejectionReason: String?

        enum CodingKeys: String, CodingKey {
            case iban, phone, email, address, status
            case accountType = "account_type"
            case legalName = "legal_name"
            case idOrTaxNo = "id_or_tax_no"
            case taxOffice = "tax_office"
            case statusLabel = "status_label"
            case rejectionReason = "rejection_reason"
        }
    }

    struct Secenek: Decodable, Hashable {
        let key: String
        let label: String
    }

    enum CodingKeys: String, CodingKey {
        case billing, payout
        case canEditPayout = "can_edit_payout"
        case accountTypes = "account_types"
        case webPath = "web_path"
    }
}

private struct DVBOdemeFaturaCevabi: Decodable {
    let ok: Bool?
    let message: String?
}

struct DVBVergiDairesi: Decodable, Identifiable, Hashable {
    let code: String
    let name: String
    let city: String?
    let label: String
    var id: String { code }
}

private struct DVBVergiDairesiListesi: Decodable {
    let data: [DVBVergiDairesi]
}

struct DVBHekimOdemeFaturaView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var veri: DVBOdemeFaturaBilgileri?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var faturaKaydediliyor = false
    @State private var hesapKaydediliyor = false
    @State private var hesapOnayi = false
    @State private var vdAramaAcik = false

    // Fatura bilgileri
    @State private var unvan = ""
    @State private var mukellef = "individual"
    @State private var vergiNo = ""
    @State private var vergiDairesi = ""
    @State private var vergiDairesiKodu: String?
    @State private var faturaAdresi = ""
    @State private var faturaTelefon = ""
    @State private var faturaEposta = ""
    @State private var efaturaMukellefi = false
    @State private var efaturaEtiketi = ""
    @State private var varsayilanKdv = ""
    @State private var faturaNotu = ""

    // Banka hesabı
    @State private var hesapTuru = "individual"
    @State private var hesapAdi = ""
    @State private var hesapKimlik = ""
    @State private var hesapVd = ""
    @State private var iban = ""
    @State private var hesapTelefon = ""
    @State private var hesapEposta = ""
    @State private var hesapAdres = ""

    var body: some View {
        Group {
            if let v = veri {
                form(v)
            } else if let hata {
                DVBStateView(icon: "building.columns", title: "Bilgiler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Fatura ve banka bilgileri")
        .navigationBarTitleDisplayMode(.inline)
        .task { if veri == nil { await yukle() } }
        .alert("Bilgiler", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .alert("Banka hesabı kaydedilsin mi?", isPresented: $hesapOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") { Task { await hesapKaydet() } }
        } message: {
            Text("Kaydedince hesap yeniden onaya alınır. Onaylanana kadar kart ödemeleri eski yöntemle (platform tahsil eder, hakediş olarak aktarılır) işler.")
        }
        .sheet(isPresented: $vdAramaAcik) {
            DVBVergiDairesiAramaView { vd in
                vergiDairesi = vd.name
                vergiDairesiKodu = vd.code
            }
            .environmentObject(session)
        }
    }

    private func form(_ v: DVBOdemeFaturaBilgileri) -> some View {
        Form {
            // ── Fatura bilgileri
            Section {
                if !v.billing.complete {
                    Label("Fatura kesip GİB'e gönderebilmek için ünvan, VKN/TCKN, vergi dairesi ve adres gerekir.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundColor(.orange)
                }
                Picker("Mükellef türü", selection: $mukellef) {
                    Text("Serbest meslek (şahıs)").tag("individual")
                    Text("Şirket").tag("company")
                }
                TextField("Ünvan (faturada görünen ad)", text: $unvan)
                TextField("VKN (10) / TCKN (11)", text: $vergiNo).keyboardType(.numberPad)
                Button {
                    vdAramaAcik = true
                } label: {
                    HStack {
                        Text("Vergi dairesi").foregroundColor(.primary)
                        Spacer()
                        Text(vergiDairesi.isEmpty ? "Seçin" : vergiDairesi).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                TextField("Fatura adresi", text: $faturaAdresi)
                TextField("Telefon (isteğe bağlı)", text: $faturaTelefon).keyboardType(.phonePad)
                TextField("E-posta (isteğe bağlı)", text: $faturaEposta).keyboardType(.emailAddress).autocapitalization(.none).disableAutocorrection(true)
            } header: {
                Text("Fatura bilgilerim")
            } footer: {
                Text("Kestiğiniz faturalarda satıcı olarak bu bilgiler yer alır. Serbest meslek mükellefi için belge Serbest Meslek Makbuzu olarak düzenlenir.")
            }

            Section {
                Toggle("e-Fatura mükellefiyim", isOn: $efaturaMukellefi)
                if efaturaMukellefi {
                    TextField("e-Fatura posta kutusu etiketi (isteğe bağlı)", text: $efaturaEtiketi).autocapitalization(.none).disableAutocorrection(true)
                }
                TextField("Varsayılan KDV oranı % (ör. 10)", text: $varsayilanKdv).keyboardType(.numberPad)
                TextField("Fatura notu (isteğe bağlı)", text: $faturaNotu)
                Button {
                    Task { await faturaKaydet() }
                } label: {
                    HStack {
                        Text("Fatura bilgilerini kaydet").bold()
                        if faturaKaydediliyor { Spacer(); ProgressView() }
                    }
                }
                .disabled(faturaKaydediliyor)
            } footer: {
                if let yol = v.webPath {
                    Button("e-Fatura entegratör ayarları, logo, kaşe ve imza web panelinde") {
                        Task { await DVBPanelSafari.ac(yol, openURL) }
                    }
                    .font(.footnote)
                }
            }

            // ── Banka hesabı
            Section {
                if let h = v.payout, let etiket = h.statusLabel {
                    HStack {
                        Text("Durum")
                        Spacer()
                        Text(etiket).foregroundColor(h.status == "approved" ? DVBTheme.accent : (h.status == "rejected" ? .red : .orange))
                    }
                    if let r = h.rejectionReason, !r.isEmpty { Text(r).font(.footnote).foregroundColor(.red) }
                }
                Picker("Hesap türü", selection: $hesapTuru) {
                    ForEach(v.accountTypes, id: \.key) { t in Text(t.label).tag(t.key) }
                }
                TextField("Ad soyad / ünvan (hesap sahibi)", text: $hesapAdi)
                TextField("TCKN / VKN", text: $hesapKimlik).keyboardType(.numberPad)
                TextField("Vergi dairesi (isteğe bağlı)", text: $hesapVd)
                TextField("IBAN (TR ile başlar)", text: $iban).autocapitalization(.allCharacters).disableAutocorrection(true)
                TextField("Telefon (isteğe bağlı)", text: $hesapTelefon).keyboardType(.phonePad)
                TextField("E-posta (isteğe bağlı)", text: $hesapEposta).keyboardType(.emailAddress).autocapitalization(.none).disableAutocorrection(true)
                TextField("Adres (isteğe bağlı)", text: $hesapAdres)
                Button {
                    hesapOnayi = true
                } label: {
                    HStack {
                        Text("Banka hesabını kaydet").bold()
                        if hesapKaydediliyor { Spacer(); ProgressView() }
                    }
                }
                .disabled(!v.canEditPayout || hesapKaydediliyor || hesapAdi.trimmingCharacters(in: .whitespaces).isEmpty
                          || hesapKimlik.filter(\.isNumber).count < 10 || iban.filter { !$0.isWhitespace }.count != 26)
            } header: {
                Text("Banka hesabım (hakediş)")
            } footer: {
                Text(v.canEditPayout
                     ? "Hastalarınızın online ödemeleri bu hesaba aktarılır. Değişiklik onaydan sonra geçerli olur."
                     : "Banka hesabını yalnız hekimin kendisi değiştirebilir.")
            }
            .disabled(!v.canEditPayout)
        }
    }

    // MARK: - Ağ

    private func doldur(_ v: DVBOdemeFaturaBilgileri) {
        let f = v.billing
        unvan = f.invoiceTitle ?? ""
        mukellef = f.invoiceTaxpayerType
        vergiNo = f.taxNo ?? ""
        vergiDairesi = f.taxOffice ?? ""
        vergiDairesiKodu = f.taxOfficeCode
        faturaAdresi = f.invoiceAddress ?? ""
        faturaTelefon = f.invoicePhone ?? ""
        faturaEposta = f.invoiceEmail ?? ""
        efaturaMukellefi = f.isEinvoicePayer
        efaturaEtiketi = f.einvoiceAlias ?? ""
        varsayilanKdv = f.invoiceDefaultVat.map { DVBSayi.yaz($0) } ?? ""
        faturaNotu = f.invoiceNote ?? ""
        if let h = v.payout {
            hesapTuru = h.accountType ?? "individual"
            hesapAdi = h.legalName ?? ""
            hesapKimlik = h.idOrTaxNo ?? ""
            hesapVd = h.taxOffice ?? ""
            iban = h.iban ?? ""
            hesapTelefon = h.phone ?? ""
            hesapEposta = h.email ?? ""
            hesapAdres = h.address ?? ""
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBOdemeFaturaBilgileri = try await DVBAPI.shared.get("my/doctor/billing", token: token)
            veri = v
            doldur(v)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kirp(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func faturaKaydet() async {
        guard let token = session.token, !faturaKaydediliyor else { return }
        faturaKaydediliyor = true
        defer { faturaKaydediliyor = false }
        var govde: [String: Any] = [
            "invoice_taxpayer_type": mukellef,
            "invoice_title": kirp(unvan),
            "tax_no": vergiNo.filter(\.isNumber),
            "tax_office": kirp(vergiDairesi),
            "invoice_address": kirp(faturaAdresi),
            "invoice_phone": kirp(faturaTelefon),
            "invoice_email": kirp(faturaEposta),
            "is_einvoice_payer": efaturaMukellefi,
            "einvoice_alias": efaturaMukellefi ? kirp(efaturaEtiketi) : "",
            "invoice_note": kirp(faturaNotu),
        ]
        if let kod = vergiDairesiKodu { govde["tax_office_code"] = kod }
        if let k = DVBPara.coz(varsayilanKdv) { govde["invoice_default_vat"] = DVBPara.makine(k) } else { govde["invoice_default_vat"] = "" }
        do {
            let c: DVBOdemeFaturaCevabi = try await DVBAPI.shared.put("my/doctor/billing/invoice", body: govde, token: token)
            bilgi = c.message ?? "Fatura bilgileriniz kaydedildi."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func hesapKaydet() async {
        guard let token = session.token, !hesapKaydediliyor else { return }
        hesapKaydediliyor = true
        defer { hesapKaydediliyor = false }
        let govde: [String: Any] = [
            "account_type": hesapTuru,
            "legal_name": kirp(hesapAdi),
            "id_or_tax_no": hesapKimlik.filter(\.isNumber),
            "tax_office": kirp(hesapVd),
            "iban": iban.filter { !$0.isWhitespace }.uppercased(),
            "phone": kirp(hesapTelefon),
            "email": kirp(hesapEposta),
            "address": kirp(hesapAdres),
        ]
        do {
            let c: DVBOdemeFaturaCevabi = try await DVBAPI.shared.put("my/doctor/billing/payout", body: govde, token: token)
            bilgi = c.message ?? "Banka hesabı bilgileriniz kaydedildi. Onay sürecine alındı."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Vergi dairesi arama

struct DVBVergiDairesiAramaView: View {
    var secildi: (DVBVergiDairesi) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var arama = ""
    @State private var sonuclar: [DVBVergiDairesi] = []
    @State private var yukleniyor = false

    var body: some View {
        NavigationView {
            List {
                if yukleniyor && sonuclar.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if sonuclar.isEmpty {
                    Text(arama.count < 2 ? "Vergi dairesinin ya da ilin adını yazın." : "Sonuç yok.").foregroundColor(.secondary)
                } else {
                    ForEach(sonuclar) { vd in
                        Button {
                            secildi(vd)
                            dismiss()
                        } label: {
                            Text(vd.label).foregroundColor(.primary)
                        }
                    }
                }
            }
            .searchable(text: $arama, prompt: "Vergi dairesi ara")
            .navigationTitle("Vergi dairesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            }
            .task(id: arama) { await ara() }
        }
        .navigationViewStyle(.stack)
    }

    private func ara() async {
        let q = arama.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let token = session.token else { sonuclar = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let c: DVBVergiDairesiListesi = try await DVBAPI.shared.get("my/doctor/tax-offices", query: ["q": q], token: token)
            sonuclar = c.data
        } catch {
            sonuclar = []
        }
    }
}
