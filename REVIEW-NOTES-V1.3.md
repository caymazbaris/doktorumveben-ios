# App Review Notes — sürüm 1.3

> Bu dosya **App Store Connect → App Review Information → Notes** alanına girilen metnin
> birebir kopyasıdır. Alan sınırı 4.000 karakter.
>
> ⚠ `REVIEW-NOTES-V1.2.md`, `REVIEW-NOTES-BUILD13.md` ve `REVIEW-NOTES.md` ARTIK GEÇERSİZ.
> Alanı değiştirirsen burayı da değiştir; ikisi ayrışırsa hangisinin doğru olduğu bilinemez.

## Bu sürümde değişen hazırlık (2 Ekim 2026)

- **İnceleme hesabı değişti.** 1.0'dan beri ASC'de yazılı olan `appstore.review@doktorumveben.com`
  (users #298) **30 Temmuz 2026'da silinmişti** (muhtemelen inceleyici hesap silmeyi denedi);
  1.1 ve 1.2 çalışmayan bir hesapla gönderilmiş. Artık `apple.review@doktorumveben.com`
  (users #321): rol `patient`, iki adımlı doğrulama KAPALI, telefonu sahte (905550000000),
  randevu/talep/sohbet/ödeme 0. Şifre bu depoda TUTULMAZ; yalnız ASC'deki alanda.
- ⛔ Bu hesapta 2FA'yı açma, gerçek telefon numarası yazma (misafir hasta kaydı telefonla
  hesaba bağlanır), randevu bırakma. Notta inceleyiciden hesap silmeyi YENİ hesapla denemesi
  isteniyor; yine de silinirse sonraki gönderimden önce hesabı yeniden aç.
- Hekim modu için inceleyiciye hekim hesabı VERİLMEDİ (kullanıcı kararı, 2 Eki). Apple isterse
  yalnız örnek veri içeren temiz bir demo hekim hazırlanacak — test hekim #20861'de Temmuz'dan
  doğrulanamayan hasta kayıtları var, o hesap verilmez.

## ASC'ye girilen metin (İngilizce, birebir)

```
VERSION 1.3 — update to the approved 1.2. The core flow you reviewed in build 13 (search → practitioner → native request/booking → confirmation) is unchanged and native. Signing in is still optional for that flow.

REVIEW ACCOUNT
Please use the account in the Sign-In Information fields (apple.review@doktorumveben.com, a patient account). No SMS or one-time code is needed: two-step verification is off on this account. Please do not turn it on — the code would go to our team, not to you.
Account deletion is in Hesabım → Hesap → "Hesabımı sil". If you test it, please first create a new account (Hesabım → "Üye ol", or Sign in with Apple) and delete that one: deleting the review account would lock out the next review.

WHAT'S NEW IN 1.3
1) Push notifications (new permission). After sign-in the app asks for notification permission. Pushes are the same account notifications the user already sees in the app (appointment updates, replies, reminders); tapping one opens the related screen. No marketing. The list is behind the bell icon on the search screen.
2) Location (new permission, optional). Used only to pre-select the user's province and district in doctor search. Coordinates are never sent to our servers: iOS (Apple's geocoder) turns them into a province/district name and only that filter is sent with the search request. If declined, the user picks a city manually.
3) Search. All website filters are now in the app (gender, visit type, verified only, area of interest, insurance, spoken language, sort). Long lists open as searchable lists, popular items first. New card "Hekim seçmeden talep bırakın": choose a speciality and city, our team finds a suitable doctor. A doctor's page also offers "Fiyat Talep Et" (ask for the fee).
4) Native account screens in Hesabım: profile, password, family members, favourite doctors, reviews, payment history.
5) Optional two-step verification: Hesabım → Güvenlik → "İki adımlı doğrulama". Codes are sent by WhatsApp or e-mail.
6) Doctor mode. When the signed-in account belongs to a verified practitioner, the server enables practitioner tabs: Ajanda (agenda), Hastalar (patients), Gelen Kutusu (messages, cancellation requests, questions) and Tahsilat (payment links for the practitioner's own medical services). Practitioner accounts are issued only to verified doctors, so the review account (a patient) does not show these tabs and the patient experience is unchanged. If you need to see doctor mode, please reply in Resolution Center and we will provide a practitioner demo account that contains sample data only.

PAYMENTS
Unchanged: payments are for real-world medical services delivered by doctors (Guidelines 3.1.3(d) and 3.1.3(e)). Patients do not buy digital goods or subscriptions in the app. Payment pages always open in Safari, never inside the app.

PRIVACY
No third-party advertising or analytics SDKs in the native app, so no tracking and no ATT prompt. Health-related data is never shared with third parties. Region: Turkey. Content is in Turkish. Support: destek@doktorumveben.com
```

## "Bu sürümdeki yenilikler" (tr, ASC'ye girilen, kullanıcı onaylı)

```
• Bildirimleriniz artık telefonunuza anlık bildirim olarak da gelir; bildirimler arama ekranındaki zil simgesinde.
• Uygulama konumunuzdan il ve ilçeyi kendisi seçer; sitedeki tüm filtreler (cinsiyet, görüşme türü, sigorta, dil, sıralama) uygulamada.
• Branş, il, ilçe, ilgi alanı, sigorta ve dil listelerinde yazarak arayın; popüler branşlar ve büyük şehirler üstte.
• Hekim seçmeden talep: branş ve şehir seçin, ekibimiz size uygun hekimi bulsun.
• Hekim sayfasından fiyat bilgisi isteyin.
• Hesabım: profil, şifre, yakınlarım, favori hekimler, değerlendirmeler ve ödeme geçmişi uygulamada.
• İki adımlı doğrulama: Hesabım > Güvenlik'ten açın; Apple ile girişte de çalışır.
• Hekimler için Ajanda, Hastalar, Gelen Kutusu ve Tahsilat sekmeleri; randevu detayında hasta adı.
• Hata düzeltmeleri ve iyileştirmeler.
```

"yaklaşık konumunuzdan" → "konumunuzdan": DVB-000264 doğrulamasında tam konuma geçildi (commit f1caf9c).
