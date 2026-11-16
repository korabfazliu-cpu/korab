# Wonder Club · Wonder Churros: përshkrimi i projektit

> **Për kë është ky dokument:** për zhvilluesin ose agjentin në cloud që do ta ndërtojë aplikacionin e plotë.
> Këtu përshkruhet versioni i tanishëm: app-i i klientit dhe i dyqanit, të lidhur me një bazë të dhënash të përbashkët (Neon Postgres) përmes `/api/rpc`, rregullat e biznesit, struktura e kodit dhe hapat e mbetur.
>
> Gjendja: 16 nëntor 2026 · Linku live: https://wonder-churros.vercel.app (klientët) dhe https://wonder-churros.vercel.app/admin (stafi dhe admini)

---

## 0. Publikimi në cloud, shkurt

1. **Kodi:** hapni zip-in (ose degën `backend` në GitHub). Nuk ka hap build-i: `index.html` + `api/rpc.js` (Node 18+) + `db/schema.sql`.
2. **Baza:** krijoni një bazë **PostgreSQL** (p.sh. Neon, falas). Mos përdorni projektin Supabase `038-parking`.
3. **Hostimi:** Vercel (ose çdo host që shërben faqe statike + një funksion Node). Te Vercel: *Import* projektin, pa Framework, pa Build Command.
4. **Variablat:** `DATABASE_URL` (lidhja *pooled* e bazës, Sensitive) dhe `SETUP_CODE` (një kod i fshehtë për adminin e parë).
5. **Hapi i parë:** hapni `/admin`, futni `SETUP_CODE` dhe zgjidhni PIN-in e adminit. Tabelat krijohen vetë në kërkesën e parë. Klientët përdorin `/`.

Për App Store dhe Google Play, shih seksionin 8, Faza 3.

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
| Kuleta | **Rifreskohet vetë çdo 4 sekonda**: kur stafi shton pikë, ato shfaqen menjëherë me njoftimin "+X pikë u shtuan". Në krye, në të njëjtën kartelë: **pikët + QR personal + emri dhe ID**, shiriti i progresit, dhe poshtë udhëzimi për dy hapat në arkë. **"Produkt falas për ty"** shfaqet vetëm kur pikët e një produkti arrijnë pragun, me butonin "Merre falas". **"Dhurata dhe zbritje":** dhuratat personale, promocionet e kompanisë (edhe në %) dhe oferta 60 sekondëshe. Secila ka butonin **Aktivizo**, që hap një **QR unik** për atë klient dhe atë dhuratë. Stafi e skanon dhe dhurata **shfrytëzohet menjëherë**: telefoni i klientit kalon vetë në "✓ U shfrytëzua!" dhe dhurata del te **"Të shfrytëzuara"**. Një promocion shfrytëzohet një herë për klient. Te oferta, QR-ja vlen vetëm 60 sekonda. Kur kompania s'ka promocion, ka një vend bosh të rezervuar. Në fund historiku. |
| Profili ("Llogaria ime") | Kartelë personale: inicialet, emri, mbiemri, "Anëtar që nga", email-i, telefoni (nëse ka), ID-ja, data e lindjes. "Ndrysho të dhënat": telefoni (opsional, i validuar) dhe data e lindjes (vendoset vetëm një herë). Ruhen në server. "Si funksionon Wonder Club?", dalja. |

### Dyqani (`/admin`)

**Tre lloje përdoruesish:**
| Roli | Kush | Qasja |
|---|---|---|
| **Pronar** (`admin`) | krijohet një herë me `SETUP_CODE` | gjithçka; vetëm ai shton dhe fshin menaxherë |
| **Menaxher** (`manager`) | e shton pronari | gjithçka (paneli, shitjet, anulimi, **stoku**, klientët, ofertat, QR), shton dhe fshin staf |
| **Staf** (`staff`) | e shton pronari ose menaxheri | **vetëm Arka**: shitja, klienti, dhuratat, pagesa, kuponi (printimi) dhe shënimi fiskal. Nuk sheh listën e shitjeve, nuk anulon, nuk ka qasje te stoku apo klientët. Kufizimi zbatohet edhe në server. |

