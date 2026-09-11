# CMS pripojeni

Šablona pro Zabbix 7.4 pro monitorování připojení do sítě CMS (Centrální místo služeb, součást komunikační infrastruktury veřejné správy — viz [archi.gov.cz](https://archi.gov.cz/nap:komunikacni_infrastruktura_verejne_spravy)).

## Co šablona sleduje

- **Dostupnost síťových tunelů a klíčových IP adres** v cestě do CMS (fping, měření RTT):
  - tunel VSE (fg-cluster) → CESNET
  - tunel CESNET → datové centrum se základními registry (DIA/NAKIT)
  - virtuální firewall (VFW) subjektu v CMS, datové centrum **DC1**
  - virtuální firewall (VFW) subjektu v CMS, datové centrum **DC2**
- **Funkčnost lokálního DNS resolveru** pro doménu `cms2.cz`:
  - zda resolver vůbec odpovídá (SOA dotaz na `vse.cz`)
  - zda `www.cms2.cz` resolvuje na očekávanou IP adresu

Dostupnost `www.cms2.cz` přes proxy server na portu 8888 **tato šablona netestuje** — je pokrytá samostatnou šablonou **"Http proxy proxy.vse.cz"** (položky `Proxy: port 8888` a `Proxy: port 8888, rule allow www.cms2.cz`), která se přiřazuje na hostu `proxy.vse.cz`.

## Požadavky

- **fping** nainstalovaný na monitorovaném hostu.
- **UserParameter** pro fping v `/etc/zabbix/zabbix_agent2.d/` (nebo `/etc/zabbix/zabbix_agentd.d/` u klasického agenta):

  ```
  # fping host
  UserParameter=fping.host[*],fping --elapsed --timeout 150 --retry 2 $1 2>/dev/null
  ```

  Po přidání souboru restartovat agenta (`systemctl restart zabbix-agent2`).
- Zabbix agent na hostu (položky `fping.host[*]` i DNS položky běží přes agenta, ne agentless).
- Lokálně funkční DNS resolver na monitorovaném hostu (položky `net.dns[127.0.0.1,...]` a `net.dns.record[127.0.0.1,...]` se ptají na `127.0.0.1`, tedy na resolver nastavený přímo na daném serveru).

## Položky

| Název | Klíč | Jednotka | Poznámka |
|---|---|---|---|
| CMS: fping - tunnel from vse to cesnet availability | `fping.host[10.0.172.45]` | ms | RTT tunelu VSE↔CESNET, IP adresa na straně VSE. |
| CMS: fping - tunnel from cesnet to dia/nakit availability | `fping.host[10.240.245.129]` | ms | RTT tunelu CESNET↔CMS (10.240.245.128/30), IP na straně datového centra. Existuje i druhý tunel 10.240.117.128/30, ten šablona netestuje. |
| CMS: fping - firewall availability in DC1 | `fping.host[10.250.143.182]` | ms | RTT na virtuální firewall (VFW) subjektu v CMS, DC1. |
| CMS: fping - firewall availability in DC2 | `fping.host[10.250.207.182]` | ms | RTT na virtuální firewall (VFW) subjektu v CMS, DC2. |
| CMS: dns resolver - response for vse.cz SOA | `net.dns[127.0.0.1,vse.cz]` | — | Ověřuje, že lokální resolver vůbec odpovídá (SOA dotaz na `vse.cz` přes UDP). |
| CMS: dns resolver - record A for www.cms2.cz | `net.dns.record[127.0.0.1,www.cms2.cz,A]` | — | A záznam vrácený lokálním resolverem pro `www.cms2.cz`, porovnává se s makrem `{$CMS_WWW_IP}`. |

Všechny `fping.host[*]` položky mají preprocessing REGEX, který z výstupu fping vytáhne naměřený čas (`... is alive (X ms)` → `X`). Pokud host neodpovídá (`... is unreachable`), regulární výraz nesedí a chybový handler nastaví hodnotu `-1` — na tom jsou postavené triggery na nedostupnost.

## Triggery

| Trigger | Závažnost | Podmínka |
|---|---|---|
| CMS: tunnel from vse to cesnet is unreachable | Average | RTT `< 0` (fping nevrátil odpověď). |
| CMS: tunnel from cesnet to cms is unreachable | Average | RTT `< 0`. |
| CMS: virtual firewall in DC1 high latency | Warning | RTT `> 100 ms`. |
| CMS: virtual firewall in DC1 is unreachable | Average | RTT `< 0`. |
| CMS: virtual firewall in DC2 high latency | Warning | RTT `> 100 ms`. |
| CMS: virtual firewall in DC2 is unreachable | Average | RTT `< 0`. |
| CMS: broken DNS resolver on {HOST.DNS} | Average | SOA dotaz na `vse.cz` selhal. |
| CMS: resolver does not return IP address "{$CMS_WWW_IP}" for www.cms2.cz | Average | A záznam je prázdný nebo neodpovídá `{$CMS_WWW_IP}`. Závisí na triggeru "broken DNS resolver", takže se nezdvojuje, pokud je resolver rovnou úplně mimo provoz. |

Žádné "no data" triggery.

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$CMS_WWW_IP}` | `10.254.8.26` | Očekávaná IP adresa pro `www.cms2.cz`. |

## Instalace (Debian 13)

1. Nainstalovat fping:
   ```
   apt install fping
   ```
2. Vytvořit soubor s UserParameter, např. `/etc/zabbix/zabbix_agent2.d/userparameter_fping.conf`:
   ```
   # fping host
   UserParameter=fping.host[*],fping --elapsed --timeout 150 --retry 2 $1 2>/dev/null
   ```
3. Restartovat agenta:
   ```
   systemctl restart zabbix-agent2
   ```
4. Ověřit ručně, že fping vrací očekávaný formát (na tom je založený REGEX preprocessing v šabloně):
   ```
   fping --elapsed --timeout 150 --retry 2 10.0.172.45
   # očekávaný výstup: "10.0.172.45 is alive (X.XX ms)"
   ```
5. V Zabbixu: **Data collection → Templates → Import**, nahrát soubor šablony. Skupina šablon `lpavlicek templates` se vytvoří automaticky, pokud ještě neexistuje.
6. Přiřadit šablonu na oba hosty (Debian 13), na kterých se má sledovat připojení do CMS.
7. Upravit makro `{$CMS_WWW_IP}` na úrovni hosta, pokud se na některém z obou serverů liší očekávaná IP adresa `www.cms2.cz`.
8. Ověřit, že položky `net.dns[127.0.0.1,...]` a `net.dns.record[127.0.0.1,...]` fungují — Zabbix agent musí mít povolený DNS dotaz vůči `127.0.0.1` (výchozí chování by mělo fungovat bez dalšího nastavení).

## Řešení problémů

- **Položky `fping.host[*]` jsou "Not supported"** — ověřit, že je nainstalovaný `fping` a že UserParameter je opravdu načtený (`zabbix_agent2 -T -c /etc/zabbix/zabbix_agent2.conf` nebo restart agenta po přidání souboru). Ověřit i práva — `fping` typicky potřebuje `CAP_NET_RAW` (balíčkem z Debianu je binárka obvykle nastavená s potřebnými capabilities/setuid, není nutný root).
- **Hodnota položky je pořád `-1`, i když je cíl dostupný** — spustit ručně příkaz z UserParameter na hostu a zkontrolovat, že výstup přesně odpovídá vzoru `... is alive (X ms)`, na který je navázaný REGEX preprocessing.
- **DNS položky nic nevrací / jsou "Not supported"** — ověřit, že server má funkční lokální resolver na `127.0.0.1` (např. `resolvectl status` nebo obsah `/etc/resolv.conf`), a že Zabbix agent běží pod uživatelem, který má k DNS dotazům přístup (běžně žádné zvláštní právo netřeba).
- **Trigger na `www.cms2.cz` se hlásí, i když web funguje** — zkontrolovat, jestli se nezměnila IP adresa `www.cms2.cz` a případně upravit makro `{$CMS_WWW_IP}` na aktuální hodnotu.

## Nasazení

Šablona se používá na dvou serverech s Debian 13.

## Changelog

### 7.4-1 (2026-08-17)
- První verze šablony umístěná do tohoto repozitáře.
- Doplněn blok `vendor` (autor, verze).
- Doplněny template-level tagy `class: network` a `target: cms` (konzistentně s ostatními šablonami v repozitáři).
- Opravena chyba v `error_handler_params` u položky `net.dns.record[...]` — v původním exportu byla hodnota omylem escapovaná na doslovný řetězec dvou apostrofů (`''`) místo prázdného řetězce.
- Sjednocen regulární výraz REGEX preprocessingu u fping položek (`^.+ is alive ...` u všech položek, dříve první položka měla `^.* is alive ...`).
- Odstraněno nepoužité makro `{$PROXY_HOST}` a nepoužitý valuemap `Tcp service status` — souvisely s kontrolou dostupnosti `www.cms2.cz` přes proxy, která je ale reálně pokrytá šablonou "Http proxy proxy.vse.cz", ne touto šablonou. Upraven i popis šablony, aby tuto kontrolu neslíboval.
