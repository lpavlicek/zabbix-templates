# PostgreSQL pgBackRest by Zabbix agent

Zabbix 7.4 šablona pro monitoring záloh pgBackRestu (PostgreSQL 18) přes Zabbix agenta,
bez nutnosti instalovat další software (exporter apod.). Zdroje dat:

- **`pgbackrest info --output=json --stanza=<stanza>`** – spouští Zabbix agent
  (UserParameter) pod uživatelem `postgres` přes `sudo` a malý wrapper, master item vrací syrový JSON, ze kterého se přes dependent items
  a LLD odvozují všechny stavové/velikostní/časové hodnoty.
- **`pgbackrest check`** – spouští se **mimo Zabbix**, jednou denně přes systemd timer
  pod uživatelem `postgres`. Výstup se ukládá do log souboru, který Zabbix agent jen
  čte (`vfs.file.time`, `vfs.file.regmatch`, `vfs.file.regexp`).

Vendor: `lpavlicek`, verze šablony: `7.4-3`.

## Požadavky

- Zabbix 7.4 (server + agent, TimescaleDB jako backend)
- pgBackRest 2.57/2.58, PostgreSQL 18
- Ubuntu 24.04 / Debian 12+ / Debian 13
- `sudo`
- Uživatel `zabbix` smí přes `sudo` spustit jako `postgres` jen wrapper
  `/usr/local/bin/zabbix-pgbackrest-info` (viz níže). K samotné konfiguraci,
  přihlašovacím údajům k S3 ani k SSH klíčům SFTP repozitářů přístup nemá.
- Uživatel `zabbix` musí umět přečíst log soubor z `pgbackrest check` – řešeno
  členstvím v systémové skupině `postgres` (viz níže)

## Instalace

Soubory pro server jsou v adresáři `files/` se stejnou strukturou cest jako
na cílovém systému:

| Soubor v repu | Cíl na serveru | Vlastník / práva |
|---|---|---|
| `files/usr/local/bin/zabbix-pgbackrest-info` | `/usr/local/bin/zabbix-pgbackrest-info` | `root:root` `0755` |
| `files/etc/sudoers.d/zabbix-pgbackrest` | `/etc/sudoers.d/zabbix-pgbackrest` | `root:root` `0440` |
| `files/etc/zabbix/zabbix_agentd.d/pgbackrest.conf` | `/etc/zabbix/zabbix_agentd.d/pgbackrest.conf` (agent 2: `zabbix_agent2.d/`) | `root:root` `0644` |

```bash
install -o root -g root -m 0755 files/usr/local/bin/zabbix-pgbackrest-info /usr/local/bin/
install -o root -g root -m 0440 files/etc/sudoers.d/zabbix-pgbackrest /etc/sudoers.d/
visudo -cf /etc/sudoers.d/zabbix-pgbackrest
install -o root -g root -m 0644 files/etc/zabbix/zabbix_agentd.d/pgbackrest.conf /etc/zabbix/zabbix_agentd.d/
systemctl restart zabbix-agent
sudo -u zabbix sudo -n -H -u postgres /usr/local/bin/zabbix-pgbackrest-info <stanza>
```

Soubory v `files/` musí mít konce řádků LF (zajišťuje `.gitattributes`). Skript
s CRLF na Linuxu nefunguje (`/bin/sh^M: bad interpreter`) a sudoers soubor
s CRLF `visudo` odmítne. Pozor při kopírování z Windows mimo git (např. WinSCP
v textovém režimu).

Obsah souborů a důvody jednotlivých voleb popisují následující kroky.


### 1. Wrapper pro `pgbackrest info`

`/usr/local/bin/zabbix-pgbackrest-info` (vlastník `root:root`, práva `0755`):

```sh
#!/bin/sh
# Run "pgbackrest info" for the Zabbix agent. Executed as user postgres via sudo.
# The stanza name comes from the Zabbix item key, so it is strictly validated:
# without this, an arbitrary string from the item key would be passed to
# pgbackrest running as postgres (e.g. extra options such as --config or --cmd-ssh).
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: $0 <stanza>" >&2
    exit 2
fi
case "$1" in
    ''|-*|*[!A-Za-z0-9_.-]*)
        echo "invalid stanza name" >&2
        exit 2
        ;;
esac
cd /
exec /usr/bin/pgbackrest info --output=json --stanza="$1"
```