| Skeda | Kush | Çfarë bën |
|---|---|---|
| Paneli | admin | **Dashboard live** (rifreskohet çdo 4 sekonda): shitje sot (€, numri, cash dhe kartë), paralajmërim kur ka shitje pa u shënuar në arkën fiskale, shitje këtë muaj, klientë (+ të rinj këtë javë), klientë aktivë 30 ditë, dhurata të përdorura / të hapura, pikë në kuleta. Grafiku i shitjeve 14 ditë, produktet më të shitura 30 ditë, stafi sot, aktiviteti i fundit (klikohet dhe hap klientin). |
| **Arka** (shitja) | staf + admin | **Arkë shitëse për PC, tablet ose telefon.** Majtas produktet me foto, me kategori dhe kërkim; djathtas **fatura**: sasitë me − / +, klienti (opsional), dhuratat/zbritjet, nëntotali, zbritja, **totali** dhe pikët që fiton klienti. Pagesa **Cash** (paratë e marra, butonat Saktë / 5 / 10 / 20 / 50 €, **kusuri** llogaritet vetë) ose **Kartë**. "Përfundo shitjen" (ose **F9**) e ruan shitjen, shfrytëzon kodet dhe shton pikët te kuleta e klientit. Pastaj del **kuponi jo-fiskal** (printohet në printer 58/80 mm) dhe hapi **"U regjistrua në arkën fiskale"** me numrin e kuponit fiskal. **Skaneri USB/Bluetooth** punon kudo në faqe: skanon QR-në e klientit, të produktit (me sasi) ose të dhuratës, dhe ato shtohen në faturë. Mund të përdoret edhe kamera. Në telefon fatura del poshtë, me shiritin "🧾 Shporta". |
| Shitjet | staf + admin | Shitjet e ditës (zgjidhet data): numri, totali, cash, kartë, zbritjet dhe sa janë **pa fiskalizuar**. Klikimi hap kuponin: ribotim, shënim fiskal, dhe **anulim (vetëm admini)**. Anulimi heq pikët dhe i rikthen dhuratat/zbritjet e përdorura. |
| Pikë | staf + admin | **Rrjedha e vjetër me dy hapa (vetëm pikë, pa shitje) në një seancë kamere:** (1) skanon QR-në e klientit, klienti lidhet dhe kamera mbetet e hapur; (2) skanon QR-në e produktit **në telefonin e klientit** (sasia është brenda kodit), regjistrohet blerja dhe kamera mbyllet. Klienti gjendet edhe me ID, email ose telefon. Kartela e klientit rifreskohet live (p.sh. kur klienti aktivizon ofertën). "Anulo" heq blerjen (deri 30 minuta, vetëm stafi që e bëri ose admini). Regjistrim me dorë (produkti + sasia). Validon ofertën. Shënon dhuratën si të përdorur. |
| QR e produkteve | admin | Rezervë: QR për çdo produkt me çmim (29, 1 copë për skanim), sipas kategorive, me buton printimi (4 kode për rresht në A4). |
| Klientët | admin | Të gjithë klientët, me kërkim (emër, email, telefon, ID): pikë, blerje, shpenzuar, vizita e fundit. Klikimi hap detajet: të dhënat, pikët sipas produktit, dhuratat, **dhuratat/zbritjet e shfrytëzuara (kur dhe nga kush)**, historiku; **jep dhuratë** dhe **vendos PIN të ri**. |
| Ofertat | admin | Krijon **zbritje (%)**, **zbritje (€)** ose **dhuratë**, me titull, përshkrim dhe data. **Kujt i dërgohet:** *Të gjithë klientët* ose *Klientë të zgjedhur*. Zgjedhësi ka kërkim, shenja për zgjedhje, "Zgjidh të gjitha" dhe çipat e të zgjedhurve. Klientët e zgjedhur e shohin te Kuleta me shenjën "Vetëm për ty"; të tjerët nuk e shohin dhe nuk mund ta aktivizojnë. Nga kartela e një klienti: "Dërgo ofertë, zbritje ose dhuratë këtij klienti". Te lista shfaqet kujt i është dërguar dhe sa herë është shfrytëzuar. Mund të hiqen. |
| **Stoku** | menaxher + pronar | Artikujt e stokut (emri, njësia copë/kg/g/l/ml/pako, sasia, minimumi). Për çdo artikull: **Hyrje** (malli që erdhi), **Dalje / humbje**, **Numërim** (vendos sasinë reale), me shënim. **Recetat:** sa harxhon 1 copë e çdo produkti nga secili artikull; çdo shitje e zbret stokun vetë dhe anulimi e rikthen. Artikujt nën minimum dalin të parët, me ngjyrë, dhe paneli paralajmëron. Lëvizjet e fundit (kush, kur, shitja). Shitja nuk bllokohet kurrë nga stoku. |
| Stafi | menaxher + pronar | Shton dhe fshin përdorues (emër + PIN 4–6 shifra), me rolin Staf ose Menaxher (Menaxher: vetëm pronari). Ndryshon PIN-in e vet. Fshirja mbyll menjëherë seancat e atij përdoruesi. |

