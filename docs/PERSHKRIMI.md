# Wonder Club · Wonder Churros: përshkrimi i projektit

> **Për kë është ky dokument:** për zhvilluesin ose agjentin në cloud që do ta ndërtojë aplikacionin e plotë.
> Këtu përshkruhet versioni i tanishëm: app-i i klientit dhe i dyqanit, të lidhur me një bazë të dhënash të përbashkët (Neon Postgres) përmes `/api/rpc`, rregullat e biznesit, struktura e kodit dhe hapat e mbetur.
>
> Gjendja: 16 nëntor 2026 · Linku live: https://wonder-churros.vercel.app (klientët) dhe https://wonder-churros.vercel.app/admin (stafi dhe admini)

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
| Hyrja | Email, pastaj: nëse email-i ekziston, **PIN-i** (4–6 shifra); nëse jo, **emri, mbiemri dhe një PIN i zgjedhur nga klienti** (dy herë). "Harrove PIN-in?" e dërgon te stafi: admini i vendos PIN të ri. Seanca ruhet 180 ditë në telefon. Poshtë është linku **"Si funksionon Wonder Club?"**, që hap shpjegimin në 6 hapa (regjistrimi, pikët, i 10-ti falas, dhuratat, ofertat, ditëlindja) dhe poshtë tij **menynë pa çmime** për vizitorët: kartela me foto që rrëshqasin anash, sipas kategorive, plus dip-et. Ka dy skeda kërcimi ("Si funksionon" / "Menyja") dhe butonin "Krijo llogarinë falas" (`howSheet()`). |
| Start | Përshëndetje, pikët totale, foto karusel, oferta, dhurata e ditëlindjes (kur është muaji i saj). |
| Menu | 7 kategori me foto: Standard churros (2), Uno churros (6), Party box (4), Wonder box and cup (4), Kids box (1), Flavored Latte (1), Coffee (4). Plus 7 dip shtesë në listën e arkës. Vetëm tekst, pa ikona para emrave. Klikimi i produktit hap faqen e tij: foto, lloji, përmbajtja, **QR e produktit me zgjedhje sasie (1–20)**, dip-et ose shijet, përshkrimi, çmimi. |
| Kuleta | **Rifreskohet vetë çdo 4 sekonda**: kur stafi shton pikë, ato shfaqen menjëherë me njoftimin "+X pikë u shtuan". Në krye, në të njëjtën kartelë: **pikët + QR personal + emri dhe ID**, shiriti i progresit, dhe poshtë udhëzimi për dy hapat në arkë. **"Produkt falas për ty"** shfaqet vetëm kur pikët e një produkti arrijnë pragun, me butonin "Merre falas". **"Dhurata dhe zbritje":** dhuratat personale, zbritjet dhe dhuratat e kompanisë (`PROMOS`, edhe në %), oferta 60 sekondëshe. Kur kompania s'ka promocion, ka një vend bosh të rezervuar. Në fund historiku. |
| Profili ("Llogaria ime") | Kartelë personale: inicialet, emri, mbiemri, "Anëtar që nga", email-i, telefoni (nëse ka), ID-ja, data e lindjes. "Ndrysho të dhënat": telefoni (opsional, i validuar) dhe data e lindjes (vendoset vetëm një herë). Ruhen në server. "Si funksionon Wonder Club?", dalja. |

### Dyqani (`/admin`)
| Skeda | Kush | Çfarë bën |
|---|---|---|
| Paneli | admin | **Dashboard live** (rifreskohet çdo 4 sekonda): shitje sot (€ + numri i blerjeve), shitje këtë muaj, klientë (+ të rinj këtë javë), klientë aktivë 30 ditë, dhurata të përdorura / të hapura, pikë në kuleta. Grafiku i shitjeve 14 ditë, produktet më të shitura 30 ditë, stafi sot, aktiviteti i fundit (klikohet dhe hap klientin). |
| Arka | staf + admin | **Rrjedha me dy hapa në një seancë kamere:** (1) skanon QR-në e klientit, klienti lidhet dhe kamera mbetet e hapur; (2) skanon QR-në e produktit **në telefonin e klientit** (sasia është brenda kodit), regjistrohet blerja dhe kamera mbyllet. Klienti gjendet edhe me ID, email ose telefon. Kartela e klientit rifreskohet live (p.sh. kur klienti aktivizon ofertën). "Anulo" heq blerjen (deri 30 minuta, vetëm stafi që e bëri ose admini). Regjistrim me dorë (produkti + sasia). Validon ofertën. Shënon dhuratën si të përdorur. |
| QR e produkteve | admin | Rezervë: QR për çdo produkt me çmim (29, 1 copë për skanim), sipas kategorive, me buton printimi (4 kode për rresht në A4). |
| Klientët | admin | Të gjithë klientët, me kërkim (emër, email, telefon, ID): pikë, blerje, shpenzuar, vizita e fundit. Klikimi hap detajet: të dhënat, pikët sipas produktit, dhuratat, historiku; **jep dhuratë** dhe **vendos PIN të ri**. |
| Promocionet | admin | Krijon zbritje (%) ose dhuratë me tituj e data. Shfaqen menjëherë te kuleta e të gjithë klientëve brenda datave. Mund të hiqen. |
| Stafi | admin | Shton dhe fshin staf (emër + PIN 4–6 shifra). Ndryshon PIN-in e vet. |

