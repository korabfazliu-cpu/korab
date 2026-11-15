# Wonder Club · Wonder Churros: përshkrimi i projektit

> **Për kë është ky dokument:** për zhvilluesin ose agjentin në cloud që do ta ndërtojë aplikacionin e plotë.
> Këtu përshkruhet versioni i tanishëm (prototipi i publikuar), rregullat e biznesit, struktura e kodit dhe çfarë mungon që aplikacioni të jetë gati për klientë realë.
>
> Gjendja: 15 nëntor 2026 · Linku live: https://wonder-churros.vercel.app (klientët) dhe https://wonder-churros.vercel.app/admin (stafi dhe admini)

---

## 1. Qëllimi

Program besnikërie për dyqanin **Wonder Churros**, me dy aplikacione:

1. **Aplikacioni i klientit:** menyja e produkteve, kuleta e pikëve me QR personal, dhuratat, ofertat dhe dhurata e ditëlindjes.
2. **Aplikacioni i dyqanit (staf + admin):** stafi skanon QR-në e klientit, pastaj skanon QR-në e produktit, dhe pikët shtohen automatikisht te kuleta e klientit. Admini menaxhon stafin dhe sheh të gjithë klientët.

**Nuk ka porosi online** në këtë fazë. Blerja bëhet fizikisht në dyqan, dhe app-i vetëm regjistron pikët.

Kërkesa kryesore e pronarit: *të dhënat e të gjithë klientëve të ruhen në llogarinë e adminit.*

---

## 2. Gjendja e tanishme: çfarë punon

### Klienti (`/`)
| Ekrani | Çfarë bën |
|---|---|
| Hyrja | Email, pastaj kodi 6-shifror, pastaj emri dhe mbiemri. **Kodi tani shfaqet në ekran ("Demo"), nuk dërgohet me email.** Ka edhe "Hyr me llogari demo". Poshtë është linku **"Si funksionon Wonder Club?"**, që hap shpjegimin në 6 hapa (regjistrimi, pikët, i 10-ti falas, dhuratat, ofertat, ditëlindja) dhe poshtë tij **menynë pa çmime** për vizitorët: kartela me foto që rrëshqasin anash, sipas kategorive, plus dip-et. Ka dy skeda kërcimi ("Si funksionon" / "Menyja") dhe butonin "Krijo llogarinë falas" (`howSheet()`). |
| Start | Përshëndetje, pikët totale, foto karusel, oferta, dhurata e ditëlindjes (kur është muaji i saj). |
| Menu | 7 kategori me foto: Standard churros (2), Uno churros (6), Party box (2), Wonder box and cup (4), Kids box (0, "së shpejti"), Flavored Latte (1), Coffee (4). Plus 7 dip shtesë në listën e arkës. Vetëm tekst, pa ikona para emrave. Klikimi i produktit hap faqen e tij: foto, lloji, përmbajtja, **QR e produktit me zgjedhje sasie (1–20)**, dip-et ose shijet, përshkrimi, çmimi. |
| Kuleta | Pikët, shiriti i progresit, dhuratat, "Produktet falas" (progresi për secilin produkt), ofertat, **QR personal + ID** me udhëzimin për dy hapat, historiku. |
| Profili | Emri, email-i, ID-ja, data e lindjes, "Si funksionon Wonder Club?", dalja. |

### Dyqani (`/admin`)
| Skeda | Kush | Çfarë bën |
|---|---|---|
| Arka | staf + admin | **Rrjedha me dy hapa në një seancë kamere:** (1) skanon QR-në e klientit, klienti lidhet dhe kamera mbetet e hapur; (2) skanon QR-në e produktit **në telefonin e klientit** (sasia është brenda kodit), regjistrohet blerja dhe kamera mbyllet. Klienti gjendet edhe me ID ose email. Butoni "Anulo" heq skanimin e fundit. Regjistrim me dorë (produkti + sasia). Validon ofertën. Shënon dhuratën si të përdorur. |
| QR e produkteve | admin | Rezervë: QR për çdo produkt (26, 1 copë për skanim), sipas kategorive, me buton printimi (4 kode për rresht në A4). |
| Stafi | admin | Shton dhe fshin staf (emër + PIN 4 deri në 8 shifra). |
| Klientët | admin | Lista e klientëve të regjistruar në këtë pajisje, me pikët. |