- **Hyrja e stafit:** admini i parë krijohet një herë të vetme te `/admin` me **kodin e konfigurimit** (variabla `SETUP_CODE` në Vercel). Më pas hyhet me përdoruesin `admin` ose me emrin e stafit, plus PIN-in. Seanca e stafit zgjat 14 orë. Të gjitha PIN-et ruhen me bcrypt. Pas 5 PIN-eve të gabuara llogaria bllokohet 15 minuta.
- **Skaneri:** përdor `BarcodeDetector` aty ku e mbështet shfletuesi, përndryshe `jsQR` (`/js/jsqr.js`). Fusha e kërkimit pranon Enter, prandaj punon edhe me skaner USB ose Bluetooth.
- **PWA:** ka `manifest.webmanifest` dhe ikona, prandaj mund të shtohet në ekranin e telefonit.

Pamjet e ekraneve janë te `docs/screenshots/`.

---

## 3. Rregullat e biznesit (duhen ruajtur njësoj)

| Rregulli | Vlera |
|---|---|
| Pikët | **1 € blerje = 1 pikë.** Pikët mblidhen **për secilin produkt veç e veç**. Te arka, pikët llogariten mbi **shumën e paguar**: kur ka zbritje, pikët e çdo produkti ulen në të njëjtin raport. |
| Produkti falas | Kur pikët e një produkti arrijnë **çmimi × 9** (9 blerje), klienti e merr të 10-tin falas. Pikët e atij produkti zbriten me çmimi × 9 dhe krijohet një dhuratë ("[Produkti] falas"). |
| Dhurata e mirëseardhjes | Çdo klient i ri merr 1 "Churros Standard falas" (2.50 €). |
| Oferta e mirëseardhjes | 1 € zbritje te Churros Large (4.90 € bëhet 3.90 €). Klienti e aktivizon dhe i shfaqet një QR që vlen **60 sekonda**. Koha nuk ndalet. Stafi e skanon brenda kohës, pastaj oferta skadon. |
| Ditëlindja | Klienti vendos datën e lindjes. Në muajin e ditëlindjes merr 1 "Mini Churros Cup falas", **një herë në vit**. Data vendoset vetëm një herë. |
| Dhuratat dhe zbritjet | Klienti shtyp "Aktivizo", stafi skanon QR-në unike dhe dhurata shfrytëzohet menjëherë. Çdo shfrytëzim ruhet (kur, nga kush). Promocionet: një herë për klient. |
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
| Dhuratë / zbritje | `WONDER-G:<V\|P\|O><id>.<kodi 8 hex>`: V = dhuratë, P = promocion (id e përdorimit), O = ofertë. Kodi është i rastësishëm dhe ruhet në bazë. | `WONDER-G:V37.30ac18a3` |

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
- **Stafi:** `renderStaff()`, `stArka()`, `stDash()`, `stKl()`, `stPromo()`, `stStaf()`, `stQR()`, `staffAct()`, `purchase()`.
- **Skaneri:** `startScan()`, `stopScan()`, `handleCode()` (klienti lidhet, produkti regjistrohet, dhurata shfrytëzohet), `onScan()`, `parseQR()`, `parseP()`, `qrPay()`, `PQR(id, sasia)`. QR-ja e produktit te klienti: `pqrCard()`. QR-ja e dhuratës: `gSheet()`, `gItem()`, `gCheck()`.
- **Lidhja me serverin:** `api(fn, args)`. Klienti: `S` (token në `localStorage['wc_tok']`, kartela `S.me`), `pollMe()` çdo 4 s. Stafi: `ST` (token në `localStorage['wc_stok']`), `staffPoll()`, `loadTab()`. Dashboard-i: `stDash()`, `barChart()`. Klientët: `stKl()`, `custSheet()`. Promocionet: `stPromo()`.
- Në telefon ruhen vetëm token-ët e seancës. Të gjitha të dhënat janë në server.