- **Hyrja e stafit:** admini i parë krijohet një herë të vetme te `/admin` me **kodin e konfigurimit** (variabla `SETUP_CODE` në Vercel). Më pas hyhet me përdoruesin `admin` ose me emrin e stafit, plus PIN-in. Seanca e stafit zgjat 14 orë. Të gjitha PIN-et ruhen me bcrypt. Pas 5 PIN-eve të gabuara llogaria bllokohet 15 minuta.
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
| 39 | Uno Party Box (6 Uno churros me shije të ndryshme) | Party box | 12.00 |
| 40 | Party Box Mini & Uno (Uno churros + mini churros + 3 dip) | Party box | 12.00 |
| 7 | Summer Box (40 mini + fruta + 4 dip) | Party box | 13.00 |
| 20 | Twist Churros (të zhytur në çokollatë) | Wonder box and cup | 1.80 |
| 3 | Wonder Duo (5 churros + 2 dip) | Wonder box and cup | 3.50 |
| 4 | Mini Churros Cup (15 mini + 2 toppings) | Wonder box and cup | 2.50 |
| 5 | Wonder Bites (20 mini + fruta + 2 dip) | Wonder box and cup | 3.50 |
| 27 | Flavoured Latte (Caramel, Hazelnut, Toffee Crunch, Speculoos Cookie, Vanilla, Popcorn) | Flavored Latte | 2.00 |
| 28–31 | Americano 1.50 · Espresso 1.00 · Macchiato 1.50 · Hot Choco 1.50 | Coffee | |
| 41 | Kids Box (churros në gotë + Monte Drink + bllok vizatimi) | Kids box | 3.99 |
| 32–38 | Dip: Raspberry, Blueberry, Hazelnut, Vanilla, Nutella, Caramel, Pistachio | Dip | 0.50 secili |

Një produkt i ri mund të shtohet pa çmim (`p:null`): shfaqet në meny me "Së shpejti", por **nuk ka QR, nuk mbledh pikë dhe nuk del te arka** derisa të vendoset çmimi (`RC()` kthen `Infinity`, `KP()` shfaq "Së shpejti").

---

## 4. Formati i kodeve QR

| QR | Përmbajtja | Shembull |
|---|---|---|
| Klienti | `WONDER:<ID>` | `WONDER:WC924EBE` |
| Produkti | `WONDER-P:<id>` ose `WONDER-P:<id>:<sasia>` (sasia 2–20) | `WONDER-P:20` = 1 Twist · `WONDER-P:1:3` = 3 Churros Standard |

- ID-ja e klientit: `WC` + 6 shkronja ose shifra.
- QR-ja e klientit nuk përmban më të dhëna personale. Stafi e gjen klientin në server me ID-në. QR-të e vjetra (me emrin brenda) lexohen ende.
- Kodet e produkteve janë fikse. Kodet e printuara mbeten të vlefshme për sa kohë nuk ndryshon ID-ja e produktit.

---

## 5. Struktura e kodit

```
/
├── index.html              ← i gjithë app-i (HTML + CSS + JS, pa build). Të njëjtin skedar e shërbejnë / dhe /admin
├── api/rpc.js              ← API (Vercel Function, Node): POST /api/rpc {fn, args} → thërret funksionet wc_* në Postgres
├── db/schema.sql           ← skema `churros` + të gjitha funksionet; ekzekutohet automatikisht kur ndryshon versioni
├── package.json            ← varësia `pg`
├── vercel.json             ← /admin → index.html, cleanUrls, cache për /img, funksioni api/rpc.js
├── manifest.webmanifest    ← PWA
├── icon-192.png, icon-512.png, apple-touch-icon.png
├── img/                    ← fotot e produkteve dhe logot
├── js/qrcode.js            ← qrcode-generator 1.4.4 (krijon QR-të)
├── js/jsqr.js              ← jsQR 1.4.0 (lexon QR-të kur nuk ka BarcodeDetector)
└── docs/
    ├── PERSHKRIMI.md       ← ky dokument
    ├── backend-propozim.sql← propozimi i vjetër (zëvendësuar nga db/schema.sql)
    └── screenshots/
```