- **Hyrja e stafit:** herën e parë që hapet `/admin` në një pajisje, krijohet PIN-i i adminit. Më pas hyhet me përdoruesin `admin` ose me emrin e stafit, plus PIN-in. PIN-et ruhen si SHA-256.
- **Skaneri:** përdor `BarcodeDetector` aty ku e mbështet shfletuesi, përndryshe `jsQR` (`/js/jsqr.js`). Fusha e kërkimit pranon Enter, prandaj punon edhe me skaner USB ose Bluetooth.
- **PWA:** ka `manifest.webmanifest` dhe ikona, prandaj mund të shtohet në ekranin e telefonit.

Pamjet e ekraneve janë te `docs/screenshots/`.

---

## 3. Rregullat e biznesit (duhen ruajtur njësoj)

| Rregulli | Vlera |
|---|---|
| Pikët | **1 € blerje = 1 pikë.** Pikët mblidhen **për secilin produkt veç e veç**. |
| Produkti falas | Kur pikët e një produkti arrijnë **çmimi × 9** (9 blerje), klienti e merr të 10-tin falas. Pikët e atij produkti zbriten me çmimi × 9 dhe krijohet një dhuratë ("[Produkti] falas"). |
| Dhurata e mirëseardhjes | Çdo klient i ri merr 1 "Churros Standard falas" (2.50 €). |
| Oferta e mirëseardhjes | 1 € zbritje te Churros Large (4.90 € bëhet 3.90 €). Klienti e aktivizon, dhe ka **60 sekonda** për ta treguar në arkë. Koha nuk ndalet. Pas kësaj oferta skadon. Stafi e validon vetëm brenda kohës. |
| Ditëlindja | Klienti vendos datën e lindjes. Në muajin e ditëlindjes merr 1 "Mini Churros Cup falas", **një herë në vit**. *Në prototip data mund të ndryshohet, por në versionin e plotë duhet të vendoset vetëm një herë.* |
| Dhuratat | Shfaqen te kuleta ("Trego këtë në arkë"). Stafi i shënon si të përdorura. |
| Dip shtesë | 0.50 € secili. |

### Menyja (ID, çmimi)
| ID | Produkti | Kategoria | € |
|---|---|---|---|
| 1 | Churros Standard (5 churros + 1 dip) | Standard churros | 2.50 |
| 2 | Churros Large (10 churros + 2 dip) | Standard churros | 4.90 |
| 21–26 | Uno Lotus / Blueberry / Raspberry / Pistachio / Bueno / Caramel | Uno churros | 1.80 secili |
| 6 | Party Box (10 churros + 15 mini + 4 dip) | Party box | 12.00 |
| 7 | Summer Box (40 mini + fruta + 4 dip) | Party box | 13.00 |
| 20 | Twist Churros (të zhytur në çokollatë) | Wonder box and cup | 1.80 |
| 3 | Wonder Duo (5 churros + 2 dip) | Wonder box and cup | 3.50 |
| 4 | Mini Churros Cup (15 mini + 2 toppings) | Wonder box and cup | 2.50 |
| 5 | Wonder Bites (20 mini + fruta + 2 dip) | Wonder box and cup | 3.50 |
| 27 | Flavoured Latte (Caramel, Hazelnut, Toffee Crunch, Speculoos Cookie, Vanilla, Popcorn) | Flavored Latte | 2.00 |
| 28–31 | Americano 1.50 · Espresso 1.00 · Macchiato 1.50 · Hot Choco 1.50 | Coffee | |
| 32–38 | Dip: Raspberry, Blueberry, Hazelnut, Vanilla, Nutella, Caramel, Pistachio | Dip | 0.50 secili |

Kategoria **Kids box** ekziston, por ende pa produkte.

---

## 4. Formati i kodeve QR

| QR | Përmbajtja | Shembull |
|---|---|---|
| Klienti | `WONDER:<ID>:<base64url(JSON {n,s,e})>`. `n` = emri, `s` = mbiemri, `e` = email-i. | `WONDER:WCDJQKVD:eyJuIjoiQXJ0YSIs…` |
| Produkti | `WONDER-P:<id>` ose `WONDER-P:<id>:<sasia>` (sasia 2–20) | `WONDER-P:20` = 1 Twist · `WONDER-P:1:3` = 3 Churros Standard |