### API (`/api/rpc`)
| fn | Kush | Çfarë bën |
|---|---|---|
| `exists`, `register`, `login`, `logout` | klienti | hyrja me email + PIN |
| `me`, `setPhone`, `setBday`, `claimBday`, `activateOffer`, `redeem` | klienti | kuleta dhe profili |
| `hasAdmin`, `setupAdmin` | — | krijimi i adminit të parë (me `SETUP_CODE`) |
| `codePeek`, `saleCreate`, `sales`, `saleFiscal` | stafi | arka: shiko kodin pa e përdorur, krijo shitjen (çmimet dhe zbritjet llogariten në server, kodet shfrytëzohen në të njëjtin transaksion), shitjet e ditës, shënimi fiskal |
| `saleVoid` | menaxher + pronar | anulon shitjen dhe rikthen stokun |
| `stock`, `stockSave`, `stockMove`, `stockDel`, `recipeSet` | menaxher + pronar | stoku dhe recetat |
| `promoActivate` | klienti | krijon kodin e tij për një promocion |
| `staffLogin`, `staffMe`, `find`, `card`, `addPurchase`, `undoOrder`, `redeemCode`, `useVoucher`, `validateOffer`, `changePin` | stafi | arka (`redeemCode` shfrytëzon një dhuratë/zbritje nga QR-ja) |
| `dashboard`, `customers`, `customer`, `resetPin`, `giveGift`, `promos`, `promoAdd`, `promoDel`, `staffList`, `addStaff`, `delStaff` | admini | paneli |

Përgjigjja: `{data}` ose `{error:"KODI"}` (p.sh. `PIN`, `LOCKED`, `SESSION`, `FORBIDDEN`). Pikët llogariten **vetëm në server**, nga çmimet në tabelën `churros.products`. Kur ndryshon një çmim, ndryshohet te `MENU` në `index.html` dhe te `db/schema.sql`, dhe rritet `SCHEMA_VERSION` në `api/rpc.js`.

### Tabelat (`churros.*`)
`products`, `customers` (email, emri, telefoni, PIN bcrypt, ditëlindja), `staff`, `sessions` (token-ët si SHA-256), `points` (pikët për klient × produkt), `vouchers` (dhuratat, me `code`), `offers` (me `code`), `orders` (çdo blerje, me stafin dhe anulimin), `promos` (`kind` pct/eur/gift, `amount`, `audience` all/some), `promo_targets` (klientët e zgjedhur), `promo_uses` (kush e shfrytëzoi cilin promocion, kur dhe nga cili staf), `sales` (shitjet: nëntotali, zbritja, totali, pagesa, kusuri, statusi fiskal `pending/done/failed`, numri fiskal, anulimi), `sale_items`, `sale_discounts`, `stock_items` (artikujt, sasia, minimumi), `stock_moves` (çdo lëvizje: hyrje, dalje, numërim, shitje, anulim, me sasinë pas saj), `recipes` (produkt × artikull × sasi), `meta` (versioni i skemës). Pamjet `tickets` dhe `lines` bashkojnë shitjet e arkës me skanimet e vjetra vetëm-pikë për panelin. Çdo shfrytëzim ruan `used_at` dhe `used_by`, që të figurojë te admini.