### Brenda `index.html`
- `STAFF_APP`: `true` kur adresa është `/admin` ose `#admin`. Ai vendos cili app shfaqet.
- `MENU`, `CATS`, `CATIC`, `DS`, `XI`, `DIPS`, `FLAV`, `IMG`, `IMGL`: të dhënat e menysë dhe të fotove.
- **Klienti:** `render()`, `vHome()`, `vMenu()`, `vProd()`, `vWal()`, `vMe()`, `renderAuth()`.
- **Stafi:** `renderStaff()`, `stArka()`, `stQR()`, `stStaf()`, `stKl()`, `staffAct()`, `addPurchase()`.
- **Skaneri:** `startScan()`, `stopScan()`, `handleCode()` (logjika: klienti lidhet, produkti regjistrohet), `linkCustomer()`, `onScan()`, `parseQR()`, `parseP()`, `qrPay()`, `PQR(id, sasia)`. QR-ja e produktit te klienti: `pqrCard()`.
- **Lidhja me serverin:** `api(fn, args)`. Klienti: `S` (token në `localStorage['wc_tok']`, kartela `S.me`), `pollMe()` çdo 4 s. Stafi: `ST` (token në `localStorage['wc_stok']`), `staffPoll()`, `loadTab()`. Dashboard-i: `stDash()`, `barChart()`. Klientët: `stKl()`, `custSheet()`. Promocionet: `stPromo()`.
- Në telefon ruhen vetëm token-ët e seancës. Të gjitha të dhënat janë në server.

### API (`/api/rpc`)
| fn | Kush | Çfarë bën |
|---|---|---|
| `exists`, `register`, `login`, `logout` | klienti | hyrja me email + PIN |
| `me`, `setPhone`, `setBday`, `claimBday`, `activateOffer`, `redeem` | klienti | kuleta dhe profili |
| `hasAdmin`, `setupAdmin` | — | krijimi i adminit të parë (me `SETUP_CODE`) |
| `staffLogin`, `staffMe`, `find`, `card`, `addPurchase`, `undoOrder`, `useVoucher`, `validateOffer`, `changePin` | stafi | arka |
| `dashboard`, `customers`, `customer`, `resetPin`, `giveGift`, `promos`, `promoAdd`, `promoDel`, `staffList`, `addStaff`, `delStaff` | admini | paneli |

Përgjigjja: `{data}` ose `{error:"KODI"}` (p.sh. `PIN`, `LOCKED`, `SESSION`, `FORBIDDEN`). Pikët llogariten **vetëm në server**, nga çmimet në tabelën `churros.products`. Kur ndryshon një çmim, ndryshohet te `MENU` në `index.html` dhe te `db/schema.sql`, dhe rritet `SCHEMA_VERSION` në `api/rpc.js`.

### Tabelat (`churros.*`)
`products`, `customers` (email, emri, telefoni, PIN bcrypt, ditëlindja), `staff`, `sessions` (token-ët si SHA-256), `points` (pikët për klient × produkt), `vouchers` (dhuratat), `offers`, `orders` (çdo blerje, me stafin dhe anulimin), `promos`, `meta` (versioni i skemës).

### Variablat në Vercel
- `DATABASE_URL`: lidhja me Neon (pooled), e fshehtë.
- `SETUP_CODE`: kodi për krijimin e adminit të parë.

### Kod i papërdorur (mund të hiqet)
- **JS:** `TIERS`, `tier()` dhe `nextT()` (nivelet Bronz, Argjend, Ar; `tier()` thirret te `stArka()`, por rezultati nuk përdoret), `TOPUP` dhe `topS()` (ngarkimi i saldos, pa buton në ndërfaqe), `qrS()`, `fx()` (karuseli i vjetër i menysë).
- **CSS:** `#cartbar`, `.add`, `.qty`, `.tot`, `.bc`, `.grid`, `.rc`, `.blob`, `.churro`, `.sl.mc`, `.mcard`, `.mph`, `.go`.

---

## 6. Kufizimet e prototipit (duhet zgjidhur në versionin e plotë)

