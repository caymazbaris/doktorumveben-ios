import SwiftUI

/// DVB-000110 — ADAY HEKİM İÇİN NATIVE RANDEVU TALEBİ.
///
/// NEDEN VAR — App Store 4.2.2 reddinin ölçülen kök nedeni:
/// Yayındaki 165.985 hekimin 165.983'ü aday (05.09.2026 sayımı). Aday hekimde online
/// takvim olmadığı için tek eylem "Randevu Talebi"ydi ve o da DVBWebSheet ile WEB
/// açıyordu. Yani reviewer hangi hekime dokunursa dokunsun uygulamanın ANA eyleminde
/// tarayıcı görüyordu. Apple'ın 31.07.2026 tarihli reddi bunu birebir tarif ediyor:
/// "the app only includes links, images, or content aggregated from the Internet with
/// limited or no native functionality".
///
/// Bu ekran o akışı uygulamanın içine alır: hasta hiç web görmeden talebini bırakır.
struct DVBRequestView: View {

    let doctorSlug: String
    let doctorName: String

    @Environment(\.dismiss) private var dismiss

    @State private var ad = ""
    @State private var telefon = ""
    @State private var eposta = ""
    @State private var tercihTarih = Date()
    @State private var tarihSecili = false
    @State private var tercihDilim: String? = nil
    @State private var ilkZiyaret = false
    @State private var not = ""
    @State private var riza = false

    @State private var gonderiliyor = false
    @State private var hata: String? = nil
    @State private var sonuc: DVBRequestResult? = nil

    /// Sunucudaki AppointmentRequest::SLOTS ile aynı anahtarlar.
    private let dilimler: [(String, String)] = [
        ("morning", "Sabah"),
        ("afternoon", "Öğleden sonra"),
        ("evening", "Akşam"),
    ]

    private var gonderilebilir: Bool {
        ad.trimmingCharacters(in: .whitespaces).count >= 3
            && telefon.filter(\.isNumber).count >= 10
            && riza
            && !gonderiliyor
    }

    var body: some View {
        NavigationStack {
            Group {
                if let sonuc {
                    onayEkrani(sonuc)
                } else {
                    form
                }
            }
            .navigationTitle(sonuc == nil ? "Randevu Talebi" : "Talebiniz Alındı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sonuc == nil ? "Vazgeç" : "Kapat") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                Text(doctorName).font(.headline)
                Text("Bu hekimin çevrimiçi takvimi yok. Bilgilerinizi bırakın, ekibimiz sizi arayıp randevunuzu oluştursun.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Bilgileriniz") {
                TextField("Ad Soyad", text: $ad)
                    .textContentType(.name)
                    .autocorrectionDisabled()

                TextField("Cep telefonu", text: $telefon)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)

                TextField("E-posta (isteğe bağlı)", text: $eposta)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Tercihiniz (isteğe bağlı)") {
                Toggle("Tarih belirtmek istiyorum", isOn: $tarihSecili.animation())
                if tarihSecili {
                    DatePicker(
                        "Tercih ettiğim gün",
                        selection: $tercihTarih,
                        in: Date()...Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
                        displayedComponents: .date
                    )
                }

                Picker("Gün içi tercih", selection: $tercihDilim) {
                    Text("Farketmez").tag(String?.none)
                    ForEach(dilimler, id: \.0) { Text($0.1).tag(String?.some($0.0)) }
                }

                Toggle("İlk kez gideceğim", isOn: $ilkZiyaret)
            }

            Section {
                TextField("Eklemek istedikleriniz", text: $not, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Not (isteğe bağlı)")
            } footer: {
                // Sunucudaki web formuyla aynı uyarı — sağlık verisi serbest metne yazılmasın.
                Text("Lütfen sağlık bilgilerinizi buraya yazmayın; ekibimiz sizi arayacak.")
            }

            Section {
                Toggle(isOn: $riza) {
                    Text("Talebimin iletilmesi için bilgilerimin işlenmesini onaylıyorum.")
                        .font(.footnote)
                }
            } footer: {
                if let hata {
                    Text(hata).foregroundColor(.red)
                }
            }

            Section {
                Button {
                    Task { await gonder() }
                } label: {
                    HStack {
                        Spacer()
                        if gonderiliyor { ProgressView().padding(.trailing, 6) }
                        Text(gonderiliyor ? "Gönderiliyor…" : "Talebi Gönder").bold()
                        Spacer()
                    }
                }
                .disabled(!gonderilebilir)
            }
        }
    }

    // MARK: - Onay

    private func onayEkrani(_ s: DVBRequestResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(DVBTheme.brand)

            Text(s.message ?? "Talebiniz alındı.")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let kod = s.request?.refCode {
                VStack(spacing: 4) {
                    Text("Talep numaranız").font(.caption).foregroundColor(.secondary)
                    Text(kod).font(.title3.monospaced().bold()).textSelection(.enabled)
                }
                .padding(.top, 4)
            }

            Text("Ekibimiz en kısa sürede sizi arayacak.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(28)
    }

    // MARK: - Gönderim

    private func gonder() async {
        gonderiliyor = true
        hata = nil

        var govde: [String: Any] = [
            "name": ad.trimmingCharacters(in: .whitespaces),
            "phone": telefon,
            "consent": true,
            "is_first_visit": ilkZiyaret,
        ]
        if !eposta.trimmingCharacters(in: .whitespaces).isEmpty {
            govde["email"] = eposta.trimmingCharacters(in: .whitespaces)
        }
        if tarihSecili {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = DVBTime.klinik
            f.dateFormat = "yyyy-MM-dd"
            govde["preferred_date"] = f.string(from: tercihTarih)
        }
        if let tercihDilim { govde["preferred_slot"] = tercihDilim }
        if !not.trimmingCharacters(in: .whitespaces).isEmpty {
            govde["note"] = not.trimmingCharacters(in: .whitespaces)
        }

        do {
            let cevap: DVBRequestResult = try await DVBAPI.shared.post(
                "doctors/\(doctorSlug)/request", body: govde
            )
            sonuc = cevap
        } catch {
            // 422 gövdesindeki sunucu mesajı DVBError.server içinde taşınıyor.
            hata = (error as? LocalizedError)?.errorDescription
                ?? "Talebiniz gönderilemedi. Lütfen tekrar deneyin."
        }

        gonderiliyor = false
    }
}