- ID-ja e klientit: `WC` + 6 shkronja ose shifra.
- QR-ja e klientit mbart edhe emrin, që pajisja e dyqanit ta regjistrojë klientin automatikisht kur e skanon herën e parë. **Kur të ketë server, mjafton `WONDER:<ID>` ose një token i nënshkruar.** Emri dhe email-i nuk duhet të jenë më në QR.
- Kodet e produkteve janë fikse. Kodet e printuara mbeten të vlefshme për sa kohë nuk ndryshon ID-ja e produktit.

---

## 5. Struktura e kodit

```
/
├── index.html              ← i gjithë app-i (HTML + CSS + JS, pa build). Të njëjtin skedar e shërbejnë / dhe /admin
├── vercel.json             ← /admin → index.html, cleanUrls, cache për /img
├── manifest.webmanifest    ← PWA
├── icon-192.png, icon-512.png, apple-touch-icon.png
├── img/                    ← fotot e produkteve dhe logot (34 skedarë)
├── js/qrcode.js            ← qrcode-generator 1.4.4 (krijon QR-të)
├── js/jsqr.js              ← jsQR 1.4.0 (lexon QR-të kur nuk ka BarcodeDetector)
└── docs/
    ├── PERSHKRIMI.md       ← ky dokument
    ├── backend-propozim.sql← propozim për bazën e të dhënave (I PA ZBATUAR)
    └── screenshots/
```

### Brenda `index.html`
- `STAFF_APP`: `true` kur adresa është `/admin` ose `#admin`. Ai vendos cili app shfaqet.
- `MENU`, `CATS`, `CATIC`, `DS`, `XI`, `DIPS`, `FLAV`, `IMG`, `IMGL`: të dhënat e menysë dhe të fotove.
- **Klienti:** `render()`, `vHome()`, `vMenu()`, `vProd()`, `vWal()`, `vMe()`, `renderAuth()`.
- **Stafi:** `renderStaff()`, `stArka()`, `stQR()`, `stStaf()`, `stKl()`, `staffAct()`, `addPurchase()`.
- **Skaneri:** `startScan()`, `stopScan()`, `handleCode()` (logjika: klienti lidhet, produkti regjistrohet), `linkCustomer()`, `onScan()`, `parseQR()`, `parseP()`, `qrPay()`, `PQR(id, sasia)`. QR-ja e produktit te klienti: `pqrCard()`.
- **Ruajtja:** `localStorage['wonder_v3']` mban klientët, stafin dhe hash-in e adminit. `localStorage['wonder_staff']` mban sesionin e stafit, vetëm te `/admin`.

### Struktura e klientit (`db.users[email]`)
```js
{ name, surname, email, mid:'WCXXXXXX', points, earned, pp:{ [productId]: pikë },
  vouchers:[{n, v}], offers:[{n, item, off, exp?, expired?}],
  orders:[{num, total, pts, n, q, d}], bday:'YYYY-MM-DD', bdayY }
```

### Kod i papërdorur (mund të hiqet)
- **JS:** `TIERS`, `tier()` dhe `nextT()` (nivelet Bronz, Argjend, Ar; `tier()` thirret te `stArka()`, por rezultati nuk përdoret), `TOPUP` dhe `topS()` (ngarkimi i saldos, pa buton në ndërfaqe), `qrS()`, `fx()` (karuseli i vjetër i menysë).
- **CSS:** `#cartbar`, `.add`, `.qty`, `.tot`, `.bc`, `.grid`, `.rc`, `.blob`, `.churro`, `.sl.mc`, `.mcard`, `.mph`, `.go`.

---

## 6. Kufizimet e prototipit (duhet zgjidhur në versionin e plotë)