### Variablat në Vercel
- `DATABASE_URL`: lidhja me Neon (pooled), e fshehtë.
- `SETUP_CODE`: kodi për krijimin e adminit të parë.

### Kod i papërdorur (mund të hiqet)
- **JS:** konstantet `TIERS`, `REW`, `TOPUP`, `CC`, `CATIMG` dhe funksioni `fx()` (karuseli i vjetër i menysë).
- **CSS:** `#cartbar`, `.add`, `.qty`, `.tot`, `.bc`, `.grid`, `.rc`, `.blob`, `.churro`, `.sl.mc`, `.mcard`, `.mph`, `.go`.

---

## 6. Lidhja me arkën fiskale (hapi i ardhshëm)

Tani arka e Wonder Club është **arkë shitëse jo-fiskale**: çdo shitje ruhet me statusin fiskal `pending`, dhe stafi e regjistron në arkën fiskale dhe shënon numrin e kuponit fiskal (`saleFiscal`). Kjo mbetet edhe rezerva kur lidhja automatike nuk punon.

Për lidhjen automatike duhen:
1. **Pajisja fiskale ose ofruesi i softuerit fiskal i certifikuar nga ATK**, me dokumentacionin e tyre teknik (protokolli, API ose drajveri). ATK ka në EDI shërbimin "Kërkesë për Fiskalizim", që jep Kodin Unik për Fiskalizim, kusht për Softuerin Elektronik Fiskal (UA MF Nr. 01/2026).
2. **Një urë lokale në PC-në e arkës** (program i vogël): e merr shitjen nga `/api/rpc`, e dërgon te printeri fiskal (USB/serial/rrjet), dhe e kthen numrin fiskal me `saleFiscal`. Shfletuesi nuk mund të flasë drejtpërdrejt me printerin fiskal.
3. Testim me ofruesin, dhe konfirmim nga kontabilisti që procedura është në rregull.

Fushat `fiscal_status`, `fiscal_no`, `fiscal_at`, `fiscal_error` janë gati për këtë.

## 7. Kufizimet e prototipit (duhet zgjidhur në versionin e plotë)

1. **Hyrja është me email + PIN, pa verifikim të email-it.** Për kod me email duhet një shërbim dërgimi (p.sh. Resend me domenin tuaj).
2. **Rifreskimi live bëhet me polling** (çdo 4 s), jo me WebSocket. Për një dyqan mjafton plotësisht.
3. Fontet (Poppins) ngarkohen nga Google Fonts.
4. Nuk ka ende eksport CSV dhe as menaxhim të menysë nga paneli.

---

## 8. Plani për aplikacionin e plotë

### Faza 1: backend ✅ (u krye më 16.11.2026)
- **Bazë të dhënash e veçantë vetëm për Wonder Churros.** ⚠️ **Mos përdorni projektin Supabase `038-parking`.** Pronari ka kërkuar shprehimisht që ai të mos preket.
- Baza: Neon Postgres (falas), skema `churros` te `db/schema.sql`, API te `api/rpc.js`. Rregullat e seksionit 3 zbatohen në server.
- Hyrja e klientit: email + PIN. Admini i parë: me `SETUP_CODE`. Rifreskimi live: polling çdo 4 s.
- **Mbetet:** të vendoset `DATABASE_URL` në Vercel dhe dega `backend` të bashkohet me `main`.

