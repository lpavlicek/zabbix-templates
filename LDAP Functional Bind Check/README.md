# LDAP Functional Bind Check

Šablona pro Zabbix 7.4 pro funkční test dostupnosti OpenLDAP (`slapd`) přes autentizovaný LDAPS bind a search. Implementováno jako external check (spouští se na Zabbix serveru/proxy, ne na monitorovaném hostu), takže funguje stejně na hostech s agentem i bez něj.

## Co šablona sleduje

- **Funkční bind + search test** – autentizovaný LDAPS bind účtem `{$LDAP.BIND.DN}` následovaný search dotazem na rootDSE (`(objectClass=*)`, base scope, prázdný base). Protože je anonymní bind na všech LDAP serverech zakázaný, jde o jediný způsob, jak ověřit, že skutečně funguje jak bind, tak search – ne jen že je otevřený TCP port.

## Proč external check, ne agent

- Funguje i na hostech bez Zabbix agenta (primární LDAP server, dostupný jen síťově).
- Stejná šablona pokrývá všech šest hostů (demo, primary, ldaptest.vse.cz, ldap4.vse.cz, ldap5.vse.cz, anycast VIP `ldap.vse.cz`).

## Požadavky

- Skript `ldap_bind_check.sh` nahraný do adresáře `ExternalScripts` Zabbix serveru/proxy (viz parametr `ExternalScripts` v `zabbix_server.conf`/`zabbix_proxy.conf`), spustitelný pro uživatele, pod kterým běží Zabbix server/proxy.
- Balíček `ldap-utils` (binárka `ldapsearch`) nainstalovaný na Zabbix serveru/proxy.
- Každý host, na který je šablona přiřazená, musí mít nakonfigurované aspoň jedno rozhraní s **vyplněným DNS jménem** (např. rozhraní typu Agent s DNS jménem `ldap4.vse.cz`) – i když na hostu žádný agent neběží a i když má rozhraní "Connect to" nastaveno na IP. Item key používá `{HOST.DNS}`, ne `{HOST.CONN}`, protože certifikát serveru neprojde ověřením proti IP adrese.

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$LDAP.PORT}` | `636` | TCP port LDAPS. |
| `{$LDAP.BIND.DN}` | `uid=monitor,ou=admin,dc=vse,dc=cz` | Bind DN pro funkční test (stejný účet na všech LDAP serverech). |
| `{$LDAP.BIND.PASSWORD}` | *(prázdné, typ Secret text)* | Heslo k `{$LDAP.BIND.DN}`. **Musí se nastavit na úrovni hosta** – demo LDAP server má jiné heslo než zbytek. |
| `{$LDAP.BIND.TIMEOUT}` | `3` | Síťový a vyhledávací časový limit (sekundy) předávaný `ldapsearch` (`-o nettimeout`, `-l`). |

Makra `{$LDAP.PORT}`, `{$LDAP.BIND.DN}` a `{$LDAP.BIND.PASSWORD}` jsou záměrně pojmenovaná stejně jako v budoucí šabloně LDAP Statistics, aby šlo heslo zadat jen jednou na hosta a použít pro obě šablony.

## Položky a triggery

| Položka | Typ | Klíč | Hodnota |
|---|---|---|---|
| LDAP: Functional bind and search test (LDAPS) | External check | `ldap_bind_check.sh[{HOST.DNS},{$LDAP.PORT},{$LDAP.BIND.DN},{$LDAP.BIND.PASSWORD},{$LDAP.BIND.TIMEOUT}]` | Text: `OK` nebo `FAILED: <důvod>` |

Update interval: 5 minut. Item-level timeout: 5 s (nad rámec 3s síťového limitu skriptu, kvůli spuštění procesu).

| Trigger | Severity | Poznámka |
|---|---|---|
| LDAP: Functional bind+search test failed on {HOST.NAME} | High | `last(...)<>"OK"`; Operational data zobrazuje přímo poslední hodnotu položky (tedy důvod selhání) bez nutnosti otevírat položku. Popis triggeru obsahuje hotový příkaz pro ruční ověření s `-W` (interaktivní zadání hesla). |

## Formát výstupu skriptu

Skript vždy vypíše jeden řádek a skončí s exit kódem 0 (položka tak nikdy nespadne do "Not supported" a chyba se vždy dostane až k triggeru):

- **`OK`** – bind i search proběhly úspěšně a search vrátil aspoň jeden záznam (`# numEntries: N`, N ≥ 1).
- **`FAILED: <důvod>`** – kryje dva různé případy, oba viditelné přímo v Zabbixu bez nutnosti logovat se na server:
  - **chyba validace parametrů** – např. `bind password parameter is empty (check {$LDAP.BIND.PASSWORD} for this host)`, když zapomeneš nastavit heslo na konkrétním hostu;
  - **skutečná chyba `ldapsearch`** – bind/TLS/síťová chyba nebo timeout. Skript nevymýšlí vlastní kategorizaci, ale vytáhne nejvýstižnější řádek přímo z výstupu `ldapsearch` (přednostně řádek `additional info:`, pak řádek začínající `ldap_`/`TLS:`, jinak poslední neprázdný řádek).
  - zvláštní případ: pokud `ldapsearch` skončí s exit kódem 0, ale vrátí `# numEntries: 0` (bind prošel, ale search z nějakého důvodu – např. ACL – nevrátil žádný záznam), hlásí se to jako `FAILED: search returned zero entries (unexpected for an authenticated rootDSE search)`, ne jako úspěch.

