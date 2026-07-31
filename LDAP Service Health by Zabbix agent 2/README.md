# LDAP Service Health by Zabbix agent 2

Šablona pro Zabbix 7.4 pro monitorování zdraví služby OpenLDAP (`slapd`) přes lokálně nainstalovaného Zabbix agenta 2.

## Co šablona sleduje

- **Stav systemd jednotky** `slapd.service` (`ActiveState`) – detekce pádu nebo zastavení služby.
- **Dostupnost portu LDAPS** (`{$LDAP.PORT}`, výchozí 636) – lokální kontrola, zda je port v LISTEN stavu.
- **Chybové hlášky v logu slapd** – řádky se severitou `notice` a vyšší (notice, warning, err, crit, alert, emerg); řádky s `debug`/`info` se ignorují.
- **Využití paměti procesem slapd** (% reálné paměti) – informativní metrika bez triggeru.

## Určeno pro

Hosty s běžícím `slapd` a lokálně nainstalovaným Zabbix agentem 2 (např. `demo`, `ldaptest.vse.cz`, `ldap4.vse.cz`, `ldap5.vse.cz`).

Není určeno pro:
- primární LDAP server (dostupný jen vzdáleně, bez agenta),
- anycast VIP `ldap.vse.cz` (není samostatný fyzický host).

Pro tyto případy slouží šablony **LDAP Functional Bind Check** a **LDAP Statistics**.

## Požadavky

- Zabbix agent **2** – klíč `systemd.unit.info` není dostupný v klasickém Zabbix agentovi 1.
- Uživatel, pod kterým běží Zabbix agent, musí mít právo číst `/var/log/slapd.log`.
- Systemd jednotka služby musí být pojmenována `slapd.service` (Debian standard).

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$LDAP.LOG.PATH}` | `/var/log/slapd.log` | Cesta k logu slapd sledovanému na chybové hlášky. |
| `{$LDAP.PORT}` | `636` | TCP port LDAPS, kontrolovaný na lokální LISTEN stav. |

## Položky

| Název | Klíč | Typ hodnoty | Poznámka |
|---|---|---|---|
| slapd: systemd service state | `systemd.unit.info["slapd.service",ActiveState]` | Char | Aktuální stav systemd jednotky; heartbeat 1h. |
| slapd: LDAPS port availability | `net.tcp.listen[{$LDAP.PORT}]` | Unsigned (value map Up/Down) | Lokální kontrola LISTEN stavu, ne skutečná dostupnost zvenčí; heartbeat 1h. |
| slapd: memory usage, % | `proc.mem[slapd,,,,pmem]` | Float | % reálné paměti použité procesem slapd. |
| slapd: error messages in log (notice and above) | `log[{$LDAP.LOG.PATH},"^\S+ (notice\|warning\|err\|crit\|alert\|emerg) "]` | Log | Aktivní kontrola (Zabbix agent 2); do historie se ukládají jen řádky odpovídající regexu. |

## Triggery

| Název | Severity | Poznámka |
|---|---|---|
| slapd: Service is not running on {HOST.NAME} | High | Systemd jednotka není ve stavu `active`; operational data zobrazuje aktuální stav. |
| slapd: LDAPS port {$LDAP.PORT} is unavailable on {HOST.NAME} | High | Závisí na předchozím triggeru – nehlásí se duplicitně, pokud služba už neběží. |
| slapd: Error found in log on {HOST.NAME} | Warning | `OK event generation: None` + `Allow manual close`. Každý nový chybový řádek vytvoří novou problémovou událost (Problem event generation: Multiple); problém se v Zabbixu zavírá ručně. |

## Value mapping

`slapd port available`: `1` → `Up`, `0` → `Down` (použito u položky LDAPS port availability).

## Instalace

1. V Zabbixu: **Data collection → Templates → Import**, nahrát YAML soubor šablony.
2. Přiřadit šablonu na hosty `demo`, `ldaptest.vse.cz`, `ldap4.vse.cz`, `ldap5.vse.cz` (Data collection → Hosts).
3. Ověřit, že na hostu běží Zabbix agent **2** (ne klasický agent 1) – `zabbix_agent2 -V`.
4. Pokud se na konkrétním hostu liší cesta k logu nebo port LDAPS, upravit makra `{$LDAP.LOG.PATH}` / `{$LDAP.PORT}` na úrovni hosta.
5. Ověřit čitelnost logu pro uživatele, pod kterým běží agent: `sudo -u zabbix tail /var/log/slapd.log`.

## Řešení problémů

- **Položka `systemd.unit.info` je "Not supported"** – ověřit verzi agenta (`zabbix_agent2 -V`); klíč vyžaduje Zabbix agenta 2.
- **Položka `net.tcp.listen` vrací 0, i když slapd běží** – ověřit, na jaké adrese/portu slapd skutečně naslouchá (`ss -tlnp | grep slapd`). Kontrola pokrývá jak IPv4, tak IPv6 sokety, takže by měla fungovat bez ohledu na to, na jakém rozhraní slapd poslouchá.
- **Trigger na chybu v logu se sám nezavírá** – to je záměr (`recovery_mode: NONE` + `manual_close`); problém se po prošetření zavírá v Zabbixu ručně.

## Známá omezení

- Kontrola portu je pouze lokální (LISTEN stav) – neověřuje TLS handshake, platnost certifikátu ani skutečnou dostupnost zvenčí. Na to slouží šablony TLS sslscan a LDAP Functional Bind Check.
- Položka využití paměti nemá trigger, zatím jde čistě o informativní metriku.

## Changelog

### 7.4-1 (2026-07-31)
- První verze šablony.
- Kontrola stavu systemd jednotky `slapd.service` (`ActiveState`).
- Kontrola LISTEN stavu portu LDAPS (`net.tcp.listen`), s value mappingem Up/Down.
- Kontrola využití paměti procesem slapd (`proc.mem`, `pmem`).
- Detekce chybových hlášek v logu slapd (severity notice a vyšší), s ručním zavíráním problémů.