### Faza 2: përmirësime
- Admini: eksport CSV i klientëve dhe i blerjeve.
- Admini: menaxhimi i menysë (produkte, çmime, foto, "I RI") nga paneli, pa ndryshuar kodin.
- Njoftime (push) për dhuratat dhe ofertat.
- Fontet dhe librari lokale, pa varësi nga CDN.

### Faza 3: dyqanet e aplikacioneve (opsionale)
- Paketim me Capacitor për App Store (99 $ në vit) dhe Google Play (25 $ një herë).

---

## 9. Publikimi i tanishëm
- **GitHub:** `korabfazliu-cpu/korab`. Dega `main` është versioni i vjetër, pa server, që është live tani. Dega **`backend`** ka versionin me bazë të dhënash dhe dashboard, dhe bashkohet me `main` sapo të vendoset `DATABASE_URL`.
- **Vercel:** projekti `wonder-churros`. Çdo push në `main` publikohet automatikisht te https://wonder-churros.vercel.app.
- Nuk ka hap build-i: faqe statike + një Vercel Function (`api/rpc.js`).
- **Testimi lokal:** `npx vercel dev` me `DATABASE_URL` dhe `SETUP_CODE` në `.env`. Mund të përdoret edhe një PostgreSQL lokal: skema krijohet vetë në kërkesën e parë.

## 10. Testimi i bërë
U testua me Playwright në Chrome:
- regjistrimi, menyja dhe kategoritë, faqja e produktit;
- kuleta, oferta 60 sekondëshe, ditëlindja;
- hyrja e stafit dhe e adminit, PIN-i i gabuar;
- skanimi me kamerë i QR-së së klientit dhe të produktit (kamerë e simuluar);
- "Anulo", kodet e shtypura, regjistrimi me dorë;
- printimi i QR-ve dhe mbrojtja nga XSS.

Të gjitha kaluan, pa gabime JavaScript. **Skanimi me telefon të vërtetë duhet provuar në dyqan.**
- **Lidhja klient–admin (16.11)** u testua me PostgreSQL 16 lokal dhe dy shfletues (telefon + tablet): regjistrimi, konfigurimi i adminit, skanimi me kamerë (klient + 3 copë), pikët live te klienti me njoftim, oferta live te stafi, dhuratat, anulimi, promocionet live, stafi, paneli, kërkimi i klientëve, dhurata nga admini, ndryshimi i PIN-it, rifreskimet. Plus 35 kontrolle direkte të API-së.
- **QR-të e dhuratave (16.11):** dhurata, promocioni dhe oferta aktivizohen te klienti, skanohen nga stafi (kamerë dhe kod i shtypur), shfrytëzohen një herë, telefoni i klientit kalon live në "U shfrytëzua!", dhe admini i sheh te detajet e klientit dhe te promocionet.
- **Arka (16.11):** 14 kontrolle API (shitje pa klient, para të pamjaftueshme, shportë bosh, 3 zbritje njëherësh, pikët mbi shumën e paguar, kod i përdorur, fiskal, anulim, të drejtat) dhe 19 kontrolle në shfletues në PC (1366 px) dhe telefon: produktet, kategoritë, skaneri USB (produkt me sasi, klient, dhuratë), kusuri, F9, kuponi, shënimi fiskal, shitje me kartë, lista e ditës, anulimi, paneli.
- **Rolet dhe stoku (16.11):** 28 kontrolle API (pronar/menaxher/staf, ndalimet në server, fshirja, stoku, recetat, zbritja nga shitja dhe rikthimi nga anulimi) dhe 12 kontrolle në shfletues (pronari shton menaxher, menaxheri shton staf dhe artikuj, receta, stafi sheh vetëm Arkën dhe shet, stoku zbret).
- **Propozimi SQL** u testua në PostgreSQL 16 lokal: regjistrimi, hyrja, PIN-i i gabuar, blerja, produkti falas, oferta, validimi, ndalimi i stafit te funksionet e adminit, dhe ndalimi i qasjes direkte në tabela.