1. **S'ka server ose bazë të dhënash.** Çdo pajisje ruan të dhënat e veta (`localStorage`). Pajisja e dyqanit mban klientët dhe pikët, por **telefoni i klientit nuk i sheh pikët që shton stafi**. Admini sheh vetëm klientët e skanuar në atë pajisje. Ky është problemi kryesor.
2. **Kodi i email-it nuk dërgohet.** Shfaqet në ekran.
3. **PIN-i i adminit** krijohet nga kushdo që hap i pari `/admin` në një pajisje të re.
4. **"Hyr me llogari demo"** duhet hequr para publikimit për klientët.
5. Të dhënat humbin nëse fshihet historiku i shfletuesit.
6. Fontet (Poppins) ngarkohen nga Google Fonts.

---

## 7. Plani për aplikacionin e plotë

### Faza 1: backend (domosdoshmëri)
- **Bazë të dhënash e veçantë vetëm për Wonder Churros.** ⚠️ **Mos përdorni projektin Supabase `038-parking`.** Pronari ka kërkuar shprehimisht që ai të mos preket.
- Propozimi gati është te `docs/backend-propozim.sql`: skema `churros` me tabelat `products`, `customers`, `staff`, `sessions`, `points`, `vouchers`, `offers`, `orders`. Klienti dhe stafi kanë qasje vetëm përmes funksioneve `wc_*`, që zbatojnë rregullat e seksionit 3 në server:
  `wc_register`, `wc_login`, `wc_me`, `wc_set_bday`, `wc_claim_bday`, `wc_activate_offer`, `wc_redeem`, `wc_staff_login`, `wc_find`, `wc_add_purchase`, `wc_use_voucher`, `wc_validate_offer`, `wc_customers`, `wc_add_staff`, `wc_del_staff`, `wc_change_pin`.
  PIN-et ruhen me bcrypt. Ka bllokim 15 minutash pas 5 përpjekjeve të gabuara.
- **Hyrja e klientit:** ose kod me email (duhet SMTP i vërtetë, p.sh. Resend), ose email + PIN, siç është në propozim.
- **Llogaria e adminit** krijohet nga pronari, jo nga "kushdo i pari".
- **Kohë reale:** kuleta e klientit rifreskohet automatikisht (Realtime ose polling çdo 3–5 sekonda) kur stafi shton pikë.
- Ndërfaqja ekzistuese mbetet. Zëvendësohet vetëm shtresa e të dhënave (`db`, `save()`, `U()`, `addPurchase()` etj.) me thirrje te API.

### Faza 2: përmirësime
- Admini: statistika (blerje sot, të ardhura, dhurata të përdorura), eksport CSV i klientëve, historik i plotë.
- Admini: menaxhimi i menysë (produkte, çmime, foto, "I RI") nga paneli, pa ndryshuar kodin.
- Oferta të reja të krijuara nga admini.
- Njoftime (push) për dhuratat dhe ofertat.
- Fontet dhe librari lokale, pa varësi nga CDN.

### Faza 3: dyqanet e aplikacioneve (opsionale)
- Paketim me Capacitor për App Store (99 $ në vit) dhe Google Play (25 $ një herë).

---

## 8. Publikimi i tanishëm
- **GitHub:** `korabfazliu-cpu/korab`, dega `main`.
- **Vercel:** projekti `wonder-churros`. Çdo push në `main` publikohet automatikisht te https://wonder-churros.vercel.app.
- Nuk ka hap build-i. Është faqe statike.
- **Testimi lokal:** `python3 -m http.server` nuk e njeh `/admin`, prandaj përdorni `npx vercel dev`, ose hapni `index.html#admin`.

## 9. Testimi i bërë
U testua me Playwright në Chrome:
- regjistrimi, menyja dhe kategoritë, faqja e produktit;
- kuleta, oferta 60 sekondëshe, ditëlindja;
- hyrja e stafit dhe e adminit, PIN-i i gabuar;
- skanimi me kamerë i QR-së së klientit dhe të produktit (kamerë e simuluar);
- "Anulo", kodet e shtypura, regjistrimi me dorë;
- printimi i QR-ve dhe mbrojtja nga XSS.

Të gjitha kaluan, pa gabime JavaScript. **Skanimi me telefon të vërtetë duhet provuar në dyqan.**
- **Propozimi SQL** u testua në PostgreSQL 16 lokal: regjistrimi, hyrja, PIN-i i gabuar, blerja, produkti falas, oferta, validimi, ndalimi i stafit te funksionet e adminit, dhe ndalimi i qasjes direkte në tabela.
