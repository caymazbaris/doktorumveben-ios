# Doktorumveben iOS — App Store Yol Haritası (Tur 200)

> Sentez: 2026-07-25 · `com.doktorumveben.app` (Capacitor "hosted" WKWebView → https://doktorumveben.com) · Hesap: KURULUŞ, Enrollment `69KLRXJ34T` (Barış Caymaz / IKSERO BILISIM). $99 ÖDENDİ (sipariş W1455065635, 2026-07-25). Kaynak: 10-ajanlı doğrulamalı araştırma workflow'u; tüm doğrulama iddiaları CONFIRMED (yüksek güven).

## 1) 4.2 RED RİSKİ — KOŞULLU GO
Çıplak hosted WKWebView'i (native katman yok, offline'da beyaz ekran, ATT kararsız) **olduğu gibi göndermek → neredeyse kesin ilk-tur reddi** (Guideline 4.2 "repackaged website" / pratikte 4.2.2). Aşağıdaki azaltıcıların çoğu uygulanırsa onay gerçekçi (Practo/Zocdoc tarzı randevu-pazaryerleri kabul ediliyor; kapı "app-like mı", tıbbi içerik değil).

**Azaltıcılar (öncelik sırası):**
1. **iOS'ta gerçek APNs push** — 4.2 için en güçlü tek sinyal. FCM'i iOS'ta APNs'e köprüle.
2. **Kamera/mikrofon/foto native izinleri** (Info.plist) + görüntülü muayene çalışsın (yoksa getUserMedia çöker + red).
3. **Native "İnternet yok / Tekrar dene" ekranı** — beyaz/WKWebView hata sayfası ASLA görünmesin.
4. **Native entegrasyonları App Review Notes'ta say:** push, belge yükleme (native dosya/kamera seçici), canvas imza (onam), splash/status bar, offline ekranı. En az bir tam-native ekran güçlendirici.
5. **Tarayıcı-chrome'u gizle:** URL çubuğu yok, dış linkler in-app SafariViewController'da, uzun-basma menü/loupe bastırılsın.
6. **ATT'yi çöz** (paralel red kapısı 5.1.2 — §4).
7. **iPhone-only** (`TARGETED_DEVICE_FAMILY=1`) → iPad görseli zorunlu olmasın + bozuk görünüm reddi olmasın.
8. **Demo hasta + doktor hesabı + OTP bypass** (reviewer içeri giremezse 2.1/5.1.1 reddi).
9. **Uygulama içinden "Hesabımı sil" girişi** (5.1.1v).
10. **iOS'ta doktor üyelik "satın al" akışını GÖSTERME** (3.1.1 IAP riski; randevu ödemesi gerçek-dünya hizmeti = 3.1.3 muaf).

Beklenti: azaltıcılarla 1-2 inceleme turunda onay; takvime 1-2 hafta tampon. Yeni KURULUŞ hesabı ilk gönderimde sıkı denetlenir → net Review Notes + çalışan demo şart.

## 2) Görev Listesi ([KULLANICI]/[CLAUDE])
**A. Hesap:** [KULLANICI] sözleşme + $99 ✅DONE. ASC ▸ Business sözleşme (ücretsiz app otomatik).
**B. Kimlik/anahtar (KULLANICI):** App ID `com.doktorumveben.app` + **Push capability AÇ**; ASC API key (.p8 + Issuer ID + Key ID); **APNs Auth Key ayrı .p8** + Key ID + Team ID → Firebase'e yükle.
**C. Codemagic (KULLANICI):** kişisel hesap (500 dk/ay ücretsiz); Integrations ▸ Developer Portal ▸ ASC API 3 değeri, ad **`DoktorumvebenASC`**; GoogleService-Info.plist secure file (base64).
**D. Kod düzeltmeleri (CLAUDE):** §3.
**E. ASC kayıt+meta (KULLANICI + CLAUDE taslak):** New App (iOS, "Doktorumveben", TR, com.doktorumveben.app, SKU DOKTORUMVEBEN-IOS-001); Age Rating (Medical/Treatment → muhtemel 13+); App Privacy (§4); Review Notes + demo hesap; ekran görüntüsü.
**F. Derleme+gönderim (KULLANICI):** Codemagic build → TestFlight cihaz testi (push/kamera/offline/ATT) → Export Compliance → App Review.

## 3) Dosya Düzeltmeleri (CLAUDE) — `C:\ClaudeCrm\doktorumveben-ios\`
Referans: kardeş uygulama `C:\ClaudeCrm\doktorumveben-ekip\scripts\prepare-native.mjs` (Cap 8.4.2, entitlement otomasyonu var).

