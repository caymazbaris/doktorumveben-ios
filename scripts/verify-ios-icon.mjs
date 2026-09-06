#!/usr/bin/env node
/**
 * DVB-000122 — App Store ikon zinciri doğrulaması.
 *
 * NEDEN VAR: 1.0 (13) mağazaya ikonsuz gitti. App Store Connect'te hem uygulama
 * kartı hem de "Included Assets → App Icon" alanı Apple'ın kendi yer tutucusunu
 * (Placeholder.mill) gösteriyordu — yani Apple derlemeden ikon ÇIKARAMADI.
 *
 * Bu sessiz kalabiliyordu, çünkü:
 *   · prepare-native-ios.mjs yalnız PNG DOSYASINI doğruluyordu; dosya doğruydu.
 *   · Contents.json ve pbxproj bağlantısı hiç kontrol edilmiyordu.
 *   · `ios/` sürüm kontrolünde değil; her derlemede sıfırdan üretilip ARDINDAN
 *     üç ayrı adım tarafından değiştiriliyor (SwiftUI enjeksiyonu, widget hedefi).
 *     Widget adımı pbxproj'u xcodeproj gem'iyle BAŞTAN YAZIYOR.
 *   · Derleme günlüğü de kanıt vermiyor: xcpretty varlık kataloğu satırını hiç
 *     basmıyor — ikonu düzgün çıkan ikshesap derlemesinde de o satır yok. Yani
 *     "log'da görünmüyor" burada hiçbir şeyin kanıtı DEĞİL.
 *
 * Bu betik zincirin BEŞ halkasını da tek tek ölçer ve biri kopuksa derlemeyi
 * DURDURUR. Yeri önemlidir: pbxproj'a dokunan SON adımdan sonra koşmalı.
 *
 * Kullanım: node scripts/verify-ios-icon.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const iconSrc = path.join(root, 'assets/app-icon-1024.png');
const iconSetDir = path.join(root, 'ios/App/App/Assets.xcassets/AppIcon.appiconset');
const pbxPath = path.join(root, 'ios/App/App.xcodeproj/project.pbxproj');

const hatalar = [];
const kanit = [];
const not = (s) => kanit.push(`  ✓ ${s}`);
const hata = (s) => hatalar.push(`  ✗ ${s}`);

/** PNG başlığı (IHDR) — bağımlılıksız. Geçersizse null. */
export function pngInfo(buf) {
  if (!buf || buf.length < 33) return null;
  if (buf.toString('latin1', 1, 4) !== 'PNG') return null;
  if (buf.toString('latin1', 12, 16) !== 'IHDR') return null;
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
    bitDepth: buf[24],
    colorType: buf[25],
    interlace: buf[28],
    hasTrns: buf.toString('latin1').includes('tRNS'),
  };
}

/**
 * Apple'ın App Store ikonundan beklediği koşullar. SAF FONKSİYON — sınanabilsin
 * diye ayrıldı (Exception::getFile() dersinin aynısı: karar mantığı G/Ç'den ayrı).
 * @returns {string[]} boş dizi = uygun
 */
export function ikonKusurlari(meta) {
  if (!meta) return ['PNG olarak okunamadı'];
  const k = [];
  if (meta.width !== 1024 || meta.height !== 1024) k.push(`1024x1024 değil (${meta.width}x${meta.height})`);
  if (meta.bitDepth !== 8) k.push(`8-bit değil (bit=${meta.bitDepth})`);
  if (meta.colorType === 4 || meta.colorType === 6 || meta.hasTrns) k.push('alfa/şeffaflık var — Apple reddeder');
  if (meta.interlace !== 0) k.push('interlaced PNG — Apple çıkaramayabilir');
  return k;
}

/**
 * Contents.json içinde 1024'lük App Store yuvası doğru tanımlanmış mı?
 * SAF FONKSİYON.
 * @returns {{girdi:object|null, kusurlar:string[]}}
 */
export function marketingYuvasi(contents) {
  const imgs = Array.isArray(contents?.images) ? contents.images : [];
  const g = imgs.find((i) => i && i.size === '1024x1024');
  if (!g) return { girdi: null, kusurlar: ['1024x1024 yuvası YOK'] };
  const k = [];
  if (!g.filename) k.push('yuvada filename yok (boş yuva — actool ikon üretmez)');
  // Xcode 14+ tek boyutlu ikon: idiom "universal" + platform "ios".
  // Eski biçim: idiom "ios-marketing". İkisi de kabul; başkası DEĞİL.
  const universal = g.idiom === 'universal' && g.platform === 'ios';
  const eski = g.idiom === 'ios-marketing';
  if (!universal && !eski) {
    k.push(`idiom/platform hatalı (idiom=${g.idiom ?? 'yok'}, platform=${g.platform ?? 'yok'}) — `
      + 'iOS App Store yuvası olarak tanınmaz');
  }
  return { girdi: g, kusurlar: k };
}

/**
 * pbxproj'da "App" hedefinin Resources fazı varlık kataloğunu taşıyor mu?
 * SAF FONKSİYON — pbxproj metnini alır, karar döner.
 *
 * Yalnız "dosyada Assets.xcassets geçiyor mu" diye bakmak YETMEZ: dosya
 * referansı dururken build fazından düşmüş olabilir; o hâlde katalog derlenmez
 * ve uygulama ikonsuz çıkar. Bu yüzden hedeften faza inilir.
 */