Wrapper je nutný: pravidlo v sudoers přímo na `/usr/bin/pgbackrest info ... --stanza=*`
by nebylo bezpečné, protože `*` v sudoers odpovídá i mezerám, takže by šlo
připojit libovolné další přepínače pgbackrestu.

### 2. Sudoers

`/etc/sudoers.d/zabbix-pgbackrest` (práva `0440`, vždy upravovat přes
`visudo -f /etc/sudoers.d/zabbix-pgbackrest`):

```
zabbix ALL=(postgres) NOPASSWD: /usr/local/bin/zabbix-pgbackrest-info
```

Ověření (musí vrátit JSON, ne výzvu k heslu ani chybu):

```bash
sudo -u zabbix sudo -n -H -u postgres /usr/local/bin/zabbix-pgbackrest-info <stanza>
```

### 3. UserParameter na Zabbix agentovi

Na každém monitorovaném hostu přidat do konfigurace Zabbix agenta (např.
`/etc/zabbix/zabbix_agentd.d/pgbackrest.conf`):

```
UserParameter=pgbackrest.info[*],sudo -n -H -u postgres /usr/local/bin/zabbix-pgbackrest-info "$1"
```

a restartovat agenta (`systemctl restart zabbix-agent`).

- `-n` – nikdy se neptat na heslo (při chybě v sudoers item rovnou selže,
  místo aby visel do timeoutu),
- `-H` – `HOME` uživatele `postgres`, aby pgbackrest našel
  `~postgres/.ssh/known_hosts` u SFTP repozitářů (pokud není nastaveno
  `repoN-sftp-known-host`).

Klíč UserParametru zůstává `pgbackrest.info[*]`, šablona se proto nemění.

**Nevýhody / omezení:**
- Každé volání (každých 15 min na stanzu) zapíše sudo záznam do
  `/var/log/auth.log` / journalu. Lze potlačit, např.
  `Defaults!/usr/local/bin/zabbix-pgbackrest-info !log_allowed` (sudo 1.9.10+;
  neověřeno na všech distribucích), za cenu horší auditní stopy.
- Kdo může měnit klíč itemu v Zabbixu, může nechat spustit `pgbackrest info`
  pro libovolnou existující stanzu na hostu. Nic dalšího wrapper nepovolí.

### 4. Skupina `postgres` (jen kvůli logu z `pgbackrest check`)

```bash
usermod -aG postgres zabbix
```

Zabbix agent musí být po přidání do skupiny restartován (nová skupina se
promítne až po restartu procesu). Pro `pgbackrest info` už členství ve skupině
potřeba není, Zabbix agent jej čte jen kvůli `vfs.file.*` itemům nad
log souborem z `pgbackrest check`.

### 5. Systemd timer pro `pgbackrest check`

`pgbackrest check` se spouští jednou denně mimo Zabbix, výstup jde do
`/var/log/pgbackrest/<stanza>-check.log` (cesta je konfigurovatelná přes makro
`{$PGBACKREST.CHECK.LOG.DIR}`).

**`/etc/systemd/system/pgbackrest-check@.service`**

```ini
[Unit]
Description=pgBackRest check for stanza %i
Wants=network-online.target
After=network-online.target postgresql.service

[Service]
Type=oneshot
User=postgres
Group=postgres
UMask=0027
ExecStart=/bin/sh -c '/usr/bin/pgbackrest check --stanza=%i --log-level-console=detail > /var/log/pgbackrest/%i-check.log 2>&1'
```

**`/etc/systemd/system/pgbackrest-check@.timer`**

```ini
[Unit]
Description=Daily pgBackRest check for stanza %i

[Timer]
OnCalendar=*-*-* 04:00:00
RandomizedDelaySec=900
Persistent=true
Unit=pgbackrest-check@%i.service

[Install]
WantedBy=timers.target
```

Aktivace (za `<stanza>` dosadit skutečný název stanzy):

```bash
systemctl daemon-reload
systemctl enable --now pgbackrest-check@<stanza>.timer
```

