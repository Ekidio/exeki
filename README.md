# EXEKI

**Windows és DOS programok futtatása Macen, egyszerűen.** Húzd rá az `.exe` fájlt, és elindul.

Nincs terminál, nincs „bottle”-kezelés, nincs beállítás. Az EXEKI felismeri, milyen programot kapott, kiválasztja hozzá a megfelelő motort, és mindent magától letölt és beállít.

- **Windows programok** (32 és 64 bites `.exe`, `.msi`, `.bat`) a [Wine](https://www.winehq.org) motorral. Erre épül a CrossOver és a Whisky is.
- **DOS programok és régi játékok** (`.exe`, `.com`, pl. a DOS-os Doom) a [DOSBox Staging](https://www.dosbox-staging.org) motorral.
- **Automatikus frissítés:** az app naponta ellenőrzi, van-e új verzió, és egy kattintással frissít.
- Apple Silicon (M1–M4) és Intel Mac, macOS 14 (Sonoma) vagy újabb.
- Magyar felület, érthető hibaüzenetek.

## Telepítés

1. Töltsd le a legfrissebb **`EXEKI-x.y.dmg`** fájlt a [Releases](../../releases/latest) oldalról.
2. Nyisd meg, és húzd az **EXEKI** ikont az **Alkalmazások** mappába.
3. Indítsd el az Alkalmazások mappából.

### „Az Apple nem tudta ellenőrizni…” – ha a Mac nem engedi megnyitni

Az EXEKI ingyenes, nyílt forráskódú program, és nem fizetünk az Apple-nek a hitelesítésért. Ezért az **első indításnál** a macOS rákérdez. Ezt **csak egyszer** kell megcsinálni:

1. A figyelmeztetésben kattints a **Kész** gombra. *(Ne az „Áthelyezés a Kukába” gombra!)*
2. Nyisd meg: ** menü → Rendszerbeállítások → Adatvédelem és biztonság**.
3. Görgess le a **Biztonság** részhez. Ott ezt látod: *„Az EXEKI blokkolva lett…”*. Kattints a **Megnyitás mindenképp** gombra (angolul: *Open Anyway*).
4. Erősítsd meg a jelszavaddal vagy Touch ID-vel.

Ezután az app ugyanúgy indul, mint bármelyik másik. A későbbi automatikus frissítéseknél ezt már nem kell megismételni.

### Első indítás

Az app egyetlen képernyőn végigvezet mindenen:

- ha kell, telepíti az Apple **Rosetta** kiegészítőjét (egy jelszókérés),
- letölti a Windows-futtató motort (kb. 190 MB, egyszer),
- létrehozza a virtuális **C:** meghajtót.

Ez összesen néhány perc. A DOS-motort (kb. 45 MB) csak az első DOS program indításakor tölti le.

## Használat

- **Húzd rá** a programot az ablakra vagy a Dockban lévő ikonra, vagy kattints a mezőre, és válaszd ki. Hogy Windows vagy DOS program, azt az EXEKI magától eldönti.
- **Telepítők** (`setup.exe`, `.msi`): futtasd őket ugyanígy. A telepítés után a program magától megjelenik a **Programjaim** listában, a saját ikonjával. Onnan egy kattintással indítható.
- **Programjaim:** jobb kattintás egy programon: *Megjelenítés a Finderben* vagy *Elrejtés a listából*. Telepítés nélküli `.exe`-t vagy DOS játékot a **⋯ → Program hozzáadása a listához…** menüponttal tehetsz a listába.
- **Dupla kattintás az .exe fájlokra:** **⋯ → Legyen ez az .exe fájlok megnyitója**.
- **Ha rossz motor indulna:** **⋯ → Futtatás a DOS-motorral… / Futtatás a Windows-motorral…**
- **Ha valami elromlott:** **⋯ → Windows környezet visszaállítása…**. Ez tiszta lappal indul, a régi C: meghajtó a Kukába kerül.
- **Frissítés kézzel:** **EXEKI menü → Frissítések keresése…**

## Mi fog működni?

Jól működnek az egyszerű Windows programok (segédprogramok, fájlkezelők, pl. Total Commander, régebbi irodai programok) és a legtöbb DOS-os program és játék.

Nem vagy rosszul működnek:

- csalásvédelmet használó online játékok,
- kernel-illesztőprogramot igénylő szoftverek,
- Windows 3.1-es (16 bites) programok,
- ARM-os Windowsra készült programok (ezekből általában van x64-es változat).

Ha egy program nem indul, az app megpróbálja megmondani, miért: például hiányzó .NET vagy Visual C++ csomag.

## Hol vannak a fájlok?

| Mi | Hol |
|---|---|
| Az app | `/Applications/EXEKI.app` |
| Motorok (Wine, DOSBox) | `~/Library/Application Support/EXEKI/Wine` és `…/DOSBox` |
| A virtuális C: meghajtó | `~/Library/Application Support/EXEKI/Windows/drive_c` |

**Teljes eltávolítás:** húzd az appot a Kukába, és töröld a `~/Library/Application Support/EXEKI` mappát.

---

## Fejlesztőknek

```bash
./build.sh             # universal app → dist/EXEKI.app
./make-dmg.sh          # app + DMG telepítő → dist/EXEKI-<verzió>.dmg
./make-release.sh      # DMG + aláírt appcast.xml → dist/release-<verzió>/
./prepare-engines.sh   # a motorok csomagjai a saját tükörhöz → dist/engines/
```

Követelmények: Xcode (Swift 6), a DMG-hez Python 3.10+. A `dmgbuild` automatikusan települ egy helyi `.venv` környezetbe, a Sparkle pedig a `.vendor` mappába, ellenőrzőösszeggel ellenőrizve.

### Egyszeri beállítás

1. Hozz létre egy GitHub repót, és írd a nevét a **`release.conf`** fájlba: `GITHUB_REPO="felhasznalo/exeki"`.
2. **Frissítési kulcs:** a frissítéseket egy EdDSA-kulcs írja alá. A privát kulcs a Mac kulcskarikájában van („exe-futtato” fiók), a biztonsági mentése a `~/EXEKI-frissitesi-kulcs-MENTSD-EL.key` fájl. **Tedd biztonságos helyre** (pl. jelszókezelőbe vagy pendrive-ra). Ha elveszik, a meglévő felhasználók többé nem kapnak frissítést. Visszaállítás: `.vendor/Sparkle-*/bin/generate_keys --account exe-futtato -f <fájl>`. A publikus kulcs a `sparkle-public-key.txt` fájlban van, ez nyugodtan lehet a repóban.
3. **Motortükör:** futtasd a `./prepare-engines.sh` szkriptet, és töltsd fel a `dist/engines/` tartalmát egy **`engines`** címkéjű GitHub kiadásba. Ezt ne jelöld „latest”-nek. Az app először innen tölti le a motorokat, és csak utána az eredeti helyükről. A Whisky azért halt meg, mert a motor letöltési helye megszűnt; így ez nálunk nem fordulhat elő.

### Új verzió kiadása

1. Emeld a verziót az `Info.plist` fájlban (`CFBundleShortVersionString`, és eggyel a `CFBundleVersion`).
2. `./make-release.sh`
3. A szkript kiírja a teendőket: új GitHub kiadás `v<verzió>` címkével, feltöltöd a **DMG-t és az `appcast.xml`-t**, és ez legyen a „latest release”.

A felhasználók appja 24 órán belül felajánlja a frissítést. Ha egy új verzió újabb Wine- vagy DOSBox-verziót kér (`Sources/Engines.swift`), az app a frissítés után magától letölti az új motort. Ilyenkor a `prepare-engines.sh`-t is futtasd le újra, és töltsd fel az új csomagot az `engines` kiadásba.

### Tesztelés

```bash
# motor helyi fájlból (az ellenőrzőösszeget ilyenkor is ellenőrzi)
defaults write hu.ekidio.EXEKI WineArchiveURL file:///útvonal/wine-devel-11.17-osx64.tar.xz
defaults write hu.ekidio.EXEKI DOSBoxArchiveURL file:///útvonal/dosbox-staging-macOS-v0.83.0.dmg

# frissítés helyi appcastból
defaults write hu.ekidio.EXEKI UpdateFeedURL http://localhost:8765/appcast.xml

# beállítóképernyők előnézete
EXEKI_PREVIEW_STEP=move|rosetta|download|update|windows|failed "dist/EXEKI.app/Contents/MacOS/EXEKI"
```

**Fontos:** az app fájlneve maradjon ékezet nélküli, mert a Sparkle nem tudja újraindítani az olyan appot, amelynek az elérési útjában ékezet van.

## Licenc

Az **EXEKI** forráskódja a [GPL-3.0](LICENSE) licenc alatt érhető el.

Felhasznált szoftverek:

- **Wine:** [LGPL 2.1+](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html) licenc, forrás: [gitlab.winehq.org/wine/wine](https://gitlab.winehq.org/wine/wine). A macOS-es build: [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds).
- **DOSBox Staging:** [GPL 2.0+](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) licenc, forrás: [dosbox-staging](https://github.com/dosbox-staging/dosbox-staging).
- **Sparkle:** MIT licenc.

Részletek: `Resources/Licencek.txt`. A Microsoft és a Windows a Microsoft Corporation védjegyei. Az EXEKI nem áll kapcsolatban a Microsofttal, sem az Apple-lel.
