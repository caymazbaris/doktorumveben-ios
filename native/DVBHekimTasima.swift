import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000341 — RANDEVU TAŞIMA (hekim).
//
// Kullanıcı (8 Eki 2026): "takvim ekleme kısımlarını uygulamaya alalım online görüşmeleri de 3 günlük işleri de yapalm".
//
// Kural sunucuda ve web takvimiyle ORTAK (RandevuTasima): geçmişe taşınamaz, çakışan saat reddedilir, saat değişince
// hatırlatmalar yeniden kurulur ve hastaya "randevunuz taşındı" bildirimi gider. Boş saatler randevu eklemedeki uçtan
// (/my/doctor/booking-slots) bu randevunun hizmetiyle istenir; istenirse saat elle girilir. Süre değişmez.
// ═══════════════════════════════════════════════════════════════════════════════

private struct DVBTasimaSaatleri: Decodable {
    let date: String
    let slots: [String]
}

private struct DVBTasimaCevabi: Decodable {
    let ok: Bool
    let message: String?
}

struct DVBHekimTasimaView: View {
    let randevu: DVBHekimRandevu
    var tasindi: (String) -> Void = { _ in }

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var gun: Date
    @State private var saatler: [String] = []
    @State private var seciliSaat: String?
    @State private var saatlerYukleniyor = false
    @State private var saatHatasi: String?
    @State private var elleSaat = false
    @State private var elleSaatDegeri: Date
    @State private var kaydediliyor = false
    @State private var hata: String?

    init(randevu: DVBHekimRandevu, tasindi: @escaping (String) -> Void = { _ in }) {
        self.randevu = randevu
        self.tasindi = tasindi
        let baslangic = randevu.startsAt ?? Date()
        _gun = State(initialValue: max(baslangic, Calendar.current.startOfDay(for: Date())))
        _elleSaatDegeri = State(initialValue: baslangic)
        // Hizmeti olmayan (eski) randevuda boş saat listesi istenemez → doğrudan elle saat.
        _elleSaat = State(initialValue: randevu.serviceId == nil)
    }

    private var bugun: Date { Calendar.current.startOfDay(for: Date()) }

    /// Sunucu `starts_at`'i uygulama saat diliminde (Türkiye) okur: "2026-10-10 14:30".
    private var yeniBaslangic: String? {
        if elleSaat { return "\(DVBSaat.anahtar(gun)) \(DVBSaat.gun(elleSaatDegeri, "HH:mm"))" }
        guard let seciliSaat else { return nil }
        return "\(DVBSaat.anahtar(gun)) \(seciliSaat)"
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(randevu.patientName ?? "Hasta").font(.headline)
                        if let s = randevu.startsAt {
                            Text("Şu an: \(DVBSaat.gun(s, "d MMMM EEEE")) · \(DVBSaat.saat(randevu.startsAt))–\(DVBSaat.saat(randevu.endsAt))")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    DatePicker("Yeni gün", selection: $gun, in: bugun..., displayedComponents: .date)
                        .environment(\.timeZone, DVBTime.klinik)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                        .id(gun)
                    if !elleSaat { saatSecimi }
                    if randevu.serviceId != nil {
                        Toggle("Saati elle gir", isOn: $elleSaat)
                    }
                    if elleSaat {
                        DatePicker("Saat", selection: $elleSaatDegeri, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, DVBTime.klinik)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                    }
                } header: {
                    Text("Yeni tarih ve saat")
                } footer: {
                    Text("Randevu süresi değişmez. Taşıyınca hastaya bilgi gider ve hatırlatmalar yeni saate göre yeniden kurulur.")
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle("Randevuyu taşı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await tasi() }
                    } label: {
                        if kaydediliyor { ProgressView() } else { Text("Taşı").bold() }
                    }
                    .disabled(yeniBaslangic == nil || kaydediliyor)
                }
            }
            .task(id: DVBSaat.anahtar(gun)) { await saatleriYukle() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var saatSecimi: some View {
        if saatlerYukleniyor {
            ProgressView().frame(maxWidth: .infinity)
        } else if let saatHatasi {
            Text(saatHatasi).font(.footnote).foregroundColor(.red)
        } else if saatler.isEmpty {
            Text("Bu gün için boş saat yok. Başka gün seçin ya da saati elle girin.").font(.footnote).foregroundColor(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(saatler, id: \.self) { saat in
                    let secili = seciliSaat == saat
                    Button { seciliSaat = saat } label: {
                        Text(saat).font(.subheadline.monospacedDigit())
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(secili ? DVBTheme.brand : Color(.secondarySystemBackground))
                            .foregroundColor(secili ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(secili ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func saatleriYukle() async {
        seciliSaat = nil
        guard let token = session.token, let hizmet = randevu.serviceId else { saatler = []; return }
        saatlerYukleniyor = true
        defer { saatlerYukleniyor = false }
        do {
            let c: DVBTasimaSaatleri = try await DVBAPI.shared.get(
                "my/doctor/booking-slots", query: ["date": DVBSaat.anahtar(gun), "service_id": String(hizmet)], token: token
            )
            saatler = c.slots
            saatHatasi = nil
        } catch {
            guard let m = DVBError.mesaj(error) else { return }
            saatler = []
            saatHatasi = m
        }
    }

    private func tasi() async {
        guard let token = session.token, let yeni = yeniBaslangic, !kaydediliyor else { return }
        kaydediliyor = true
        defer { kaydediliyor = false }
        do {
            let c: DVBTasimaCevabi = try await DVBAPI.shared.post(
                "my/doctor/appointments/\(randevu.id)/reschedule", body: ["starts_at": yeni], token: token
            )
            hata = nil
            tasindi(c.message ?? "Randevu taşındı.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
