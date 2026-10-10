# App Review Notes — sürüm 1.4

> Bu dosya **App Store Connect → App Review Information → Notes** alanına girilecek metnin birebir kopyasıdır
> (alan sınırı 4.000 karakter). ⚠ `REVIEW-NOTES-V1.3.md` ve öncekiler 1.4 için GEÇERSİZ.
> Hazırlayan: DVB-000341/343/344/345 + DVB-000351/352/353 (9 Ekim 2026). İnceleme hesabı 1.3 ile aynı (`apple.review@doktorumveben.com`,
> şifre yalnız ASC'deki alanda — bu depoda tutulmaz). Hekim demo hesabı 1.3'teki karar gereği verilmedi.

## Gönderimden önce kullanıcının yapması gerekenler

1. ASC'de **1.4** sürümünü aç (yayın: onaylanınca otomatik — 1.3 ile aynı karar).
2. Codemagic "iOS App Store (TestFlight)" derlemesi (MARKETING_VERSION 1.4) işlendikten sonra **Add Build**.
3. Aşağıdaki iki metni yapıştır → Save → **Add for Review** → **Submit for Review**.
4. ✅ **App Privacy — YAPILDI (10 Ekim 2026, kullanıcı "hepsini ekle"):** ASC'de 12 veri türü yayında; yeni eklenenler Physical Address, Other Financial Info, Emails or Text Messages, Photos or Videos, Customer Support, Other User Content (hepsi App Functionality · kimliğe bağlı · izleme yok). Sigorta poliçesi mevcut "Health" beyanında. Aşağıdaki açıklama kayıt için duruyor.
   Eski not — bu sürümde hekim hesabı uygulamadan **profil fotoğrafı yükleyebiliyor**
   ve **IBAN / fatura bilgisi (ünvan, VKN/TCKN, adres)** girebiliyor; hasta da saç ekimi merkezine **ad, telefon,
   e-posta** ile talep bırakabiliyor. ASC → App Privacy'de "Photos or Videos" ile "Financial Info → Other Financial Info"
   (ve "Contact Info") beyanlarının işaretli olduğunu kontrol et; yoksa ekle (amaç: App Functionality, kimliğe bağlı,
   izleme yok). Gizlilik etiketi gerçeği yansıtmalı — App Review yanıltılmaz.
   DVB-000351/352/353 ile eklenenler: hasta **sağlık sigortası poliçesini** (firma, poliçe no, geçerlilik) kaydedebiliyor
   → "Health & Fitness → Health" ya da "Financial Info → Other Financial Info" beyanından biri işaretli olmalı;
   hekim modunda hastanın **onam imzası** (parmakla çizilen imza görüntüsü) alınıyor → "Other Data" (ya da "Other User
   Content"); "Doktora sor"da kullanıcı **soru metni** yazabiliyor → "User Content → Other User Content".

## ASC'ye girilecek metin (İngilizce, birebir)

```
VERSION 1.4 — update to the approved 1.3. The patient flow you reviewed (search → practitioner → native request/booking → confirmation) is unchanged. Signing in is still optional for that flow.

REVIEW ACCOUNT
Please use the account in the Sign-In Information fields (apple.review@doktorumveben.com, a patient account). Two-step verification is off; please do not turn it on. Account deletion is in Hesabım → Hesap → "Hesabımı sil"; if you test it, please create a new account first and delete that one.

WHAT'S NEW IN 1.4 (patients — no sign-in needed)
1) "Hastaneler" (Hospitals) on the search screen: hospital list by city, hospital page (about, departments, contracted insurers, photos) and the doctors of each department.
2) "Saç ekimi (İzmir)" (hair transplant): an information page with FAQ and clinic profiles. A user can ask a clinic for a free consultation or for price information; the form asks for explicit consent before the name and phone are forwarded to that clinic. No prices are shown in the app.
3) Online video consultations: for an online appointment the appointment screen shows "Görüşmeye katıl". The meeting opens in Safari (WebRTC; camera/microphone permission is asked by Safari, not by the app). The patient waits in a waiting room until the doctor admits them.
4) Account (sign-in): "Puanlarım" (points and referral code), "Sigortalarım" (save your health insurance policy), "Verilerimi indir" (download a copy of your account data as a JSON file — data portability right under KVKK).
5) "Sağlık rehberi" (health guide): read-only articles, each reviewed by a doctor.
6) "Doktora sor" (ask a doctor) appears only when the section is enabled on our website (currently off). Questions are pre-moderated: nothing is published until a verified doctor answers; the asker's name is shortened and contact details are never shown.

WHAT'S NEW IN 1.4 (doctor mode only)
7) Doctor mode (enabled by the server only for verified practitioner accounts) now covers the doctor's web panel: consent forms (templates; the patient signs on the device with a finger, or receives a signing link; signed PDFs), profile editing and profile photo (system photo picker, no photo-library permission), calendar connections (iCloud, Outlook, Google, ICS), working hours and leave, services, patient requests, rescheduling, accounting, e-invoices (Turkish e-Fatura/e-Arşiv), invoice and bank (IBAN) details for receiving payouts, clinic addresses, insurers, booking-page link and QR code, reports, packages, staff, sales leads and a "report a problem" form.
The review account is a patient, so these screens are not visible to it. If you need to see doctor mode, please reply in Resolution Center and we will provide a practitioner demo account with sample data only.

PAYMENTS
Unchanged: payments are for real-world medical services delivered by doctors (3.1.3(d)/(e)). No digital goods or subscriptions are sold in the app and the app does not link to plan purchases. Payment pages always open in Safari. The IBAN screen is where a doctor enters the bank account that receives their own patients' payments; it is not a purchase.

PRIVACY
No third-party advertising or analytics SDKs, no tracking, no ATT prompt. Health-related data is never shared with third parties; a hair-transplant request is sent only to the clinic the user chose, after consent. Region: Turkey. Content is in Turkish. Support: destek@doktorumveben.com
```

## "Bu sürümdeki yenilikler" (tr)

```
• Hastaneler: hastane profilleri, bölümler, anlaşmalı sigortalar ve her bölümdeki hekimler.
• İzmir saç ekimi: bilgi sayfası, merkez profilleri, ücretsiz ön görüşme ve fiyat bilgisi talebi.
• Online görüşme: randevu ekranından "Görüşmeye katıl"; hekiminiz sizi bekleme odasından içeri alır.
• Hekimler için: profil ve fotoğraf düzenleme, takvim bağlantıları (iCloud, Outlook, Google), çalışma saatleri ve izinler, hizmetler, hasta talepleri, randevu taşıma.
• Hekimler için: muhasebe, e-Fatura, fatura ve banka bilgileri, adresler, sigortalar, randevu sayfası ve QR, raporlar, paketler, personel ve satış adayları.
• Hekimler için: onam formları — hasta ekranda parmağıyla imzalar ya da imza bağlantısı gönderilir; imzalı PDF.
• Hesabım: Puanlarım, Sigortalarım ve Verilerimi indir.
• Sağlık rehberi: hekim onaylı sağlık yazıları.
• Hata düzeltmeleri ve iyileştirmeler.
```
