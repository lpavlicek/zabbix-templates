# Zabbix Template: TLS/SSL Monitoring pomocí sslscan

Šablona pro Zabbix 7.4 poskytující kompletní monitoring SSL/TLS konfigurací pomocí nástroje `sslscan`.

## 📋 Obsah

- [Funkce](#-funkce)
- [Požadavky](#-požadavky)
- [Instalace](#-instalace)
- [Konfigurace](#-konfigurace)
- [Monitorované metriky](#-monitorované-metriky)
- [Triggery a upozornění](#-triggery-a-upozornění)
- [Příklady použití](#-příklady-použití)
- [Řešení problémů](#-řešení-problémů)
- [Autor a licence](#-autor-a-licence)

## 🎯 Funkce

### Automatické objevování koncových bodů
- **Low-Level Discovery** pro automatické vytvoření monitoringu pro každý definovaný cíl
- Podpora libovolného počtu SSL/TLS endpointů
- Dynamická konfigurace pomocí maker

### Komplexní kontroly SSL/TLS
- ✅ Detekce zastaralých protokolů (TLS 1.0, TLS 1.1)
- ✅ Kontrola verifikace certifikátů (expirace, platnost, self-signed)
- ✅ Validace kryptografických klíčů (typ, délka)
- ✅ Kontrola podpory moderních verzí (TLS 1.2, TLS 1.3)
- ✅ Detekce chyb při skenování (DNS, timeout, handshake)

### Podpora různých protokolů
- HTTPS (port 443)
- SMTP s StartTLS (port 25, 587)
- PostgreSQL s StartTLS (port 5432)
- MySQL s StartTLS (port 3306)
- IMAP s StartTLS (port 143)
- POP3 s StartTLS (port 110)
- LDAP s StartTLS (port 389)
- FTP s StartTLS (port 21)
- IRC s StartTLS (port 6667)
- XMPP s StartTLS (port 5222)

### Agregované reporty
- **Celková závažnost** (Overall Severity) - jediná metrika pro všechny monitorované endpointy
- **Závažnost na cíl** (Target Severity) - agregovaná metrika pro každý endpoint
- Ideální pro dashboardy a executive reporting

## 📦 Požadavky

### Software
- **Zabbix Server/Proxy**: verze 7.4 nebo novější
- **sslscan**: verze 2.x

### Síťové požadavky
- Zabbix server/proxy musí mít síťový přístup k monitorovaným SSL/TLS endpointům
- Odchozí spojení na specifikované porty (443, 25, 5432, atd.)

## 🚀 Instalace

### 1. Instalace sslscan
```bash
# Debian/Ubuntu
sudo apt-get install sslscan

# RHEL/CentOS/Rocky Linux
sudo yum install sslscan

# Ověření
sslscan --version
```

### 2. Instalace external scriptu

Zkopírujte soubor `sslscan_check.sh` do `/usr/lib/zabbix/externalscripts/sslscan_check.sh`:

Nastavte oprávnění:
```bash
sudo chmod +x /usr/lib/zabbix/externalscripts/sslscan_check.sh
```

Otestujte script:
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/sslscan_check.sh www.google.com:443
```

### 3. Import šablony do Zabbixu

1. Přihlaste se do Zabbix webového rozhraní
2. Přejděte do **Data collection → Templates**
3. Klikněte na **Import**
4. Vyberte soubor `TLS sslscan Monitoring.yaml`
5. Klikněte na **Import**

## ⚙️ Konfigurace

### 1. Přiřazení šablony k hostu

1. Přejděte na **Data collection → Hosts**
2. Vyberte host (nebo vytvořte nový host specifický pro SSL monitoring)
3. V záložce **Templates** přidejte šablonu **TLS sslscan Monitoring**
4. Uložte změny

### 2. Konfigurace maker

V záložce **Macros** na úrovni hostu nastavte:

#### Povinná makra

**`{$SSLSCAN.TARGETS}`**
```
www.example.cz:443,api.example.cz:443,mail.example.cz:25
```
- Čárkami oddělený seznam cílů ve formátu `hostname:port`
- Port je od verze 7.4-7 volitelný – pokud ho neuvedete (jen `hostname`), použije se automaticky **port 443**
- Každý cíl vytvoří samostatnou sadu monitorovacích položek

#### Volitelná makra

**`{$SSLSCAN.STARTTLS}`** (výchozí: prázdné)
```
,,--starttls-smtp
```
- Čárkami oddělený seznam StartTLS parametrů odpovídajících cílům
- Prázdná hodnota = standardní HTTPS
- Příklad: pro 3 cíle (HTTPS, HTTPS, SMTP) → `,,--starttls-smtp`

Podporované StartTLS parametry:
- `--starttls-ftp` - FTP (port 21)
- `--starttls-imap` - IMAP (port 143)
- `--starttls-irc` - IRC (port 6667)
- `--starttls-ldap` - LDAP (port 389)
- `--starttls-mysql` - MySQL (port 3306)
- `--starttls-pop3` - POP3 (port 110)
- `--starttls-psql` - PostgreSQL (port 5432)
- `--starttls-smtp` - SMTP (port 25, 587)
- `--starttls-xmpp` - XMPP (port 5222)

**`{$SSLSCAN.CERT.EXPIRATION.WARN}`** (výchozí: 7)
```
30
```
- Počet dní před expirací certifikátu pro spuštění varování
- Doporučené hodnoty:
  - `30` - kritické produkční služby
  - `14` - standardní služby
  - `7` - nekritické služby
  - `3` - testovací prostředí

### 3. Příklady konfigurací

#### Jednoduchá HTTPS monitorování
```yaml
{$SSLSCAN.TARGETS}: www.example.cz:443,api.example.cz:443
{$SSLSCAN.STARTTLS}: 
{$SSLSCAN.CERT.EXPIRATION.WARN}: 14
```

#### Smíšená konfigurace (HTTPS + databáze + email)
```yaml
{$SSLSCAN.TARGETS}: web.example.cz:443,db.example.cz:5432,smtp.example.cz:25
{$SSLSCAN.STARTTLS}: ,--starttls-psql,--starttls-smtp
{$SSLSCAN.CERT.EXPIRATION.WARN}: 30
```

#### Komplexní infrastruktura
```yaml
{$SSLSCAN.TARGETS}: www.example.cz:443,api.example.cz:443,db1.example.cz:5432,db2.example.cz:5432,mail.example.cz:25,mail.example.cz:587,ldap.example.cz:636
{$SSLSCAN.STARTTLS}: ,,,--starttls-psql,--starttls-psql,--starttls-smtp,--starttls-smtp,
{$SSLSCAN.CERT.EXPIRATION.WARN}: 30
```

## 📊 Monitorované metriky

### Pro každý discovered endpoint

| Položka | Typ | Popis |
|---------|-----|-------|
| **TLS sslscan Check** | External | Master položka - spouští sslscan a vrací XML výstup |
| **Certificate Days Until Expiration** | Dependent | Počet dní do expirace certifikátu |
| **Certificate Expiration Date** | Dependent | Datum expirace certifikátu (textový formát) |
| **Certificate Expired** | Dependent | Binární: certifikát expiroval (1/0) |
| **Certificate Not Yet Valid** | Dependent | Binární: certifikát ještě není platný (1/0) |
| **Certificate Self-Signed** | Dependent | Binární: self-signed certifikát (1/0) |
| **Certificate Key Type** | Dependent | Typ klíče (RSA, EC, DSA) |
| **Certificate Key Bits** | Dependent | Délka klíče v bitech |
| **Certificate EC Curve** | Dependent | Název EC křivky (pro EC certifikáty) |
| **TLS 1.0 Enabled** | Dependent | Binární: TLS 1.0 povolen (1/0) |
| **TLS 1.1 Enabled** | Dependent | Binární: TLS 1.1 povolen (1/0) |
| **TLS 1.2 Enabled** | Dependent | Binární: TLS 1.2 povolen (1/0) |
| **TLS 1.3 Enabled** | Dependent | Binární: TLS 1.3 povolen (1/0) |
| **SSL Scan Error** | Dependent | Chybová zpráva ze skenování (pokud nějaká) |
| **Target Severity** | Calculated | Agregovaná závažnost pro daný cíl (0-4) |

### Globální metriky

| Položka | Typ | Popis |
|---------|-----|-------|
| **Overall Severity** | Calculated | Maximální závažnost ze všech monitorovaných cílů |
| **Hostnames List** | Calculated | Seznam cílů z makra {$SSLSCAN.TARGETS} |

## 🚨 Triggery a upozornění

### Kritické (High Priority)

| Trigger | Podmínka | Popis |
|---------|----------|-------|
| **Certificate expired** | `expired=1` | Certifikát expiroval |
| **Certificate not yet valid** | `not-yet-valid=1` | Certifikát ještě není platný |

### Varování (Warning/Average)

| Trigger | Podmínka | Popis |
|---------|----------|-------|
| **TLS 1.0 enabled** | `tls10=1` | Zastaralý protokol TLS 1.0 je povolen |
| **TLS 1.1 enabled** | `tls11=1` | Zastaralý protokol TLS 1.1 je povolen |
| **Self-signed certificate** | `self-signed=1` | Detekován self-signed certifikát |
| **Certificate expiring soon** | `days < {$...WARN}` | Certifikát brzy expiruje |
| **SSL Scan error** | `length(error)>0` | Chyba při skenování (DNS, timeout, atd.) |

### Informační (Info)

| Trigger | Podmínka | Popis |
|---------|----------|-------|
| **Weak cryptographic key** | `RSA<3072 OR !RSA&!EC` | Slabý kryptografický klíč |

### Závislosti triggerů

- Trigger "Certificate expiring soon" je závislý na "Certificate expired"
- Ostatní triggery jsou závislé na "SSL Scan error"

## 🔧 Řešení problémů

### Problém: Items nejsou vytvořeny po přiřazení šablony

**Řešení:**
1. Zkontrolujte, že makro `{$SSLSCAN.TARGETS}` je nastaveno
2. Počkejte 1 hodinu (interval discovery) nebo spusťte discovery ručně
3. Zkontrolujte log Zabbix serveru: `/var/log/zabbix/zabbix_server.log`

### Problém: "No such file or directory" v chybových zprávách

**Řešení:**
```bash
# Ověřte, že script existuje
ls -la /usr/lib/zabbix/externalscripts/sslscan_check.sh

# Ověřte oprávnění
sudo chmod +x /usr/lib/zabbix/externalscripts/sslscan_check.sh

# Ověřte, že sslscan je nainstalován
which sslscan
```

### Problém: "Connection timeout" chyby

**Řešení:**
1. Ověřte síťovou konektivitu z Zabbix serveru/proxy:
```bash
   telnet hostname port
   openssl s_client -connect hostname:port
```
2. Zkontrolujte firewall pravidla
3. Zvyšte timeout v scriptu (parametr `--timeout`)

### Problém: Items mají hodnotu "Not supported"

**Řešení:**
1. Zkontrolujte, že external check vrací validní XML
2. Spusťte script ručně:
```bash
   sudo -u zabbix /usr/lib/zabbix/externalscripts/sslscan_check.sh hostname:port
```
3. Ověřte XML strukturu výstupu

> **Poznámka:** Chyby ve formátu makra `{$SSLSCAN.TARGETS}` (např. neplatný znak v hostname) se od verze 7.4-7 nezobrazují jako "Not supported", ale jako standardní hodnota položky **TLS sslscan Error for {#TARGET}** a odpovídající trigger "SSL Scan error". Pokud tedy vidíte "Not supported", jde o jiný problém (chybějící/nespustitelný script, chybějící sslscan apod.), ne o špatně zadaný cíl. Cíl bez portu (např. jen `www.example.cz`) navíc od verze 7.4-7 není chyba – automaticky se použije port 443.

### Problém: "Could not resolve hostname"

**Řešení:**
1. Ověřte DNS konfiguraci na Zabbix serveru/proxy:
```bash
   nslookup hostname
   dig hostname
```
2. Zkontrolujte `/etc/resolv.conf`
3. Použijte IP adresu místo hostname (dočasné řešení)

## 📁 Struktura souborů
```
.
├── TLS sslscan Monitoring.yaml    # Zabbix šablona
├── sslscan_check.sh               # External script
└── README.md                      # Tato dokumentace
```

## 📝 Changelog

### Verze 7.4-7 (2026-07-21)

**Změny z 21. 7. 2026:**
- 🐛 Oprava chování skriptu při chybě validace vstupu (např. neplatný znak v cíli): dříve skript psal chybu na stderr a končil nenulovým exit kódem, což způsobilo, že master položka přešla do stavu "Not supported" a chybová zpráva se k triggeru vůbec nedostala (trigger zůstal na staré, zavádějící hodnotě). Nyní skript i v těchto případech vrací validní XML s `<error>` na stdout a exit 0, takže zpráva správně doteče přes položku "SSL Scan Error" až k triggeru
- ✨ Cíl v makru `{$SSLSCAN.TARGETS}` už nemusí obsahovat port – pokud chybí (např. jen `www.example.cz`), skript automaticky použije port 443
- 🏷️ Prodloužen timeout pro odpověď ze skriptu ze 6s na 10s

### Verze 7.4-6 (2026-07-20)

**Změny z 20. 7. 2026:**
- 🔒 Zpevnění external scriptu `sslscan_check.sh` – validace formátu cíle (`host:port`) a allow-list pro StartTLS parametr, ochrana proti argument injection do sslscanu
- 🐛 Oprava chyby v JavaScript preprocessingu položky "Certificate Days Until Expiration" (špatně pojmenovaná proměnná způsobovala, že se sentinel pro chybějící datum nikdy nevrátil)
- 🌐 Překlad zbývajících českých komentářů v JavaScript preprocessingu do angličtiny
- 🔗 Doplněny závislosti (dependencies) triggerů "TLS 1.0/1.1 enabled", "Self-signed certificate" a "Weak cryptographic key" na trigger "SSL Scan error", aby se při selhání skenu nezobrazovaly zavádějící souběžné alerty
- 🏷️ Trigger "Certificate expiring soon" nyní v názvu zobrazuje neměnné datum expirace certifikátu; počet zbývajících dnů je nově v poli Operational data
- ✏️ Opravy drobných překlepů v popisech položek a nesoulad příkazu `--connect-timeout` vs. dříve chybně uvedený `--connection-timeout`

### Verze 7.4-1 (2025-11-09)
- ✨ Iniciální release
- ✅ Podpora Zabbix 7.4
- ✅ Low-Level Discovery pro SSL/TLS endpointy
- ✅ Kontrola TLS verzí (1.0, 1.1, 1.2, 1.3)
- ✅ Validace certifikátů (expirace, self-signed, platnost)
- ✅ Kontrola kryptografických klíčů (typ, délka)
- ✅ Podpora StartTLS protokolů
- ✅ Agregované reporty (Overall Severity, Target Severity)

