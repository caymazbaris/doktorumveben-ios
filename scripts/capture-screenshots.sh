#!/usr/bin/env bash
# DVB-000121 — App Store ekran gorutusu yakalama (Simulator).
#
# NEDEN DOSYAYA CIKTI: uygulama 06.09.2026'dan beri iPhone + iPad. App Store
# Connect iPad destekleyen uygulamadan 13" iPad ekran goruntusu de ISTER;
# yuklenmeden gonderim dugmesi acilmaz. Ayni betigi iki cihaz sinifi icin
# kosturmak gerekiyordu.
#
# Codemagic'in "Start new build" diyaloginda ortam degiskeni verilecek alan YOK
# (olculdu) — yani "gerektiginde elle ipad diye kostururuz" yolu kapali. Bu
# yuzden calisan iPhone hatti YENIDEN YAZILMADI, oldugu gibi buraya tasindi ve
# is akisi ayni betigi iki kez cagiriyor. Tek kosuda iki takim da uretilir ve
# ikisi her zaman ayni derlemeden gelir.
#
# DVB_SHOT_DEVICE = iphone (varsayilan) | ipad
# Cagiran adim APP degiskenini beklemez; .app'i kendisi bulur.
set -e
set -e
BUNDLE=com.doktorumveben.app
APP=$(find /tmp/dd/Build/Products -maxdepth 2 -name "App.app" -type d | head -1)
if [ -z "$APP" ]; then echo "HATA: App.app bulunamadi"; exit 1; fi
echo "App: $APP"

echo "=== Mevcut cihaz tipleri (iPhone) ==="
xcrun simctl list devicetypes | grep -i iphone || true
echo "=== Mevcut runtime'lar ==="
xcrun simctl list runtimes | grep -i ios || true

# En yeni iOS runtime
RT=$(xcrun simctl list runtimes | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | tail -1)
if [ -z "$RT" ]; then echo "HATA: iOS runtime yok"; exit 1; fi
echo "Runtime: $RT"

# Verilen adaylardan var olan İLK cihaz tipini seç
sec_tip() {
  for id in "$@"; do
    if xcrun simctl list devicetypes | grep -q "$id"; then echo "$id"; return 0; fi
  done
  return 1
}

# DVB-000121 — yönetici kararı 06.09.2026: "tabletlerde de kullanılsın".
# Uygulama artık iPhone + iPad (TARGETED_DEVICE_FAMILY="1,2"), bu yüzden
# App Store Connect 13" iPad ekran görüntüsü de İSTER; iPad görüntüsü
# yüklenmeden gönderim düğmesi açılmaz.
#
# Çalışan iPhone hattı YENİDEN YAZILMADI: yalnız cihaz seçimi ve çıktı
# dizini değişkene bağlandı. Aynı iş akışı DVB_SHOT_DEVICE=ipad ile
# ikinci kez koşturulunca iPad takımını üretir. Varsayılan eskisi gibi
# iPhone — mevcut davranış değişmiyor.
case "${DVB_SHOT_DEVICE:-iphone}" in
  ipad)
    SET_ADI="13-inch-ipad"
    DT_BUYUK=$(sec_tip \
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB \
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4 \
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation-8GB \
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro--12-9-inch---6th-generation) \
      || { echo "HATA: 13 inc iPad cihaz tipi yok"; xcrun simctl list devicetypes | grep -i ipad; exit 1; }
    ;;
  *)
    # Apple bugün 6.9" istiyor; 6.5" ikinci set olarak kabul ediliyor.
    SET_ADI="6.9-inch"
    DT_BUYUK=$(sec_tip \
      com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
      com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max \
      com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max \
      com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max) || { echo "HATA: Pro Max cihaz tipi yok"; exit 1; }
    ;;
esac
echo "Takım: $SET_ADI · Cihaz tipi: $DT_BUYUK"

UDID=$(xcrun simctl create "DVBShot-$SET_ADI" "$DT_BUYUK" "$RT")
echo "UDID: $UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b || true
xcrun simctl ui "$UDID" appearance light || true
# Apple'ın kendi tanıtım saati 9:41 — tam dolu pil/sinyal, temiz durum çubuğu.
xcrun simctl status_bar "$UDID" override \
  --time "09:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 || true
# Tur 241 — SİSTEM BİLDİRİMİNİ BEKLE. Build #6'da 02-hekim-profili.png'nin
# tepesine iOS'un kendi "Ready for Apple Intelligence" banner'ı düştü ve
# hekimin adını kapattı. Her build sıfırdan cihaz yarattığı için bu ilk-açılış
# bildirimi HER SEFERİNDE tetikleniyor; simctl'de bildirimi kapatan bir anahtar
# yok, o yüzden penceresi geçene kadar bekliyoruz (yakala() ayrıca ikinci kez
# çekiyor ve OCR sonunda banner metnini arayıp build'i düşürüyor).
echo "İlk açılış bildirimleri için bekleniyor…"
sleep 45

xcrun simctl install "$UDID" "$APP"

# MUTLAK yol ŞART: ekran görüntüsünü CoreSimulator servisi yazıyor, bu kabuk
# değil — göreli yolu bizim çalışma dizinimize göre çözemiyor ve
# "The folder ... doesn't exist" ile düşüyor (ilk denemede tam bu oldu).
OUT="$PWD/screenshots/$SET_ADI"
mkdir -p "$OUT"
echo "Çıktı dizini: $OUT"

