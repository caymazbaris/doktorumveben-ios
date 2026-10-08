import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000343 — HEKİM PROFİL DÜZENLEME.
//
// Kullanıcı (8 Eki 2026): "profil düzenleme, muhasebe ve e-Fatura. da yapalım".
//
// Kurallar sunucuda (HekimProfilApiController, web profil sayfasıyla aynı doğrulama). Uygulama KISMİ günceller: yalnız bu
// ekrandaki alanlar gider; SEO, SSS, sosyal bağlantılar ve Google alanları web panelinde kalır ve dokunulmaz.
// İlgi alanları web'deki gibi iki listedir: "ilgilendiğim" ve "ilgilenmediğim" (aynı konu ikisinde birden olamaz).
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBHekimProfilVerisi: Decodable {
    let profile: Profil
    let specialties: [Secenek]
    let expertisePool: [Secenek]
    let webPath: String?

    struct Secenek: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
    }

    struct Profil: Decodable {
        let displayName: String?
        let title: String?
        let phone: String?
        let gender: String?
        let about: String?
        let educationSchool: String?
        let graduationYear: Int?
        let experienceYears: Int?
        let languages: [String]?
        let primarySpecialtyId: Int?
        let hospitalName: String?
        let isPublished: Bool
        let onlineMeetingEnabled: Bool
        let onlineMeetingFee: Double?
        let whatsappEnabled: Bool
        let whatsappNumber: String?
        let autoConfirm: Bool
        let avatar: String?
        let profileUrl: String?
        let expertises: [Int]
        let ilgilenmedigim: [Int]

        enum CodingKeys: String, CodingKey {
            case title, phone, gender, about, languages, avatar, expertises, ilgilenmedigim
            case displayName = "display_name"
            case educationSchool = "education_school"
            case graduationYear = "graduation_year"
            case experienceYears = "experience_years"
            case primarySpecialtyId = "primary_specialty_id"
            case hospitalName = "hospital_name"
            case isPublished = "is_published"
            case onlineMeetingEnabled = "online_meeting_enabled"
            case onlineMeetingFee = "online_meeting_fee"
            case whatsappEnabled = "whatsapp_enabled"
            case whatsappNumber = "whatsapp_number"
            case autoConfirm = "auto_confirm"
            case profileUrl = "profile_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case profile, specialties
        case expertisePool = "expertise_pool"
        case webPath = "web_path"
    }
}

private struct DVBProfilCevabi: Decodable {
    let ok: Bool?
    let message: String?
}

private struct DVBAvatarCevabi: Decodable {
    let ok: Bool
    let message: String?
    let avatar: String?
}

struct DVBHekimProfilView: View {
    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var veri: DVBHekimProfilVerisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var kaydediliyor = false
    @State private var fotoAcik = false
    @State private var fotoYukleniyor = false
    @State private var avatar: String?

    // Düzenlenen alanlar
    @State private var unvan = ""
    @State private var telefon = ""
    @State private var cinsiyet: String?
    @State private var hakkinda = ""
    @State private var okul = ""
    @State private var mezuniyet = ""
    @State private var deneyim = 0
    @State private var diller = ""
    @State private var bransId: Int?
    @State private var kurum = ""
    @State private var yayinda = true
    @State private var otomatikOnay = false
    @State private var online = false
    @State private var onlineUcret = ""
    @State private var whatsappAcik = false
    @State private var whatsappNo = ""
    @State private var ilgili: Set<Int> = []
    @State private var ilgisiz: Set<Int> = []

    var body: some View {
        Group {
            if let v = veri {
                form(v)
            } else if let hata {
                DVBStateView(icon: "person.crop.circle.badge.exclamationmark", title: "Profil alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Profilim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await kaydet() }
                } label: {
                    if kaydediliyor { ProgressView() } else { Text("Kaydet").bold() }
                }
                .disabled(veri == nil || kaydediliyor)
            }
        }
        .task { await yukle() }
        .alert("Profil", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .sheet(isPresented: $fotoAcik) {
            DVBFotoSecici(kapat: { fotoAcik = false }) { resim in
                Task { await fotoYukle(resim) }
            }
        }
    }

    private func form(_ v: DVBHekimProfilVerisi) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AsyncImage(url: URL(string: avatar ?? "")) { resim in
                        resim.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.profile.displayName ?? "").font(.headline)
                        Button {
                            fotoAcik = true
                        } label: {
                            if fotoYukleniyor { ProgressView() } else { Text("Fotoğrafı değiştir") }
                        }
                        .buttonStyle(.borderless)
                        .disabled(fotoYukleniyor)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Kimlik") {
                TextField("Unvan (ör. Uzm. Dr.)", text: $unvan)
                Picker("Cinsiyet", selection: $cinsiyet) {
                    Text("Belirtilmemiş").tag(String?.none)
                    Text("Kadın").tag(String?.some("female"))
                    Text("Erkek").tag(String?.some("male"))
                }
                DVBAramaliSecici(
                    baslik: "Ana branş",
                    secenekler: v.specialties.map { DVBSecenek(id: $0.id, ad: $0.name) },
                    secili: $bransId,
                    bosEtiket: nil
                )
                TextField("Çalıştığı kurum (hastane / klinik)", text: $kurum)
            }