Ověřit, že adresář `{$PGBACKREST.CHECK.LOG.DIR}` (výchozí `/var/log/pgbackrest`)
má group-execute pro skupinu `postgres` (např. `0750 postgres:postgres`), jinak
se k souboru zabbix nedostane, i kdyby soubor samotný čitelný byl.

### 6. Import šablony a nastavení makra

Naimportovat `PostgreSQL pgBackRest by Zabbix agent.yaml`, přiřadit šablonu hostu a povinně nastavit:

- `{$PGBACKREST.STANZA}` – název stanzy na daném hostu (bez tohoto makra
  zůstanou itemy "Not supported")

U hostů s odlišným zálohovacím plánem (např. denní `full` bez `incr/diff`)
přepsat na úrovni hostu makro `{$PGBACKREST.BACKUP.MAX.AGE:"full"}` na `26h`.

## Makra

| Makro | Výchozí hodnota | Význam |
|---|---|---|
| `{$PGBACKREST.STANZA}` | *(bez výchozí hodnoty)* | Název stanzy – **povinné nastavit per host** |
| `{$PGBACKREST.CHECK.LOG.DIR}` | `/var/log/pgbackrest` | Adresář s výstupem `pgbackrest-check@<stanza>.service` |
| `{$PGBACKREST.BACKUP.MAX.AGE:"full"}` | `8d` | Max. stáří poslední `full` zálohy |
| `{$PGBACKREST.BACKUP.MAX.AGE:"diff"}` | `26h` | Max. stáří poslední `diff` zálohy |
| `{$PGBACKREST.BACKUP.MAX.AGE:"incr"}` | `26h` | Max. stáří poslední `incr` zálohy |
| `{$PGBACKREST.CHECK.MAX.AGE}` | `32h` | Max. stáří check-logu (denní timer + rezerva) |

## Co šablona sleduje

**Stanza (bez LLD):**
- celkový stav stanzy (`status.code`/`message`) + value mapping s popisem kódů
- stáří a chybovost denního `pgbackrest check` logu (dle systemd timeru)

**LLD – repozitáře** (`{#REPO}`, libovolný počet, i s mezerami v číslování
jako repo1+repo3):
- stav daného repozitáře, min/max archivovaný WAL segment
- potvrzení z `pgbackrest check`, že se na dané repo skutečně podařilo
  zapsat/archivovat testovací WAL segment

**LLD – zálohy** (`{#REPO}` × `{#TYPE}`, jen reálně existující kombinace):
- čas poslední zálohy daného typu v daném repu (informativní), a odděleně
  čas poslední zálohy daného typu **nebo full** (trigger na stáří – full
  záloha zachraňuje limit i pro diff/incr)
- velikost skutečně zálohovaných dat (`info.delta`) a komprimovaná velikost
  na repu (`info.repository.delta`) – **ne** `info.size`/`info.repository.size`,
  což jsou celkové/kumulativní hodnoty stejné pro celý řetězec záloh
- počet záloh daného typu v repu (informativní, bez triggeru – retence se
  liší server od serveru i repo od repo)

## Value mappingy

- **`pgBackRest: stanza status code`** – kódy 0/1/2/3/4/5/6/99 dle zdrojového
  kódu pgbackrestu (`src/command/info/info.c`). Kódy 4 (mixed) a 5 (database
  mismatch) se objevují jen v agregovaném stavu celé stanzy, nikdy u
  jednotlivého repa.
- **`pgBackRest: boolean check result`** – 0/1 → No/Yes, použito u
  `pgbackrest: check log contains error`.

## Uzavírání problémů

Všechny triggery mají recovery mode *Expression* a ruční uzavření je vypnuté:
problém se zavře sám při nejbližším vyhodnocení s OK hodnotou, tj. u triggerů
z `pgbackrest info` typicky do 15 minut (interval master itemu). Triggery na
`pgbackrest check` se vyhodnocují jednou za hodinu a zavřou se až po dalším běhu
systemd timeru (denně), případně po ručním
`systemctl start pgbackrest-check@<stanza>.service`.

Pokud problém trvá, ačkoli ručně spuštěný `pgbackrest info` je v pořádku,
spusťte jej stejně jako agent (viz ověření v kroku 2), ne pod rootem.