**BLOCKER:**
1. YENİ `scripts/prepare-native-ios.mjs` (+ codemagic'te `cap add ios` sonrası çağrı): Info.plist'e `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`. (ios/ her CI'da sıfırdan üretiliyor.)
2. Aynı betik → `App.entitlements` (`aps-environment`=production) + pbxproj'a Push + Background Modes(remote-notification).
3. `codemagic.yaml`: `auth: integrations` → **`auth: integration`** (tekil). İlk build'den önce.

**YÜKSEK:**
4. `package.json`: Capacitor 6 → **8** (ekip hizası: core/ios/android 8.4.2, app 8.1.1, push 8.1.2, splash 8.0.2, status-bar 8.0.3, cli 8.4.2) + `@capacitor/assets` + typescript.
5. `codemagic.yaml`: `node:20`→**22**, `xcode:latest`→**26.0** pin.
6. YENİ `.gitignore` (node_modules, ios/, android/, *.p8, *.p12, *.mobileprovision, *.keystore).
7. `@capacitor/assets` ile ikon/splash göm (icon-only.png 1024 opak, splash.png 2732², splash-dark.png); `capacitor-assets generate --ios`.
8. `TARGETED_DEVICE_FAMILY=1` (iPhone-only).
9. `PrivacyInfo.xcprivacy` üretimi (§4).

**ORTA:**
10. `capacitor.config.ts`: `appendUserAgent:'DoktorumvebenApp/1.0 (ios)'` + `server.errorPath:'error.html'`; YENİ `www/error.html` (markalı "İnternet yok").
11. `APPLE-STORE-KILAVUZ.md` push zorunlu (4.2) olarak güncelle + ATT/Privacy kararı.

## 4) App Privacy + ATT + Privacy Manifest
- **PrivacyInfo.xcprivacy ZORUNLU** (CONFIRMED, 1 May 2024'ten beri): Capacitor eklentileri required-reason API'ye dokunur (Preferences→UserDefaults CA92.1; Filesystem→C617.1/DDA9.1). Yoksa ITMS-91053 otomatik ret. Web'deki GA4/Meta pikseli manifest'i tetiklemez (JS, native SDK değil) ama App Privacy + ATT'yi etkiler.
- **ATT kararı — YOL B önerilir:** iOS native bağlamda (`Capacitor.isNativePlatform`) Meta pikseli + GA reklam/Signals'ı KAPAT → "tracking" yok → **ATT gerekmez**, "Data Used to Track You" beyan etmezsin. (YOL A: ATT plugin + NSUserTrackingUsageDescription + pikselleri onaya kapıla; daha çok bakım.)
- **App Privacy etiketi (Play Veri Güvenliği ile birebir):** Name/Email/Phone (App Functionality) · Health=randevu/şikayet (App Functionality, **paylaşılmaz/tracking yok**) · Payment Info (kart PayTR'de işlenir/saklanmaz) · Coarse Location (il/ilçe filtresi) · User ID + Device ID (push token) · Product Interaction/GA4 (Analytics; YOL B'de tracking yok). Privacy Policy URL zorunlu.

## 5) Ekran Görüntüleri — MEVCUT YETERLİ (CONFIRMED)
Zorunlu tek slot **6.9" iPhone** sınıfı; bu sınıf **1290x2796**'yı kabul eder → elimizdeki `assets/screenshots/6.7-inch-1290x2796/` (4 kare) **karşılar**, yeniden üretme YOK. 6.5"(1242x2688) opsiyonel yedek. iPad görseli GEREKMEZ (iPhone-only). PNG/JPG, sRGB, alfa YOK.

## 6) Codemagic Mac'siz — CONFIRMED
Bulut Mac mini'de derler+imzalar+TestFlight'a yükler; fiziksel Mac yok. `ios_signing{distribution_type:app_store, bundle_identifier:com.doktorumveben.app}` + `integrations: app_store_connect: DoktorumvebenASC` (Codemagic sertifika+profili Apple'dan çeker). Tek düzeltme: `auth: integration` tekil (§3-3). Öneri: `cap sync ios` sonrası açık `cd ios/App && pod install`. Tuzak: bundle_id her yerde aynı; com.doktorumveben.app (bu) ≠ com.doktorumveben.ekip (kardeş).

## 7) En Yakın 3 Aksiyon
1. **[KULLANICI]** ASC girişi (caymazbaris@gmail.com + şifre + 2FA); üyelik aktifleşince App ID + Push capability + ASC API .p8.
2. **[CLAUDE]** §3 BLOCKER'ları uygula (prepare-native-ios.mjs + codemagic auth:integration + node22/xcode pin + package Cap8 + .gitignore + error.html + PrivacyInfo).
3. **[KULLANICI kararı]** ATT için YOL B onayı → [CLAUDE] web/native piksel-kapama uygular.