            Section {
                TextField("İletişim telefonu", text: $telefon).keyboardType(.phonePad)
                Toggle("WhatsApp'tan yazılabilsin", isOn: $whatsappAcik)
                if whatsappAcik {
                    TextField("WhatsApp numarası", text: $whatsappNo).keyboardType(.phonePad)
                }
            } header: {
                Text("İletişim")
            } footer: {
                Text("WhatsApp kapatılınca numara da profilden kaldırılır.")
            }

            Section("Hakkımda") {
                TextEditor(text: $hakkinda).frame(minHeight: 120)
            }

            Section {
                TextField("Mezun olduğu okul", text: $okul)
                TextField("Mezuniyet yılı", text: $mezuniyet).keyboardType(.numberPad)
                Stepper("Deneyim: \(deneyim) yıl", value: $deneyim, in: 0...80)
                TextField("Konuştuğu diller (virgülle)", text: $diller)
            } header: {
                Text("Eğitim ve deneyim")
            }

            Section {
                NavigationLink(destination: DVBIlgiAlaniSecimView(havuz: v.expertisePool, ilgili: $ilgili, ilgisiz: $ilgisiz)) {
                    HStack {
                        Text("İlgi alanları")
                        Spacer()
                        Text("\(ilgili.count) seçili").foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Hastalar sizi bu konularla bulur. İlgilenmediğiniz konuları da işaretleyebilirsiniz.")
            }

            Section {
                Toggle("Profilim yayında", isOn: $yayinda)
                Toggle("Randevuları otomatik onayla", isOn: $otomatikOnay)
                Toggle("Online görüşme yapıyorum", isOn: $online)
                if online {
                    TextField("Online görüşme ücreti (ör. 1500,00)", text: $onlineUcret).keyboardType(.decimalPad)
                }
            } header: {
                Text("Randevu ve görünürlük")
            }

            Section {
                if let u = v.profile.profileUrl, let url = URL(string: u) {
                    Button { openURL(url) } label: { Label("Profilimi görüntüle", systemImage: "person.text.rectangle") }
                }
                if let yol = v.webPath {
                    Button { Task { await webdeAc(yol) } } label: {
                        Label("SEO, SSS ve sosyal bağlantılar (web)", systemImage: "safari")
                    }
                }
            }
        }
    }

    // MARK: - Ağ