1. **Hyrja është me email + PIN, pa verifikim të email-it.** Për kod me email duhet një shërbim dërgimi (p.sh. Resend me domenin tuaj).
2. **Rifreskimi live bëhet me polling** (çdo 4 s), jo me WebSocket. Për një dyqan mjafton plotësisht.
3. Fontet (Poppins) ngarkohen nga Google Fonts.
4. Nuk ka ende eksport CSV dhe as menaxhim të menysë nga paneli.

---

## 7. Plani për aplikacionin e plotë

### Faza 1: backend ✅ (u krye më 16.11.2026)
- **Bazë të dhënash e veçantë vetëm për Wonder Churros.** ⚠️ **Mos përdorni projektin Supabase `038-parking`.** Pronari ka kërkuar shprehimisht që ai të mos preket.
- Propozimi gati është te `docs/backend-propozim.sql`: skema `churros` me tabelat `products`, `customers`, `staff`, `sessions`, `points`, `vouchers`, `offers`, `orders`. Klienti dhe stafi kanë qasje vetëm përmes funksioneve `wc_*`, që zbatojnë rregullat e seksionit 3 në server:
  `wc_register`, `wc_login`, `wc_me`, `wc_set_bday`, `wc_claim_bday`, `wc_activate_offer`, `wc_redeem`, `wc_staff_login`, `wc_find`, `wc_add_purchase`, `wc_use_voucher`, `wc_validate_offer`, `wc_customers`, `wc_add_staff`, `wc_del_staff`, `wc_change_pin`.
  PIN-et ruhen me bcrypt. Ka bllokim 15 minutash pas 5 përpjekjeve të gabuara.
- **Hyrja e klientit:** ose kod me email (duhet SMTP i vërtetë, p.sh. Resend), ose email + PIN, siç është në propozim.
- **Llogaria e adminit** krijohet nga pronari, jo nga "kushdo i pari".
- **Kohë reale:** kuleta e klientit rifreskohet automatikisht (Realtime ose polling çdo 3–5 sekonda) kur stafi shton pikë.
- Ndërfaqja ekzistuese mbetet. Zëvendësohet vetëm shtresa e të dhënave (`db`, `save()`, `U()`, `addPurchase()` etj.) me thirrje te API.

### Faza 2: përmirësime
- Admini: eksport CSV i klientëve dhe i blerjeve.
- Admini: menaxhimi i menysë (produkte, çmime, foto, "I RI") nga paneli, pa ndryshuar kodin.
- Njoftime (push) për dhuratat dhe ofertat.
- Fontet dhe librari lokale, pa varësi nga CDN.

### Faza 3: dyqanet e aplikacioneve (opsionale)
- Paketim me Capacitor për App Store (99 $ në vit) dhe Google Play (25 $ një herë).

---

## 8. Publikimi i tanishëm
- **GitHub:** `korabfazliu-cpu/korab`, dega `main`.
- **Vercel:** projekti `wonder-churros`. Çdo push në `main` publikohet automatikisht te https://wonder-churros.vercel.app.
- Nuk ka hap build-i. Është faqe statike.
- **Testimi lokal:** `npx vercel dev` me `DATABASE_URL` dhe `SETUP_CODE` në `.env`. Mund të përdoret edhe një PostgreSQL lokal: skema krijohet vetë në kërkesën e parë.

## 9. Testimi i bërë
U testua me Playwright në Chrome:
- regjistrimi, menyja dhe kategoritë, faqja e produktit;
- kuleta, oferta 60 sekondëshe, ditëlindja;
- hyrja e stafit dhe e adminit, PIN-i i gabuar;
- skanimi me kamerë i QR-së së klientit dhe të produktit (kamerë e simuluar);
- "Anulo", kodet e shtypura, regjistrimi me dorë;
- printimi i QR-ve dhe mbrojtja nga XSS.

Të gjitha kaluan, pa gabime JavaScript. **Skanimi me telefon të vërtetë duhet provuar në dyqan.**
- **Lidhja klient–admin (16.11)** u testua me PostgreSQL 16 lokal dhe dy shfletues (telefon + tablet): regjistrimi, konfigurimi i adminit, skanimi me kamerë (klient + 3 copë), pikët live te klienti me njoftim, oferta live te stafi, dhuratat, anulimi, promocionet live, stafi, paneli, kërkimi i klientëve, dhurata nga admini, ndryshimi i PIN-it, rifreskimet. Plus 35 kontrolle direkte të API-së.
- **Propozimi SQL** u testua në PostgreSQL 16 lokal: regjistrimi, hyrja, PIN-i i gabuar, blerja, produkti falas, oferta, validimi, ndalimi i stafit te funksionet e adminit, dhe ndalimi i qasjes direkte në tabela.
