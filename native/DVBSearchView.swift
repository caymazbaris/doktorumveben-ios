import SwiftUI

struct DVBSpecialty: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
}

/// Tur 235 — Hekim arama. Giriş GEREKTİRMEZ; uygulamayı ilk açan (ve App Store
/// denetçisi) hemen gerçek içerik görür.
@MainActor
struct DVBSearchView: View {

    @State private var query = ""
    @State private var specialties: [DVBSpecialty] = []
    @State private var selectedSpecialty: DVBSpecialty?
    @State private var doctors: [DVBDoctor] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            Group {
                if loading && doctors.isEmpty {
                    ProgressView("Hekimler getiriliyor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, doctors.isEmpty {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: error) {
                        reload()
                    }
                } else if doctors.isEmpty {
                    DVBStateView(
                        icon: "magnifyingglass",
                        title: "Sonuç yok",
                        message: "Farklı bir isim ya da branş deneyin."
                    )
                } else {
                    List(doctors) { doctor in
                        NavigationLink(destination: DVBDoctorDetailView(doctor: doctor)) {
                            DVBDoctorRow(doctor: doctor)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .top) { specialtyChips }
            .navigationTitle("Hekim ara")
            .searchable(text: $query, prompt: "İsim ya da branş")
            .onChange(of: query) { _ in debouncedReload() }
            .task {
                await loadSpecialties()
                if doctors.isEmpty { reload() }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var specialtyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tümü", active: selectedSpecialty == nil) {
                    selectedSpecialty = nil
                    reload()
                }
                ForEach(specialties) { s in
                    chip(title: s.name, active: selectedSpecialty?.id == s.id) {
                        selectedSpecialty = selectedSpecialty?.id == s.id ? nil : s
                        reload()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? DVBTheme.brand : Color(.secondarySystemBackground))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Veri

    private func loadSpecialties() async {
        // Uç sarmalayıcısız DÜZ dizi döndürüyor (DoctorApiController::specialties).
        if let list: [DVBSpecialty] = try? await DVBAPI.shared.get("specialties") {
            specialties = list
        }
    }

    /// Her tuşa basışta istek atmayalım: son yazımdan 350 ms sonra ara.
    private func debouncedReload() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { reload() }
        }
    }

    private func reload() {
        searchTask?.cancel()
        searchTask = Task {
            loading = true
            error = nil
            defer { loading = false }

            var params: [String: String] = [:]
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { params["q"] = q }
            if let slug = selectedSpecialty?.slug { params["specialty"] = slug }

            do {
                let page: DVBDoctorPage = try await DVBAPI.shared.get("doctors", query: params)
                if !Task.isCancelled { doctors = page.data }
            } catch {
                if !Task.isCancelled {
                    doctors = []
                    self.error = (error as? DVBError)?.errorDescription ?? "Bilinmeyen hata."
                }
            }
        }
    }
}

// MARK: - Satır

struct DVBDoctorRow: View {
    let doctor: DVBDoctor

    var body: some View {
        HStack(spacing: 12) {
            DVBAvatar(url: doctor.avatar, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(doctor.name ?? "—")
                        .font(.headline)
                        .lineLimit(1)
                    if doctor.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(DVBTheme.brand)
                    }
                }
                if let specialty = doctor.specialty {
                    Text(specialty)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if let district = doctor.district {
                        Label(district, systemImage: "mappin.and.ellipse")
                    }
                    if let count = doctor.ratingCount, count > 0, let rating = doctor.rating {
                        Label(String(format: "%.1f (%d)", rating, count), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Uzak avatar; yoksa baş harf. `AsyncImage` iOS 15'ten beri var, ek paket gerekmez.
struct DVBAvatar: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "person.fill").foregroundColor(.secondary)
        }
    }
}
