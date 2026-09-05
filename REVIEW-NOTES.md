# App Review Notes — Doktorumveben (com.doktorumveben.app)

> Bu dosya, **App Store Connect → App Review Information → Notes** alanına GİRİLMİŞ metnin
> birebir kopyasıdır. Alanın sınırı **4.000 karakter**. Alanı değiştirirsen burayı da güncelle —
> ikisi ayrışırsa hangisinin doğru olduğu bilinemez.
>
> Gönderim: **Tur 241, 30 Tem 2026 — BUILD 11 / sürüm 1.0** (önce reddedilen build 8'di).
> Red gerekçeleri: 2.3.8, 4.2.0, 4.2.2, 4.8.0.

---

## Gönderilen metin (birebir — EN)

```text
RESUBMISSION — this is BUILD 11. The previously reviewed build was 8. Every rejection point below was addressed in this build.

4.8 LOGIN SERVICES — Sign in with Apple is now NATIVE and IN-APP.
Open the app and tap the "Hesabım" (Account) tab in the bottom bar. Directly under the e-mail/password form is Apple's own Sign in with Apple button (SwiftUI SignInWithAppleButton) — no web view, no redirect, equivalent placement and prominence. We request name and e-mail only, Apple's private e-mail relay is fully supported, and the identity token is verified server-side against Apple's JWKS. Signing in is optional: browsing AND booking work with no account at all.

4.2 / 4.2.2 MINIMUM FUNCTIONALITY — the app is now a native client with real, bookable doctors.
1) Native, not a web view. Doctor search, the doctor profile, the appointment calendar, the booking form and the confirmation screen are implemented in SwiftUI. The app also uses device capabilities a website cannot: it writes the confirmed appointment into the iPhone's own Calendar (EventKit, write-only access) and sets a local reminder for the day before.
2) Real inventory. Practitioners who have signed a consent now have live calendars with selectable times, and you can complete a real booking WITHOUT creating an account. Verified examples — tap "Doktor Bul" (Find a Doctor) and search the name:
- Op. Dr. Erkan Kulduk — ENT, İzmir — 20-minute slots, Tue-Sat 11:00-19:00
- Uzm. Dr. Erhan Ergin — Manisa — 20-minute slots, Mon-Sat 08:30-18:30
- Kl. Psk. Ekin Sökmen — Psychologist, İzmir — 60-minute sessions, Mon-Sat 09:00-17:00
Doctor -> "Randevu al" (Book) -> pick a day -> pick a time -> enter a name and a Turkish mobile number -> submit. The appointment is created immediately and shown with its appointment number.
Why a new booking reads "awaiting approval": in Turkey the practitioner must confirm a medical appointment before it is final. The patient is notified by WhatsApp and e-mail the moment it is approved, and doctors who prefer instant confirmation switch on auto-approval in their own panel. This is the production behaviour of the live service at doktorumveben.com, not a placeholder.
No dead ends: a practitioner with no online calendar shows "Randevu Talep Et" (request an appointment) plus a WhatsApp option instead of an empty calendar, so every doctor leads to a working way to get an appointment.

2.3.8 ACCURATE METADATA — every screenshot was recaptured from THIS build and shows the actual native screens: doctor search, doctor profile, the appointment calendar, and the account screen with the Sign in with Apple button.

5.1.1(v) ACCOUNT DELETION — a signed-in patient deletes their account and data from inside the app: "Hesabım" -> account/data deletion. No support contact required.

DEMO ACCOUNT — in the Sign-In fields above. No SMS and no one-time code is required for it; the password alone signs you in.

DEVICE FEATURES USED — camera and microphone (in-app video consultation over WebRTC), photo library / document upload, on-screen signature for informed-consent forms, iPhone Calendar write + local reminders, native splash screen and status bar, native error/retry state. Push notifications are NOT in this build; they are planned for a later update.

PAYMENTS — appointment fees are payments for real-world medical services (Guideline 3.1.3(e)), taken by our licensed Turkish payment provider PayTR. No digital goods or subscriptions are sold to patients, so In-App Purchase does not apply. The doctor-side paid subscription is not offered inside the iOS app.

PRIVACY — the app does not track users across other companies' apps or websites; third-party advertising SDKs are disabled in the native app context, so no ATT prompt is shown and no "Data used to track you" is declared. Region: Turkey. Content is in Turkish. Support: destek@doktorumveben.com
```

---

## Gerçeklik denetimi (bu turda tek tek doğrulandı — iddia ≠ kod olmasın)

| Nottaki iddia | Kanıt |
| --- | --- |
| Apple ile giriş uygulama içinde, native | `native/DVBAppleSignIn.swift` + `DVBAccountView` + 06 numaralı ekran görüntüsünde OCR ile "Sign in with Apple" görüldü (CI kalite kapısı bunu zorunlu tutuyor) |
| Jeton sunucuda JWKS'e karşı doğrulanıyor | `app/Services/Auth/AppleIdTokenVerifier.php` (prod) |
| Arama/profil/takvim/randevu SwiftUI | `DVBSearchView` / `DVBDoctorDetailView` / `DVBBookingView` |
| iPhone Takvimi + yerel hatırlatma | `native/DVBCalendarKit.swift` (`EKEventStore`, `requestWriteOnlyAccessToEvents`) |
| Kamera/mikrofon/foto/takvim izin metinleri | `scripts/prepare-native-ios.mjs` içinde `NS*UsageDescription` (satır ~152-169) |
| Girişsiz randevu | canlıda uçtan uca denendi (randevu oluşturuldu, sonra temizlendi) |
| **Push YOK** | `firebase/GoogleService-Info.plist` mevcut DEĞİL → `pushReady=false` → `aps-environment` entitlement'ı basılmıyor. Bu yüzden not "planned for a later update" diyor. |
| Export Compliance | `ITSAppUsesNonExemptEncryption=false` Info.plist'e otomatik basılıyor → şifreleme sorusu kendiliğinden geçiyor |

<!--
İç not (Apple'a GİTMİYOR):
- Demo hesap: appstore.review@doktorumveben.com — **CANLIDA DOĞRULANDI 30 Tem 2026:**
  `users.id = 298`, `is_active = 1`, `two_factor_enabled = 0`, `phone = NULL`,
  `email_verified_at = 2026-07-25 19:53:40`. Şifre kasten bu depoda TUTULMUYOR;
  yalnız App Store Connect'in Sign-In alanında saklı.
  (Bu dosyanın eski sürümlerinde iki HATA vardı: e-posta "apple.review@..." yazıyordu —
  öyle bir adres YOK; ve "user #321 + telefon 905550000000" yazıyordu — ikisi de yanlış,
  hesabın telefonu hiç yok. Sorguyla düzeltildi.)
- 2FA'yı bu hesapta ASLA açmayın. Açılırsa /api/v1/auth/login jeton yerine `requires_otp`
  döner ve SMS bekler; prod'da tanımlı SMS sağlayıcısı YOK (Netgsm boş) → incelemeci
  kalıcı olarak giriş yapamaz ve uygulama tekrar reddedilir.
- Telefonun NULL olması iyi: kayıt akışı, telefonu eşleşen misafir hasta kaydını mevcut
  hesaba BAĞLAR. Bu hesaba gerçek bir numara yazılırsa incelemeci başka birinin
  randevularını görebilir. Numara EKLEMEYİN.
- Sürüm yayımı "Manually release this version" seçili: onaydan sonra
  "Pending Developer Release"de bekler, yayına almak için elle basmak gerekir.
-->

## Yaş sınırı (Age Rating)
Kategori **Medical**. Anketde "Medical/Treatment-Focused Content" → **Infrequent/Mild**
(uygulama randevu dizini, tıbbi teşhis/tedavi tavsiyesi değil). Beklenen sonuç 12+/13+.
Fazla beyan etme — açık tedavi talimatı verilmiyor.
