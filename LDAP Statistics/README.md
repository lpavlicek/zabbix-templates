# LDAP Statistics

Šablona pro Zabbix 7.4 pro základní statistiky provozu a stavu OpenLDAP (`slapd`), čtené ze stromu `cn=Monitor` (overlay `back-monitor`) přes autentizovaný LDAPS bind – anonymní bind je na všech LDAP serverech zakázaný.

## Co šablona sleduje

- **Počty dokončených operací podle typu** (bind, unbind, search, compare, modify, modrdn, add, delete, abandon, extended) – přepočtené na operace/s.
- **Aktuální počet spojení**.
- **Čas startu slapd** – nepřímý signál nedávného restartu.
- **Chyba sběru dat** – zda se `ldap_stats.sh` vůbec podařilo z hosta něco přečíst.

## Proč external check, ne agent

Stejně jako u Functional Bind Check – funguje i na hostech bez Zabbix agenta (primární LDAP server), stejná šablona pokrývá všechny reálné hosty.

## Určeno pro

Hosty demo, primary, ldaptest.vse.cz, ldap4.vse.cz, ldap5.vse.cz. VIP (`ldap.vse.cz`) je vynechán – není samostatný fyzický uzel a nemá vlastní `cn=Monitor`.

## Požadavky

- Skript `ldap_stats.sh` nahraný do adresáře `ExternalScripts` Zabbix serveru/proxy, spustitelný.
- Balíček `ldap-utils` (`ldapsearch`) na Zabbix serveru/proxy.
- `back-monitor` načtený na cílovém LDAP serveru a bind účet s právem číst `cn=Monitor`.
- Každý host musí mít nakonfigurované rozhraní s vyplněným **DNS jménem** (viz níže, stejný důvod jako u Functional Bind Check – `{HOST.DNS}` kvůli TLS certifikátu).

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$LDAP.PORT}` | `636` | TCP port LDAPS. |
| `{$LDAP.BIND.DN}` | `uid=monitor,ou=admin,dc=vse,dc=cz` | Bind DN pro čtení `cn=Monitor`. |
| `{$LDAP.BIND.PASSWORD}` | *(prázdné, typ Secret text)* | Heslo k `{$LDAP.BIND.DN}`. **Nastavit na úrovni hosta** – demo má jiné heslo. |
| `{$LDAP.BIND.TIMEOUT}` | `3` | Síťový a vyhledávací časový limit (s) pro každý ze tří dílčích `ldapsearch` dotazů. |

Tato makra jsou záměrně stejná jako u šablony **LDAP Functional Bind Check** (stejné jméno, stejné výchozí hodnoty) – na hostu, kde jsou přiřazeny obě šablony, se heslo zadává jen jednou.

## Architektura – master item + dependent items

Jedna položka typu External check (`LDAP: cn=Monitor raw statistics`) spustí skript, který interně provede až tři samostatné `ldapsearch` dotazy (operace, aktuální spojení, čas startu) a výsledek sloučí do jednoho JSON:

```json
{"operations":{"bind":15234,"search":894321,...},"connections_current":27,"start_time":"2026-07-25 08:01:23"}
```

Z ní pak 12 dependent items přes JSONPath vytáhne jednotlivé hodnoty. Master item má `history: 0` – neukládá se, slouží jen jako přenosová vrstva pro dependent items.

**Odolnost vůči částečnému selhání:** každá ze tří sekcí (`operations`, `connections_current`, `start_time`) se do JSON zahrne, jen když se povede příslušný dílčí dotaz. Když jeden dotaz selže a ostatní projdou, chybí v JSON jen ta jedna sekce – dependent items na ni mají `error_handler: Discard value`, takže při chybějící sekci prostě podrží poslední známou hodnotu, bez chybového stavu položky.

**Úplné selhání** (validace parametrů, chybějící `ldapsearch`, nebo selhání všech tří dotazů najednou) vrátí místo toho `{"error": "<důvod>"}` – na to slouží položka a trigger níže.

## Položky

| Položka | Typ | Klíč | Hodnota |
|---|---|---|---|
| LDAP: cn=Monitor raw statistics | External check (master) | `ldap_stats.sh[...]` | Text: JSON (history: 0, neprohlížet přímo) |
| LDAP: Bind/Unbind/Search/Compare/Modify/Modrdn/Add/Delete/Abandon/Extended operations, ops/sec | Dependent | `ldap.stats.ops.<typ>.rate` | Float, ops/s |
| LDAP: current connections | Dependent | `ldap.stats.connections.current` | Unsigned |
| LDAP: slapd start time | Dependent | `ldap.stats.start_time` | Char, `YYYY-MM-DD HH:MM:SS` |
| LDAP: cn=Monitor collection error | Dependent | `ldap.stats.error` | Char, text chyby nebo prázdný řetězec |

Update interval master itemu: 5 minut. Item-level timeout: 15 s (rezerva na 3 sekvenční `ldapsearch` volání).

## Chybová položka a trigger

Položka **`LDAP: cn=Monitor collection error`** je jediná s triggerem v této šabloně. Na rozdíl od ostatních dependent items se **nezahazuje** při chybějícím poli `error` v JSON – přes krok JavaScript preprocessing vrací buď text chyby, nebo prázdný řetězec:

```javascript
try {
  var data = JSON.parse(value);
  return data.error || '';
} catch (e) {
  return '';
}
```

Díky tomu se položka aktualizuje v každém cyklu a trigger se **sám automaticky uzavře**, jakmile sběr dat zase začne fungovat – není potřeba nic zavírat ručně.

| Trigger | Severity | Poznámka |
|---|---|---|
| LDAP: cn=Monitor statistics collection failing on {HOST.NAME} | Warning | `last(...)<>""`; Operational data zobrazuje přímo důvod selhání. |

**Pozor na rozsah:** tento trigger pokrývá jen **úplné** selhání (viz architektura výše) – když selže jen jedna ze tří dílčích sekcí a zbytek projde, trigger se nespustí (příslušné dependent items jen tiše podrží starou hodnotu). To je záměr, ne mezera – u statistik, které slouží čistě ke grafování, by trigger na každý dílčí výpadek jedné metriky byl zbytečně hlučný.

## Instalace

1. Zkopírovat `ldap_stats.sh` do `ExternalScripts` adresáře Zabbix serveru/proxy, nastavit spustitelnost.
2. Ověřit `ldap-utils` na Zabbix serveru/proxy.
3. V Zabbixu: **Data collection → Templates → Import**, nahrát YAML soubor šablony.
4. Přiřadit šablonu na hosty demo, primary, ldaptest.vse.cz, ldap4.vse.cz, ldap5.vse.cz.
5. Zkontrolovat/doplnit rozhraní s DNS jménem na každém hostu.
6. Nastavit makro `{$LDAP.BIND.PASSWORD}` na úrovni hosta (pokud je již nastavené z šablony Functional Bind Check na stejném hostu, není potřeba nic dělat navíc).

## Řešení problémů

- **Trigger „collection failing"** – hodnota `opdata` u problému ukazuje přesný důvod (stejné hlášky jako u Functional Bind Check – chybějící heslo, chybějící `ldapsearch`, chyba bindu/sítě). Postupovat stejně jako v troubleshootingu Functional Bind Check.
- **Trigger nikdy neproběhne, ale grafy jsou prázdné/staré** – jde pravděpodobně o částečné selhání jedné sekce (viz výše); zkontrolovat, zda `back-monitor` skutečně obsahuje `cn=Operations`/`cn=Connections`/`cn=Time` a že bind účet má právo je číst.
- **Item `ldap.stats.error` pořád ukazuje starou chybu, i když je LDAP zpátky OK** – nemělo by se stávat díky JS logice (vrací `''` při úspěchu); pokud ano, zkontrolovat, že master item skutečně dostává nový JSON (Latest data → zobrazit historii raw položky).

## Známá omezení

- Bez triggerů na jednotlivé metriky (operace/s, spojení) – čistě grafovací data.
- Chybová položka pokrývá jen úplné selhání sběru, ne výpadek jedné dílčí sekce.
- Čas startu je informativní, žádný trigger na neočekávaný restart.

## Changelog

### 7.4-1 (2026-08-01)
- První verze šablony.
- Master item (`ldap_stats.sh`, external check) + 10 dependent items s počty operací podle typu (ops/sec přes `CHANGE_PER_SECOND`).
- Dependent items pro aktuální počet spojení a čas startu slapd.
- Odolnost vůči částečnému selhání jednotlivých sekcí JSON (`error_handler: Discard value`).
- Položka a trigger pro úplné selhání sběru dat (`ldap.stats.error`), s automatickým uzavřením problému po obnovení.
- Sdílená makra `{$LDAP.BIND.DN}` / `{$LDAP.BIND.PASSWORD}` s šablonou LDAP Functional Bind Check.