export function katalogHedefeBagliMi(pbx) {
  const hedef = pbx.match(/\/\* App \*\/ = \{\s*isa = PBXNativeTarget;[\s\S]*?buildPhases = \(([\s\S]*?)\);/);
  if (!hedef) return { ok: false, sebep: 'pbxproj içinde "App" adlı PBXNativeTarget bulunamadı' };

  const fazIdleri = [...hedef[1].matchAll(/([0-9A-F]{24})/g)].map((m) => m[1]);
  if (fazIdleri.length === 0) return { ok: false, sebep: 'App hedefinin buildPhases listesi boş' };

  for (const id of fazIdleri) {
    const faz = pbx.match(new RegExp(`${id} \\/\\* [^*]*\\*\\/ = \\{[\\s\\S]*?isa = PBXResourcesBuildPhase;[\\s\\S]*?\\n\\t\\t\\};`));
    if (!faz) continue;
    if (faz[0].includes('Assets.xcassets in Resources')) {
      return { ok: true, sebep: `App hedefinin Resources fazında (${id})` };
    }
  }
  return {
    ok: false,
    sebep: 'Assets.xcassets App hedefinin Resources fazında DEĞİL — katalog derlenmez, uygulama ikonsuz çıkar',
  };
}

// ── 1) Kaynak ikon ───────────────────────────────────────────────────────────
if (!fs.existsSync(iconSrc)) {
  hata(`Kaynak ikon yok: ${path.relative(root, iconSrc)}`);
} else {
  const buf = fs.readFileSync(iconSrc);
  const k = ikonKusurlari(pngInfo(buf));
  if (k.length) hata(`Kaynak ikon uygun değil: ${k.join('; ')}`);
  else not(`Kaynak ikon uygun (1024x1024, 8-bit, alfa yok, interlace yok)`);
}

// ── 2) Katalogdaki PNG kaynakla AYNI mı ──────────────────────────────────────
let contents = null;
if (!fs.existsSync(iconSetDir)) {
  hata(`AppIcon.appiconset yok: ${path.relative(root, iconSetDir)}`);
} else {
  const cPath = path.join(iconSetDir, 'Contents.json');
  try {
    contents = JSON.parse(fs.readFileSync(cPath, 'utf8'));
  } catch (e) {
    hata(`Contents.json okunamadı/bozuk: ${e.message}`);
  }

  const { girdi, kusurlar } = marketingYuvasi(contents ?? {});
  if (kusurlar.length) hata(`Contents.json: ${kusurlar.join('; ')}`);
  else not(`Contents.json 1024'lük yuvayı doğru tanımlıyor (idiom=${girdi.idiom}, platform=${girdi.platform ?? '—'})`);

  if (girdi?.filename) {
    const p = path.join(iconSetDir, girdi.filename);
    if (!fs.existsSync(p)) {
      hata(`Contents.json "${girdi.filename}" diyor ama dosya YOK — actool boş yuva görür, ikon üretmez`);
    } else {
      const buf = fs.readFileSync(p);
      const k = ikonKusurlari(pngInfo(buf));
      if (k.length) hata(`Katalogdaki ikon uygun değil: ${k.join('; ')}`);

      if (fs.existsSync(iconSrc)) {
        const a = crypto.createHash('sha256').update(fs.readFileSync(iconSrc)).digest('hex');
        const b = crypto.createHash('sha256').update(buf).digest('hex');
        if (a !== b) {
          hata(`Katalogdaki ikon MARKA İKONU DEĞİL (sha ${b.slice(0, 12)}… ≠ ${a.slice(0, 12)}…) — `
            + 'muhtemelen Capacitor yer tutucusu kaldı');
        } else {
          not(`Katalogdaki ikon marka ikonuyla birebir aynı (sha ${a.slice(0, 12)}…)`);
        }
      }
    }
  }
}

// ── 3) pbxproj: katalog App hedefine bağlı mı ────────────────────────────────
if (!fs.existsSync(pbxPath)) {
  hata(`project.pbxproj yok: ${path.relative(root, pbxPath)}`);
} else {
  const pbx = fs.readFileSync(pbxPath, 'utf8');

  const bag = katalogHedefeBagliMi(pbx);
  if (bag.ok) not(`Assets.xcassets ${bag.sebep}`);
  else hata(bag.sebep);

  // ── 4) ASSETCATALOG_COMPILER_APPICON_NAME her yapılandırmada AppIcon mı ────
  const adlar = [...pbx.matchAll(/ASSETCATALOG_COMPILER_APPICON_NAME = ([^;]+);/g)].map((m) => m[1].trim());
  const appHedefiSayisi = adlar.filter((a) => a === 'AppIcon').length;
  if (appHedefiSayisi < 2) {
    hata(`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon yalnız ${appHedefiSayisi} yapılandırmada `
      + '(Debug + Release beklenir) — eksik olan yapılandırma ikonsuz derlenir');
  } else {
    not(`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon (${appHedefiSayisi} yapılandırma)`);
  }
}

// ── Rapor ────────────────────────────────────────────────────────────────────
console.log('\n[ikon-doğrulama] App Store ikon zinciri:');
for (const s of kanit) console.log(s);
if (hatalar.length === 0) {
  console.log('[ikon-doğrulama] TAMAM — bu derleme App Store Connect\'e ikonla gider.\n');
  process.exit(0);
}
console.error('\n[ikon-doğrulama] KOPUK HALKA:');
for (const s of hatalar) console.error(s);
console.error(
  '\nDerleme DURDURULDU. İkonsuz bir derleme yüklemek işe yaramaz: App Store Connect\n'
  + '"Included Assets → App Icon" alanında Apple\'ın yer tutucusunu gösterir ve inceleme\n'
  + 'bunu yer tutucu ikon (Guideline 2.3.8) sayabilir — 1.0 (8) tam bu yüzden reddedilmişti.\n'
);
process.exit(1);