    private func doldur(_ p: DVBHekimProfilVerisi.Profil) {
        unvan = p.title ?? ""
        telefon = p.phone ?? ""
        cinsiyet = p.gender
        hakkinda = p.about ?? ""
        okul = p.educationSchool ?? ""
        mezuniyet = p.graduationYear.map(String.init) ?? ""
        deneyim = p.experienceYears ?? 0
        diller = (p.languages ?? []).joined(separator: ", ")
        bransId = p.primarySpecialtyId
        kurum = p.hospitalName ?? ""
        yayinda = p.isPublished
        otomatikOnay = p.autoConfirm
        online = p.onlineMeetingEnabled
        onlineUcret = p.onlineMeetingFee.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        whatsappAcik = p.whatsappEnabled
        whatsappNo = p.whatsappNumber ?? ""
        ilgili = Set(p.expertises)
        ilgisiz = Set(p.ilgilenmedigim)
        avatar = p.avatar
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBHekimProfilVerisi = try await DVBAPI.shared.get("my/doctor/profile", token: token)
            veri = v
            doldur(v.profile)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    /// Boş metin → null (sunucu alanı boşaltır); dolu → kırpılmış metin.
    private func metin(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? NSNull() : t
    }

    private func kaydet() async {
        guard let token = session.token, !kaydediliyor else { return }
        let yil = mezuniyet.trimmingCharacters(in: .whitespaces)
        if !yil.isEmpty && Int(yil) == nil {
            bilgi = "Mezuniyet yılı dört haneli bir yıl olmalı."
            return
        }
        kaydediliyor = true
        defer { kaydediliyor = false }

        var govde: [String: Any] = [
            "title": metin(unvan),
            "phone": metin(telefon),
            "about": metin(hakkinda),
            "education_school": metin(okul),
            "graduation_year": Int(yil).map { $0 as Any } ?? NSNull(),
            "experience_years": deneyim,
            "languages": diller.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            "hospital_name": metin(kurum),
            "is_published": yayinda,
            "auto_confirm": otomatikOnay,
            "online_meeting_enabled": online,
            "whatsapp_enabled": whatsappAcik,
            "expertises": Array(ilgili),
            "ilgilenmedigim": Array(ilgisiz),
        ]
        if let cinsiyet { govde["gender"] = cinsiyet }
        if let bransId { govde["primary_specialty_id"] = bransId }
        if whatsappAcik { govde["whatsapp_number"] = metin(whatsappNo) }
        if let u = DVBPara.coz(onlineUcret) {
            govde["online_meeting_fee"] = DVBPara.makine(u)
        } else if onlineUcret.trimmingCharacters(in: .whitespaces).isEmpty {
            govde["online_meeting_fee"] = NSNull()
        }

        do {
            let c: DVBProfilCevabi = try await DVBAPI.shared.patch("my/doctor/profile", body: govde, token: token)
            bilgi = c.message ?? "Profil güncellendi."
            await yukle()
            await session.hekimiYukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func fotoYukle(_ resim: UIImage) async {
        guard let token = session.token, let veri = DVBGorsel.jpeg(resim) else { return }
        fotoYukleniyor = true
        defer { fotoYukleniyor = false }
        do {
            let c: DVBAvatarCevabi = try await DVBAPI.shared.yukle(
                "my/doctor/profile/avatar", alan: "avatar", dosya: veri, dosyaAdi: "profil.jpg", mime: "image/jpeg", token: token
            )
            avatar = c.avatar
            bilgi = c.message ?? "Profil fotoğrafı güncellendi."
            await session.hekimiYukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func webdeAc(_ yol: String) async {
        guard let hedef = URL(string: yol, relativeTo: DVBConfig.webBase)?.absoluteURL else { return }
        let adres = await DVBWebOturum.kopruAdresi(hedef) ?? hedef
        await MainActor.run { openURL(adres) }
    }
}

// MARK: - İlgi alanı seçimi

/// Her konu üç durumdan birinde: ilgileniyorum (yeşil), ilgilenmiyorum (kırmızı), seçili değil. Dokunuş sırayla değiştirir.
struct DVBIlgiAlaniSecimView: View {
    let havuz: [DVBHekimProfilVerisi.Secenek]
    @Binding var ilgili: Set<Int>
    @Binding var ilgisiz: Set<Int>
    @State private var arama = ""

    private var liste: [DVBHekimProfilVerisi.Secenek] {
        let q = DVBArama.katla(arama.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return havuz }
        return havuz.filter { DVBArama.katla($0.name).contains(q) }
    }

    var body: some View {
        List {
            Section {
                ForEach(liste) { e in
                    Button {
                        degistir(e.id)
                    } label: {
                        HStack {
                            Text(e.name).foregroundColor(.primary)
                            Spacer()
                            if ilgili.contains(e.id) {
                                Label("İlgileniyorum", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundColor(DVBTheme.accent)
                            } else if ilgisiz.contains(e.id) {
                                Label("İlgilenmiyorum", systemImage: "minus.circle.fill").labelStyle(.iconOnly).foregroundColor(.red)
                            } else {
                                Image(systemName: "circle").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Bir kez dokunun: ilgileniyorum. İki kez: ilgilenmiyorum. Üç kez: seçimi kaldır. Değişiklikler profilde Kaydet'e basınca saklanır.")
            }
        }
        .searchable(text: $arama, prompt: "Konu ara")
        .navigationTitle("İlgi alanları")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func degistir(_ id: Int) {
        if ilgili.contains(id) {
            ilgili.remove(id)
            ilgisiz.insert(id)
        } else if ilgisiz.contains(id) {
            ilgisiz.remove(id)
        } else {
            ilgili.insert(id)
        }
    }
}
