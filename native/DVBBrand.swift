import SwiftUI

/// DVB-000264 — MARKA BAŞLIĞI.
///
/// Kullanıcı (30 Eyl 2026, ilk gerçek iPhone denemesi): "Logomuz yok hiç". Yerel ekranların hiçbirinde marka
/// öğesi yoktu; varlık kataloğunda yalnız uygulama simgesi ve açılış ekranı vardı.
///
/// Sitedeki başlıkla aynı dil: simge + "Doktorum**ve**ben", "ve" yeşil. Yazı `Text` olarak çizilir (resim değil):
/// koyu/açık görünümde ve Dinamik Yazı boyutunda kendiliğinden doğru kalır.
///
/// ⚠ "BrandMark" varlığı derleme betiğinde üretilir (scripts/prepare-native-ios.mjs) — `ios/` her derlemede
/// şablondan yeniden üretildiği için elle eklenen varlık kaybolur. Varlık üretilemezse `Image` boş kalır, ÇÖKMEZ.
struct DVBBrandLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            (Text("Doktorum").foregroundColor(.primary)
                + Text("ve").foregroundColor(DVBTheme.accent)
                + Text("ben").foregroundColor(.primary))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doktorum Ve Ben")
        .accessibilityAddTraits(.isHeader)
    }
}

extension DVBTheme {
    /// Logodaki "ve" yeşili. Logonun açık yeşili (#7BE3B8) açık zeminde okunmuyor; aynı tonun koyusu.
    static let accent = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)

    /// Fiyat talebi rengi — sitedeki mor düğmeyle aynı aile (violet-700).
    static let fiyat = Color(red: 0x6D / 255, green: 0x28 / 255, blue: 0xD9 / 255)

    /// WhatsApp yeşili (#25D366).
    static let whatsapp = Color(red: 0x25 / 255, green: 0xD3 / 255, blue: 0x66 / 255)
}
