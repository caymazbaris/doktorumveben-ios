import Foundation

/// Tur 235 — Sunucu sözleşmesinin Swift karşılığı.
///
/// Alan adları Tur 234'te yazılan `app/Http/Resources/*` çıktılarıyla BİREBİR aynı.
/// Sunucu eski anahtarları asla kaldırmayacağına söz verdi (mağaza güncellemesi
/// günler sürdüğü için eski sürümler ayakta kalmalı) — bu yüzden burada da
/// yeni alanlar EKLENİR, mevcutlar yeniden adlandırılmaz.
///
/// Tümü `Optional`: sunucu bir alanı boş bırakırsa uygulama çökmemeli, o satırı
/// göstermemeli. Sağlık verisinde "yanlış göster" > "hiç gösterme" değildir.

// MARK: - Sarmalayıcılar

struct DVBList<T: Decodable>: Decodable {
    let data: [T]
}

struct DVBSingle<T: Decodable>: Decodable {
    let data: T
}

struct DVBMessage: Decodable {
    let message: String?
}

// MARK: - Doktor (public arama)

struct DVBDoctor: Decodable, Identifiable {
    let slug: String
    let name: String?
    let specialty: String?
    let avatar: String?
    let rating: Double?
    let ratingCount: Int?
    let isVerified: Bool?
    let district: String?
    let experience: Int?
    let distanceKm: Double?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, specialty, avatar, rating, district, experience
        case ratingCount = "rating_count"
        case isVerified = "is_verified"
        case distanceKm = "distance_km"
    }
}

struct DVBDoctorPage: Decodable {
    let data: [DVBDoctor]
    let meta: Meta?

    struct Meta: Decodable {
        let currentPage: Int?
        let lastPage: Int?
        let total: Int?

        enum CodingKeys: String, CodingKey {
            case total
            case currentPage = "current_page"
            case lastPage = "last_page"
        }
    }
}

// MARK: - Randevu

struct DVBAppointment: Decodable, Identifiable {
    let id: Int
    let no: String?
    let doctor: String?
    let patient: String?
    let type: String?
    let startsAt: Date?
    let endsAt: Date?
    let durationMinutes: Int?
    let status: String?
    let statusLabel: String?
    let patientAction: String?
    let channel: String?
    let isOnline: Bool?
    let isPast: Bool?
    let doctorSlug: String?
    let doctorAvatar: String?
    let doctorSpecialty: String?
    let location: Location?
    let canMarkComing: Bool?
    let canRequestCancel: Bool?

    struct Location: Decodable {
        let name: String?
        let address: String?
        let district: String?
        let city: String?
        let phone: String?
        let lat: Double?
        let lng: Double?
    }

    enum CodingKeys: String, CodingKey {
        case id, no, doctor, patient, type, status, channel, location
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case durationMinutes = "duration_minutes"
        case statusLabel = "status_label"
        case patientAction = "patient_action"
        case isOnline = "is_online"
        case isPast = "is_past"
        case doctorSlug = "doctor_slug"
        case doctorAvatar = "doctor_avatar"
        case doctorSpecialty = "doctor_specialty"
        case canMarkComing = "can_mark_coming"
        case canRequestCancel = "can_request_cancel"
    }
}

/// Eylem uçlarının yanıtı: mesaj + güncel randevu (istemci ikinci istek atmasın).
struct DVBAppointmentAction: Decodable {
    let message: String?
    let data: DVBAppointment
}

// MARK: - Bildirim

struct DVBNotification: Decodable, Identifiable {
    let id: Int
    let type: String?
    let title: String?
    let body: String?
    let url: String?
    let isRead: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, url
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

struct DVBNotificationPage: Decodable {
    let data: [DVBNotification]
    let meta: Meta?

    struct Meta: Decodable {
        let unread: Int?
    }
}

// MARK: - Belge / Onam

struct DVBDocument: Decodable, Identifiable {
    let id: Int
    let categoryLabel: String?
    let title: String?
    let mime: String?
    let humanSize: String?
    let doctor: String?
    let createdAt: Date?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, mime, doctor
        case categoryLabel = "category_label"
        case humanSize = "human_size"
        case createdAt = "created_at"
        case downloadUrl = "download_url"
    }
}

// MARK: - Oturum

struct DVBUser: Decodable {
    let id: Int
    let name: String?
    let email: String?
    let phone: String?
}

/// `POST /auth/login` — 2FA açık hesaplarda jeton YERİNE `requires_otp` döner.
struct DVBLoginResponse: Decodable {
    let token: String?
    let user: DVBUser?
    let requiresOtp: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case token, user, message
        case requiresOtp = "requires_otp"
    }
}

struct DVBMe: Decodable {
    let user: DVBUser
}

// MARK: - Coğrafya

struct DVBCity: Decodable, Identifiable {
    let id: Int
    let name: String
    let slug: String
}

// MARK: - Randevu talebi (DVB-000110)

/// POST /doctors/{slug}/request yanıtı.
///
/// Aday hekimde (yayındaki hekimlerin %100'ü) randevu ALINMAZ, TALEP bırakılır.
/// Onay metni sunucudan gelir: kural değişince mağaza güncellemesi beklemeyelim diye.
struct DVBRequestResult: Decodable {
    let request: Detail?
    let message: String?

    struct Detail: Decodable {
        let refCode: String?
        let status: String?
        let doctorName: String?
        let preferredDate: String?
        let preferredSlot: String?

        enum CodingKeys: String, CodingKey {
            case status
            case refCode = "ref_code"
            case doctorName = "doctor_name"
            case preferredDate = "preferred_date"
            case preferredSlot = "preferred_slot"
        }
    }
}

// MARK: - Ana ekran widget'ı (DVB-000111)

/// GET /my/doctor/agenda yanıtı. Tek uç iki rol:
///   role == "doctor"  → bugünkü ajanda, hasta adları MASKELİ ("Ba*** Ca***")
///   role == "patient" → kendi yaklaşan randevusu, hekim adı açık
struct DVBAgenda: Codable {
    let role: String?
    let title: String?
    let count: Int?
    let next: Entry?
    let items: [Entry]?
    let refreshAfterSeconds: Int?

    struct Entry: Codable, Identifiable {
        let time: String?
        let date: String?
        let name: String?
        let status: String?

        var id: String { (date ?? "") + (time ?? "") + (name ?? "") }
    }

    enum CodingKeys: String, CodingKey {
        case role, title, count, next, items
        case refreshAfterSeconds = "refresh_after_seconds"
    }
}