## Bezpečnostní poznámka

Heslo (`{$LDAP.BIND.PASSWORD}`) se do skriptu předává jako obyčejný argument příkazové řádky – po dobu běhu kontroly je tedy viditelné ve výpisu procesů (`ps aux`) na Zabbix serveru. Vzhledem k tomu, že přístup na Zabbix server mají jen důvěryhodní administrátoři, jde o akceptované riziko (alternativou by bylo čtení hesla ze souboru na disku serveru mimo Zabbix konfiguraci, což by přineslo další soubor ke správě navíc).

## Instalace

1. Zkopírovat `ldap_bind_check.sh` do `ExternalScripts` adresáře Zabbix serveru/proxy (typicky `/usr/lib/zabbix/externalscripts/`, ověř v konfiguraci), nastavit spustitelnost.
2. Ověřit, že je na Zabbix serveru/proxy nainstalovaný balíček `ldap-utils`.
3. V Zabbixu: **Data collection → Templates → Import**, nahrát YAML soubor šablony.
4. Přiřadit šablonu na všech šest hostů: demo, primary, ldaptest.vse.cz, ldap4.vse.cz, ldap5.vse.cz, ldap.vse.cz (VIP).
5. Na každém hostu zkontrolovat/doplnit rozhraní s vyplněným DNS jménem (i bez běžícího agenta).
6. Nastavit makro `{$LDAP.BIND.PASSWORD}` na úrovni **hosta** (ne šablony) – demo má jiné heslo než zbytek.

## Řešení problémů

- **Položka ukazuje `FAILED: bind password parameter is empty...`** – na daném hostu chybí nastavené makro `{$LDAP.BIND.PASSWORD}`.
- **Položka ukazuje `FAILED: ldapsearch binary not found...`** – na Zabbix serveru/proxy chybí balíček `ldap-utils`.
- **Položka je "Not supported"** – nejde o chybu samotného LDAP testu (ty se hlásí jako `FAILED: ...` v hodnotě položky), ale o problém s během skriptu samotného – zkontrolovat, že skript existuje v `ExternalScripts` adresáři a má nastavená práva ke spuštění.
- **`FAILED: additional info: TLS: hostname does not match CN in peer certificate`** – host v Zabbixu nemá vyplněné DNS jméno na rozhraní (item se připojuje na IP místo DNS jména).
- **Ruční ověření** – přesný příkaz s dosazenými hodnotami je v popisu triggeru; heslo se zadává interaktivně přes `-W`.

## Známá omezení

- Test ověřuje jen bind + search na rootDSE, ne konkrétní data v adresáři (to je záměr – jde o obecný funkční test dostupný na všech serverech bez ohledu na strukturu stromu).
- Heslo je po dobu běhu kontroly viditelné v procesech na Zabbix serveru (viz bezpečnostní poznámka výše).

## Changelog

### 7.4-1 (2026-07-31)
- První verze šablony.
- Externí check (`ldap_bind_check.sh`) s autentizovaným LDAPS bind + search testem na rootDSE.
- Validace vstupních parametrů s popisnou chybovou hláškou pro snadnou diagnostiku deploymentu.
- Rozlišení "bind úspěšný, ale 0 záznamů" od skutečného úspěchu.
- Textový výstup (`OK` / `FAILED: <důvod>`) s důvodem selhání přímo v Operational data triggeru.
- Použití `{HOST.DNS}` (ne `{HOST.CONN}`) kvůli ověření TLS certifikátu proti hostname.
