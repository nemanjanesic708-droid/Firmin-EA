# MT5 Orchestrator (LAN) – od 0 do proizvoda

Ovo je **starter‑kit** da na kućnoj privatnoj mreži povežeš 3 VM‑a sa MT5 (svaka sa tvojim EA) na **jednu centralnu bazu + AI orkestrator** koji odlučuje da li se pozicija otvara ili preskače.

## Šta dobijaš
- **API (FastAPI)** – endpointi za `heartbeat`, `decision`, `execution`
- **Baza (PostgreSQL 16)** – logovi i istorija
- **Redis** – spremno za kasniji rate‑limit/keš (nije neophodno odmah)
- **Minimalni AI** – baseline pravila + (opciono) logistička regresija na istoriji
- **Primer EA (MQL5)** – `EA/OrchestratedEA.mq5` koji priča sa API‑jem

Sve je spakovano u **Docker Compose**, bez potrebe da sam kompajliraš Python okruženje.

---

## Preduslovi
- Jedan **server VM** (preporuka: Ubuntu 22.04/24.04) na LAN‑u
- Tri **Windows VM** sa **MetaTrader 5** (po jedan MT5 + tvoj EA)
- Sve mašine su na istoj kućnoj mreži (LAN). Preporuka: rezerviši **statiku** na ruteru, npr.:
  - Server: `192.168.0.50`
  - MT5 VM‑ovi: `192.168.0.101`, `192.168.0.102`, `192.168.0.103`

> Ako nemaš statiku, dovoljno je da znaš IP servera kad podigneš stack.

---

## 1) Instalacija Docker‑a na server VM (Ubuntu)

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu   $(. /etc/os-release && echo $VERSION_CODENAME) stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

Proveri: `docker version` i `docker compose version`.

---

## 2) Kopiraj ovaj folder na server i podesi .env

1. Prebaci ZIP na server i raspakuj:
   ```bash
   unzip mt5-orchestrator.zip -d ~/mt5-orchestrator
   cd ~/mt5-orchestrator
   ```
2. Otvori `.env` i po potrebi promeni parametre (IP ti nije potreban jer je LAN):
   - `BOT_1_ID`, `BOT_1_KEY`, `BOT_2_*`, `BOT_3_*` – **ključevi moraju** da se poklapaju sa onim što staviš u EA inputs.
   - `SPREAD_LIMIT` – npr. 20 (tačka = point; ~2.0 pips na 5‑digit EURUSD)
   - `USE_ML=false` za početak.

---

## 3) Podigni stack

```bash
docker compose up -d --build
```

Proveri:
- API: `curl http://127.0.0.1:8000/health` → `{ "ok": true, ... }`
- Ako si na drugom računaru u LAN‑u: `http://192.168.0.50:8000/docs` (promeni IP za tvoj server)

> Ako koristiš UFW firewall: `sudo ufw allow from 192.168.0.0/24 to any port 8000 proto tcp`

---

## 4) Podesi MT5 na svakoj Windows VM

U **MT5 → Tools → Options → Expert Advisors**:
- čekiraj **Allow WebRequest for listed URL** i dodaj: `http://192.168.0.50:8000` (promeni IP za tvoj server).

Zatim:
1. U MT5 otvori **MQL5 Editor** (MetaEditor), **File → Open Data Folder** → uđi u `MQL5/Experts` i kopiraj `EA/OrchestratedEA.mq5`.
2. Otvori fajl u MetaEditor‑u i **Compile** (F7). Bez grešaka.
3. U MT5 povuci EA na graf za `EURUSD`. U **Inputs** podesi:
   - `InpApiBase = http://192.168.0.50:8000`
   - `InpApiKey` – npr. `KEY1` (druga VM: `KEY2`, treća: `KEY3`)
   - `InpBotId` – `bot-1` (druga: `bot-2`, treća: `bot-3`)
4. Uključi **Algo Trading** (zelena ikonica).

Logovi u **Experts** prozoru moraju da pokažu slanje heartbeat‑a i dobijanje odluke.

---

## 5) Kako radi odluka (baseline)

- Orkestrator uzima **najnoviji heartbeat** bota, čita `spread` i grubu sesiju (LDN/NY/ASIA po UTC satu).
- Ako je `spread > SPREAD_LIMIT` → **SKIP**.
- Inače **OPEN** sa zadatim `lot/SL/TP`, strana BUY/SELL naivno po sesiji (samo za demo).

Cilj je da sve **živi** i loguje u bazu. AI uključuješ tek kad prikupiš dovoljno istorije.

---

## 6) Zatvaranje i PnL

Ovaj demo EA po otvaranju odmah šalje `status=OPENED` na `/executions`. Kad poziciju zatvoriš ručno ili drugim EA‑om, možeš poslati `status=CLOSED` sa `pnl` (pozitivan za dobitak, negativan za gubitak). U praksi bi EA trebalo da hook‑uje OnTradeTransaction i javi zatvaranje automatski – to ostaje kao sledeći korak.

---

## 7) Treniranje AI (posle par dana prikupljanja)

1. Prikupi bar **50 zatvorenih trejdova** sa popunjenim `pnl`.
2. Pozovi treniranje:
   ```bash
   curl -X POST "http://192.168.0.50:8000/admin/train?key=changeme-admin"
   ```
3. Ako je uspešno, `api/models/model.pkl` će postojati.
4. U `.env` promeni `USE_ML=true` i uradi:
   ```bash
   docker compose restart api
   ```
5. Od tog momenta odluke dolaze iz modela (logistička regresija) sa pragom od 0.58.

> Ovo je **prosta** AI šema da kreneš. Kasnije možeš preći na XGBoost i bogatije feature‑e.

---

## 8) A/B test (osnove)

- Trenutno je `experiment_group` u baseline‑u **"A"**, a u ML režimu **"B"**.
- Sve odluke i rezultati se loguju u `decisions` i `executions` – lako porediš performanse po grupi.

---

## 9) Backup i auto‑start

- Docker servis podiže kontejnere na boot (zbog `restart: unless-stopped`).
- Backup: sačuvaj folder `db_data` (volumen Postgres‑a) i `api/models`.

---

## 10) Sledeći koraci / ideje

- Dodaj **OnTradeTransaction** u EA da automatski šalje `CLOSED` sa PnL‑om.
- Enrichuj `features`: ATR/RSI/BB, volatilnost, tick volumen, sesija, news flag, slippage.
- Dodaj **guardrails** u API (max otovrenih pozicija, max dnevni loss, zabrana par minuta pre/posle vesti).
- Dodaj **Grafana** za vizualizaciju metrika (može se naknadno dodati u docker‑compose).

Srećno! Ako zapne, proveravaj redosled: **API zdrav → MT5 WebRequest dozvoljen → ključevi se poklapaju → heartbeat stiže → decision se vraća → execution se loguje.**