## Známá omezení

- `pgbackrest check` běží mimo Zabbix (systemd timer) – šablona jen čte jeho
  log, nespouští ho sama (vyžadovalo by spuštění pod uživatelem `postgres`,
  což jde nad rámec pouhého členství ve skupině).
- WAL archivace se sleduje jen nepřímo přes `check` (jednou denně) a přes
  min/max archivovaný segment z `info` (informativně, bez triggeru na
  "lag") – přímý WAL lag oproti aktuálnímu stavu PostgreSQL se nesleduje.
- Zaplnění S3 repozitáře se nemonitoruje (řešeno mimo tuto šablonu).

## Changelog

### 7.4-3 (2026-10-13)
- `pgbackrest info` se nově spouští pod uživatelem `postgres` přes `sudo` a
  validující wrapper `/usr/local/bin/zabbix-pgbackrest-info`. Dřív běžel pod
  uživatelem `zabbix`, který neměl přístup k SSH klíči SFTP repozitáře: Zabbix
  hlásil `known hosts failure ... LIBSSH2_KNOWNHOST_CHECK_NOTFOUND` na repu,
  na kterém zálohy ve skutečnosti fungovaly, a problémy se nezavíraly.
  Klíč UserParametru se nemění, změna je jen na straně agenta (kroky 1–3
  instalace).
- Trigger na stav stanzy: název problému nyní obsahuje kód stavu přes value
  mapping (`{ITEM.LASTVALUE1}`) místo textu zprávy. Zpráva je samostatný
  dependent item, který se může zapsat v jiné dávce než kód; do názvu se tak
  dostával zastaralý text (např. `Stanza ris status is not OK (ok)`). Text
  zprávy je nyní v *operational data* (`opdata`), které frontend vyhodnocuje
  živě.

### 7.4-2 (2026-08-02)
- Oprava falešných poplachů na chybějící `diff`/`incr` zálohu ve dnech, kdy
  proběhla jen `full` záloha (např. neděle na některých serverech).
- Přidán nový item `pgbackrest.backup.covered.timestamp[{#REPO},{#TYPE}]`,
  který v rámci vlastního JS preprocessingu (nad stejným JSONem z
  `pgbackrest info`) vrátí čas poslední zálohy, která je buď daného typu,
  nebo `full` (full záloha pokrývá totéž, co by pokryla diff/incr). Trigger
  na stáří `diff`/`incr` zálohy nyní vychází z tohoto itemu místo z čistě
  typové položky – porovnává se proti stejnému limitu jako dřív
  (`{$PGBACKREST.BACKUP.MAX.AGE:"{#TYPE}"}`), jen zohledňuje i full zálohu.
  Původní `pgbackrest.backup.last.timestamp[{#REPO},{#TYPE}]` zůstává beze
  změny jako čistě informativní hodnota (skutečný čas poslední zálohy
  daného typu, bez "full" fallbacku) pro grafy/přehled.
- Pozn. k implementaci: první pokus odkazoval na sesterský item přes
  `pgbackrest.backup.last.timestamp[{#REPO},full]` (ruční dosazení literálu
  místo `{#TYPE}`) – Zabbix takový odkaz při importu odmítá ("Incorrect item
  key ... provided for trigger expression"), protože validuje klíč pozičně
  vůči šabloně item prototypu (buď stejný literál, nebo stejné LLD makro).
  Řešením je samostatný item, který si vše spočítá sám.

### 7.4-1 (2026-07-28)
- První verze šablony.
- Monitoring stavu stanzy a jednotlivých repozitářů (`pgbackrest info`).
- LLD pro repozitáře (libovolný počet, i s mezerami v číslování) a pro
  kombinace repo × typ zálohy (full/diff/incr) dle reálně existujících dat.
- Sledování stáří a chybovosti záloh, velikostí (skutečně zálohovaná data,
  ne celková velikost DB) a počtu záloh v retenci.
- Kontrola denního `pgbackrest check` (systemd timer mimo Zabbix) – stáří
  logu, chybové hlášky, potvrzení archivace WAL per repo.
- Value mappingy pro stavové kódy stanzy/repa a pro boolean check položky.
