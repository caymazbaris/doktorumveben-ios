import SwiftUI

/// DVB-000269 — HEKİMDEN BAĞIMSIZ RANDEVU TALEBİ ("Doktor Bul").
///
/// Kullanıcı (30 Eyl 2026): "Doktordan bağımsız randevu talep et kısmı yapalım şehir branş vs ile talep edebilsin
/// sitede whatsapptan yapıldığı mantıkta". Sitedeki "Doktor Bul" sihirbazının (DVB-000234) uygulama karşılığı: kişi
/// hekim seçmez; branş + şehir (+ ilçe, ilgi alanı) söyler, ekip uygun hekimi bulup arar. Talep sitedekiyle AYNI
/// listeye hekimsiz olarak düşer.
///
/// Uygulamadaki diğer talep formlarıyla tutarlı: aynı ÜYELİK kuralı (ad soyad, e-posta, şehir, telefon + sözleşme;
/// sunucuda TalepUyeligi). Aranan şehir hastanın şehri olarak da alınır — form tek şehir sorar.
struct DVBDoktorBulView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock
    @ObservedObject private var secim = DVBKonumSecimi.shared

    @State private var branslar: [DVBSpecialty] = []
    @State private var iller: [DVBIl] = []
    @State private var ilceler: [DVBIlce] = []
    @State private var ilgiAlanlari: [DVBFiltreSecenekleri.Oge] = []

    @State private var bransId: Int?
    @State private var ilId: Int?
    @State private var ilceId: Int?
    @State private var ilgiAlaniId: Int?

    @State private var ad = ""
    @State private var telefon = ""
    @State private var eposta = ""
    @State private var riza = false
    @State private var sozlesme = false

    @State private var gonderiliyor = false
    @State private var hata: String?
    @State private var hesapVar = false
    @State private var girisAcik = false
    @State private var sonuc: DVBRequestResult?

    private var misafir: Bool { !session.isLoggedIn }

    private var gonderilebilir: Bool {
        let e = eposta.trimmingCharacters(in: .whitespaces)
        return bransId != nil && ilId != nil
            && ad.trimmingCharacters(in: .whitespaces).count >= 3
            && telefon.filter(\.isNumber).count >= 10
            && e.contains("@") && e.contains(".")
            && riza && (!misafir || sozlesme) && !gonderiliyor
    }

    var body: some View {
        NavigationView {
            Group {
                if let sonuc { onay(sonuc) } else { form }
            }
            .navigationTitle(sonuc == nil ? "Hekim bulalım" : "Talebiniz Alındı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sonuc == nil ? "Vazgeç" : "Kapat") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await hazirla() }
        .sheet(isPresented: $girisAcik, onDismiss: { doldur(); if session.isLoggedIn { hesapVar = false; hata = nil } }) {
            DVBAccountView().environmentObject(session).environmentObject(lock)
        }
    }

    private var form: some View {
        Form {
            Section {
                Text("Hangi hekime gideceğinizi bilmiyor musunuz? Branşı ve şehri seçin; ekibimiz size uygun hekimi bulup sizi arasın.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Ne arıyorsunuz?") {
                Picker("Branş", selection: $bransId) {
                    Text("Seçin").tag(Int?.none)
                    ForEach(branslar) { Text($0.name).tag(Int?.some($0.id)) }
                }
                Picker("Şehir", selection: Binding(get: { ilId }, set: { yeni in
                    ilId = yeni
                    ilceId = nil
                    Task { await ilceleriYukle() }
                })) {
                    Text("Seçin").tag(Int?.none)
                    ForEach(iller) { Text($0.name).tag(Int?.some($0.id)) }
                }
                if ilId != nil {
                    Picker("İlçe", selection: $ilceId) {
                        Text("Fark etmez").tag(Int?.none)
                        ForEach(ilceler) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                }
                if !ilgiAlanlari.isEmpty {
                    Picker("İlgi alanı", selection: $ilgiAlaniId) {
                        Text("Belirtmek istemiyorum").tag(Int?.none)
                        ForEach(ilgiAlanlari) { o in Text(o.name).tag(o.numara) }
                    }
                }
            }

            if misafir {
                Section {
                    Text("Talep göndermek için üyelik gerekir. Aşağıdaki bilgilerle üyeliğiniz oluşturulur.")
                        .font(.footnote)
                    Button("Zaten üye misiniz? Giriş yapın") { girisAcik = true }
                        .font(.footnote.weight(.semibold))
                }
            }

            Section("Bilgileriniz") {
                TextField("Ad Soyad", text: $ad).textContentType(.name).autocorrectionDisabled()
                TextField("Cep telefonu", text: $telefon).textContentType(.telephoneNumber).keyboardType(.phonePad)
                TextField("E-posta", text: $eposta)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Toggle(isOn: $riza) {
                    Text(misafir
                         ? "KVKK Aydınlatma Metni'ni okudum; Açık Rıza Metni kapsamında kişisel verilerimin işlenmesine ve talebim için benimle iletişime geçilmesine açık rıza veriyorum."
                         : "Talebimin iletilmesi için bilgilerimin işlenmesini onaylıyorum.")
                        .font(.footnote)
                }
                if misafir {
                    Toggle(isOn: $sozlesme) {
                        Text("Üyelik Sözleşmesi ve Gizlilik Politikası'nı okudum, kabul ediyorum.").font(.footnote)
                    }
                    Link("KVKK Aydınlatma Metni", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/kvkk-aydinlatma")).font(.footnote)
                    Link("Açık Rıza Metni", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/acik-riza")).font(.footnote)
                    Link("Üyelik Sözleşmesi", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/uyelik-sozlesmesi")).font(.footnote)
                }
            } footer: {
                if let hata {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hata).foregroundColor(.red)
                        if hesapVar { Button("Giriş yap") { girisAcik = true }.font(.footnote.weight(.semibold)) }
                    }
                }
            }

            Section {
                Button {
                    Task { await gonder() }
                } label: {
                    HStack {
                        Spacer()
                        if gonderiliyor { ProgressView().padding(.trailing, 6) }
                        Text(gonderiliyor ? "Gönderiliyor…" : (misafir ? "Üye Ol ve Talebi Gönder" : "Talebi Gönder")).bold()
                        Spacer()
                    }
                }
                .disabled(!gonderilebilir)
            }
        }
    }

    private func onay(_ s: DVBRequestResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(DVBTheme.brand)
            Text(s.message ?? "Talebiniz alındı.").font(.headline).multilineTextAlignment(.center)
            if let kod = s.request?.refCode {
                VStack(spacing: 4) {
                    Text("Talep numaranız").font(.caption).foregroundColor(.secondary)
                    Text(kod).font(.title3.monospaced().bold()).textSelection(.enabled)
                }
            }
            if s.uyelikAcildi == true {
                Text("Üyeliğiniz oluşturuldu. Hesabım › Parolamı unuttum adımıyla telefonunuza gelen kodla şifre belirleyip giriş yapabilirsiniz.")
                    .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .padding(12)
                    .background(DVBTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer()
        }
        .padding(28)
    }

    // MARK: - Veri

    private func hazirla() async {
        doldur()
        if ilId == nil { ilId = secim.il?.id; ilceId = secim.ilce?.id }
        if let l: [DVBSpecialty] = try? await DVBAPI.shared.get("specialties") { branslar = l }
        iller = await DVBCografya.iller()
        ilgiAlanlari = (await DVBFiltreSecenekleri.getir())?.expertises.filter { $0.numara != nil } ?? []
        await ilceleriYukle()
    }

    private func ilceleriYukle() async {
        guard let ilId, let il = iller.first(where: { $0.id == ilId }) else { ilceler = []; return }
        ilceler = await DVBCografya.ilceler(il)
        if let ilceId, !ilceler.contains(where: { $0.id == ilceId }) { self.ilceId = nil }
    }

    private func doldur() {
        guard let u = session.user else { return }
        if ad.isEmpty, let n = u.name { ad = n }
        if eposta.isEmpty, let m = u.email, !m.hasSuffix("@wa.doktorumveben.com"), !m.hasSuffix("@aday.doktorumveben.com") { eposta = m }
        if telefon.isEmpty, let p = u.phone { telefon = p }
    }

    private func gonder() async {
        gonderiliyor = true
        hata = nil
        defer { gonderiliyor = false }

        var govde: [String: Any] = [
            "name": ad.trimmingCharacters(in: .whitespaces),
            "phone": telefon,
            "email": eposta.trimmingCharacters(in: .whitespaces),
            "consent": true,
            "uyelik_surumu": 1,
        ]
        if let bransId { govde["specialty_id"] = bransId }
        if let ilId { govde["city_id"] = ilId }
        if let ilceId { govde["district_id"] = ilceId }
        if let ilgiAlaniId { govde["expertise_id"] = ilgiAlaniId }
        if misafir { govde["terms"] = sozlesme }

        do {
            sonuc = try await DVBAPI.shared.post("doktor-bul", body: govde, token: session.token)
        } catch DVBError.server(409, let mesaj) {
            hesapVar = true
            hata = mesaj ?? "Bu e-posta ya da telefonla bir üyeliğiniz var. Giriş yapıp talebinizi gönderin."
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