# Tek bir kare flaky olursa kalanları da kaybetmeyelim; sonunda toplu kontrol var.
yakala() {   # $1=dosya  $2=ekran  $3=slug  $4=bekleme
  echo "--- $1  (ekran=$2 slug=$3) ---"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -DVBScreenshot "$2" -DVBScreenshotDoctor "$3" || true
  sleep "$4"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1" || echo "UYARI: $1 alınamadı"
  # İKİNCİ kare aynı dosyanın üzerine yazar. Sebep: sistem bildirim banner'ı
  # ~5 sn ekranda kalıyor; ilk kareye düşse bile ikincisi temiz çıkar. Veri
  # zaten yüklü olduğu için ikinci karede içerik aynı, sadece banner gider.
  sleep 8
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1" || true
  ls -la "$OUT/$1" 2>/dev/null || true
}

# Canlı API'den veri çekiliyor: ilk açılış için cömert bekleme.
yakala 01-hekim-ara.png            arama   erkan-kulduk-84ix  12
yakala 02-hekim-profili.png        profil  erkan-kulduk-84ix  12
yakala 03-randevu-takvimi.png      randevu erkan-kulduk-84ix  12
yakala 04-psikolog-profili.png     profil  ekin-sokmen-ymis   12
yakala 05-seans-takvimi.png        randevu ekin-sokmen-ymis   12
# Tur 241 — 4.8 kanıtı: uygulama içi "Apple ile giriş" düğmesi.
yakala 06-giris-apple.png          hesap   erkan-kulduk-84ix  10

echo "=== Üretilen görüntüler ==="
ls -la "$OUT"
BEKLENEN=6
ADET=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "PNG adedi: $ADET / $BEKLENEN"
# Tur 241: eskiden yalnız "0 mı?" diye bakıyordu — bir kare sessizce
# düşse haberimiz olmadan eksik takım yüklerdik. Artık TAM sayı şart.
if [ "$ADET" -ne "$BEKLENEN" ]; then
  echo "HATA: $BEKLENEN kare beklenirken $ADET üretildi — eksik kareyle mağazaya çıkılmaz."
  exit 1
fi
# Çözünürlük log'a yazılsın (6.9" = 1320x2868, 6.7" = 1290x2796).
# sips macOS'ta hazır; gömülü çok satırlı betik YAML blok kapsamını kırıyor.
for f in "$OUT"/*.png; do sips -g pixelWidth -g pixelHeight "$f" | tr '\n' ' '; echo; done

# Karelerin İÇERİĞİNİ log'a yaz: artifact indirmesi oturum kimliği istediği
# için pikselleri buradan başka görebilen yok. Apple'ın Vision OCR'ı ile her
# karedeki metni basıyoruz — hekim adı/saatler görünüyorsa ekran gerçekten
# veriyle çizilmiş demektir; hata durumu çizilmişse o da metinden anlaşılır.
# ⚠ Cihaza ÖZEL dosya ve her turda sıfırlanır. Paylaşılan tek dosya olsaydı,
# iPad turunda OCR sessizce düştüğünde kapı iPhone turunun metnini okur ve
# YANLIŞ YEŞİL verirdi — kontrol ettiğini sanıp hiçbir şey kontrol etmemek.
OCR="/tmp/ocr-$SET_ADI.txt"
rm -f "$OCR"
echo "=== İçerik doğrulama (OCR: $OCR) ==="
swift "$CM_BUILD_DIR/scripts/ocr-shots.swift" "$OUT"/*.png > "$OCR" 2>&1 \
  || echo "UYARI: OCR çalışmadı (kareler yine de üretildi)"
cat "$OCR"

xcrun simctl shutdown "$UDID" || true

# Tur 241 — KARE KALİTE KAPISI. Karelerin pikselini CI dışında kimse
# göremiyor; sessiz bir kusur doğrudan App Store'a gider. İki şeyi metinden
# yakalıyoruz ve bulursak build'i DÜŞÜRÜYORUZ:
#   1) sistem bildirim banner'ı (build #6'da "Ready for Apple Intelligence"
#      hekimin adının üstüne bindi),
#   2) uygulamanın kendi hata durumları (çözümleme/ağ hatası ekranı).
if grep -Eqi "Apple Intelligence|Ready for Apple" "$OCR"; then
  echo "HATA: karelerde iOS sistem bildirim banner'ı var — mağazaya gidemez."
  exit 1
fi
if grep -Eqi "beklenmeyen bir yanıt|Profil alınamadı|Takvim açılamadı|Bilinmeyen hata" "$OCR"; then
  echo "HATA: karelerden biri uygulamanın hata ekranını gösteriyor."
  exit 1
fi

# Tur 241 — POZİTİF kapı (App Store 4.8). Yukarıdaki iki kontrol "kötü bir şey
# YOK" der; bu ise "iyi bir şey VAR" der. 1.0 tam 4.8'den reddedildi çünkü
# Apple ile giriş uygulama içinde yoktu. Entitlement + Swift doğru görünse de
# düğme çizilmezse yine reddedilirdik; tek görme yolumuz bu kare.
# Apple'ın kendi düğmesi cihaz diline göre "Apple ile ..." / "Sign in with Apple"
# yazar — ikisini de kabul ediyoruz.
if ! grep -Eqi "Apple ile|Sign in with Apple|Sign up with Apple" "$OCR"; then
  echo "HATA: 'Apple ile giriş' düğmesi hiçbir karede görünmüyor — 4.8 yine reddedilir."
  echo "Bakılacak yerler: App.entitlements (com.apple.developer.applesignin),"
  echo "DVBAccountView'daki DVBAppleSignInButton, DVBScreenshot 'hesap' ekranı."
  exit 1
fi
echo "Kare kalite kapısı: TEMİZ (4.8 düğmesi de görüldü)"
