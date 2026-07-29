import SwiftUI

/// Tur 235 — "Randevularım". Tur 234'te eklenen `?scope=upcoming|past` ile iki sekme.
///
/// Sunucu her randevuyu tek çağrıda TAM gönderiyor (bitiş saati, adres, koordinat,
/// hangi butonun gösterileceği) — Faz 4'teki cihaz takvimi ve çevrimdışı önbellek
/// bu yüzden ikinci istek atmadan çalışacak.
@MainActor
struct DVBAppointmentsView: View {

    @EnvironmentObject private var session: DVBSession

    @State private var scope = "upcoming"
    @State private var items: [DVBAppointment] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Group {
                if !session.isLoggedIn {
                    DVBLoginGate(title: "Randevularınızı görmek için giriş yapın")
                } else if loading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, items.isEmpty {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: error) {
                        Task { await load() }
                    }
                } else if items.isEmpty {
                    DVBStateView(
                        icon: "calendar",
                        title: scope == "upcoming" ? "Yaklaşan randevunuz yok" : "Geçmiş randevunuz yok",
                        message: scope == "upcoming" ? "Ara sekmesinden hekim bulup randevu alabilirsiniz." : nil
                    )
                } else {
                    List(items) { appointment in
                        NavigationLink(destination: DVBAppointmentDetailView(appointment: appointment, onChange: { updated in
                            if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
                        })) {
                            row(appointment)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .safeAreaInset(edge: .top) {
                if session.isLoggedIn {
                    Picker("", selection: $scope) {
                        Text("Yaklaşan").tag("upcoming")
                        Text("Geçmiş").tag("past")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .navigationTitle("Randevularım")
            .onChange(of: scope) { _ in Task { await load() } }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ a: DVBAppointment) -> some View {
        HStack(spacing: 12) {
            DVBAvatar(url: a.doctorAvatar, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.doctor ?? "—").font(.headline).lineLimit(1)
                if let starts = a.startsAt {
                    Text(starts.dvbLong).font(.subheadline).foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(a.statusLabel ?? a.status ?? "")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    if a.isOnline == true {
                        Label("Online", systemImage: "video").font(.caption2).foregroundColor(DVBTheme.brand)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard session.isLoggedIn, let token = session.token else { items = []; return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let list: DVBList<DVBAppointment> = try await DVBAPI.shared.get(
                "my/appointments", query: ["scope": scope], token: token
            )
            items = list.data
        } catch DVBError.unauthorized {
            session.signOut()
        } catch {
            items = []
            self.error = (error as? DVBError)?.errorDescription ?? "Bilinmeyen hata."
        }
    }
}

// MARK: - Detay

@MainActor
struct DVBAppointmentDetailView: View {

    let appointment: DVBAppointment
    var onChange: (DVBAppointment) -> Void

    @EnvironmentObject private var session: DVBSession
    @State private var current: DVBAppointment
    @State private var busy = false
    @State private var toast: String?

    init(appointment: DVBAppointment, onChange: @escaping (DVBAppointment) -> Void) {
        self.appointment = appointment
        self.onChange = onChange
        _current = State(initialValue: appointment)
    }

    var body: some View {
        List {
            Section {
                labelled("Hekim", current.doctor)
                labelled("Branş", current.doctorSpecialty)
                labelled("Hizmet", current.type)
                labelled("Tarih", current.startsAt?.dvbLong)
                if let dk = current.durationMinutes { labelled("Süre", "\(dk) dakika") }
                labelled("Durum", current.statusLabel ?? current.status)
                labelled("Randevu no", current.no)
            }

            if let loc = current.location, (loc.address?.isEmpty == false) {
                Section("Adres") {
                    Text(loc.address ?? "")
                    if let phone = loc.phone, !phone.isEmpty {
                        Link(phone, destination: URL(string: "tel://\(phone.filter { $0.isNumber })")!)
                    }
                }
            }

            if current.canMarkComing == true || current.canRequestCancel == true {
                Section {
                    if current.canMarkComing == true {
                        Button { Task { await act("coming") } } label: {
                            Label("Geleceğim", systemImage: "checkmark.circle")
                        }
                    }
                    if current.canRequestCancel == true {
                        Button(role: .destructive) { Task { await act("cancel-request") } } label: {
                            Label("İptal talebi gönder", systemImage: "xmark.circle")
                        }
                    }
                }
                .disabled(busy)
            }

            // Tur 238 — cihaz yetenekleri. Web sayfasının yapamayacağı iki iş:
            // randevuyu telefonun takvimine yazmak ve çevrimdışı çalışan yerel hatırlatma.
            if let baslangic = current.startsAt, current.isPast != true {
                Section("Telefonuma ekle") {
                    Button {
                        Task {
                            toast = await DVBCalendarKit.takvimeEkle(
                                baslik: "\(current.doctor ?? "Hekim") randevusu",
                                baslangic: baslangic,
                                sure: current.durationMinutes ?? 30,
                                not: current.no.map { "Doktorumveben · Randevu no \($0)" }
                            )
                        }
                    } label: {
                        Label("Takvimime ekle", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        Task {
                            toast = await DVBCalendarKit.hatirlatmaKur(
                                baslik: "Yarın randevunuz var",
                                govde: "\(current.doctor ?? "Hekim") · \(baslangic.dvbLong)",
                                randevuZamani: baslangic,
                                kimlik: current.no ?? String(current.id)
                            )
                        }
                    } label: {
                        Label("Bir gün önce hatırlat", systemImage: "bell.badge")
                    }
                }
            }

            if let toast {
                Section { Text(toast).font(.subheadline).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Randevu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labelled(_ title: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                HStack {
                    Text(title).foregroundColor(.secondary)
                    Spacer()
                    Text(value).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func act(_ action: String) async {
        guard let token = session.token else { return }
        busy = true
        defer { busy = false }
        do {
            let res: DVBAppointmentAction = try await DVBAPI.shared.post(
                "my/appointments/\(current.id)/\(action)", token: token
            )
            current = res.data
            onChange(res.data)
            toast = res.message
        } catch DVBError.unauthorized {
            session.signOut()
        } catch {
            toast = (error as? DVBError)?.errorDescription ?? "İşlem tamamlanamadı."
        }
    }
}
