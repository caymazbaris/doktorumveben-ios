# App Review Notes — sürüm 1.2 (DVB-000157 / DVB-000158)

> Bu dosya **App Store Connect → App Review Information → Notes** alanına girilen metnin
> birebir kopyasıdır. Alan sınırı 4.000 karakter.
>
> ⚠ `REVIEW-NOTES-BUILD13.md` ve `REVIEW-NOTES.md` ARTIK GEÇERSİZ — onlar 1.0/1.1 içindi.
> Alanı değiştirirsen burayı da değiştir; ikisi ayrışırsa hangisinin doğru olduğu bilinemez.

## Sürüm durumu (11 Eylül 2026)

| sürüm | durum |
|---|---|
| 1.0 (build 13) | yayındaydı |
| 1.1 (build 17) | **11 Eyl'de yayına alındı** — Apple onaylamış, "Pending Developer Release"da bekliyordu |
| 1.2 (build 20) | bu notun ait olduğu sürüm; incelemeye gönderildi |

⚠ 1.1'in "hâlâ incelemede" sanılması bir hataydı: App Store Connect'te durum
**Pending Developer Release** idi, yani onay çoktan alınmıştı ve yalnız yayına alma
tuşuna basılmayı bekliyordu. Gönderimi geri çekmek, kazanılmış bir onayı çöpe atmak
olurdu — önce 1.1 yayına alındı, sonra 1.2 açıldı.

## ASC'ye girilen metin (İngilizce, birebir)

```
VERSION 1.2 — incremental update to the approved 1.1.

WHAT CHANGED IN THIS BUILD (two items only):

1) IN-APP PROBLEM REPORTING (new)
Account tab > "Yardım" > "Sorun bildir". It opens our own support form inside the app
(web view of doktorumveben.com/hesabim/sorun-bildir). Users report a problem or send a
suggestion; each report gets a tracking code and the user can follow its status on the
same page. Sign-in is required to open it, so please use the review account below.

2) BUG FIX — "Hekim ara" (doctor search) screen
After the doctor list finished loading, the large navigation title disappeared and left
an empty area at the top. The screen's container is now a stable list, so the title no
longer disappears.

NOTHING ELSE CHANGED. The native appointment-request flow that resolved the 4.2 / 4.2.2
issue in build 13 is unchanged and still native. No new permissions, no new data
collection, no change to what the app does.

REVIEW ACCOUNT: the sign-in details in the fields above work for all screens, including
the new "Sorun bildir" page.
```

## Neden bu kadar kısa

Build 13'ün notu uzundu çünkü bir RED'i kapatıyordu (4.2 / 4.2.2). Bu sürümde kapatılan
bir red yok; iki değişiklik var ve ikisi de doğrulanabilir. Yapılmayan şeyi anlatmak
inceleyicinin işini uzatır, yapılanı gizlemek ise güveni kırar — ikisinden de kaçınıldı.

⚠ "Sorun bildir" ekranı GİRİŞ İSTER. Bunu nota yazmazsak inceleyici boş/giriş ekranı
görüp özelliği bulamaz ve "eksik işlevsellik" diye dönebilir.
