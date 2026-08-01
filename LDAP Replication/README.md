# LDAP Replication

Šablona pro Zabbix 7.4 pro monitorování zpoždění (lagu) OpenLDAP `syncrepl` replikace, založená na porovnání `contextCSN` mezi replikou (consumer) a providerem (primary).

## Co šablona sleduje

- **Replikační lag v sekundách** – rozdíl mezi časovou částí `contextCSN` providera a repliky.
- **Časy obou `contextCSN`** (repliky i providera) – informativní, pro dohledání/ověření lagu.
- **Chyba sběru dat** – zda se vůbec podařilo lag spočítat.

## Určeno pro

Pouze tři repliky: `ldaptest.vse.cz`, `ldap4.vse.cz`, `ldap5.vse.cz`. **Ne** primary (je to provider, nemá smysl srovnávat sám se sebou) a **ne** demo (samostatný server bez replikace).

## Proč `dc=cz` vs. `dc=vse,dc=cz` – důležité pro pochopení šablony

`contextCSN` existuje jen jako atribut suffix entry **skutečné databáze**, ne libovolné replikované podvětve. V tomto nasazení:

- **primary** má `namingContexts: dc=cz` → `contextCSN` se čte na `dc=cz`,
- **repliky** mají `namingContexts: dc=vse,dc=cz` → `contextCSN` se čte na `dc=vse,dc=cz`,
- repliky replikují jen podvětev (`searchbase="dc=vse,dc=cz"` v `syncrepl` konfiguraci) z širší databáze providera.

Toto srovnání je spolehlivé **jen proto**, že pod `dc=cz` na primary není nic jiného než `dc=vse,dc=cz` (ověřeno) – jinak by `contextCSN` providera odrážel i změny mimo replikovanou podvětev a lag by uměl ukazovat falešné hodnoty. Pokud by se topologie v budoucnu změnila (např. přibyla další větev pod `dc=cz`), je potřeba tento předpoklad přehodnotit.

**Log-based detekce chyb syncreplu je záměrně vynechaná** – chybové hlášky slapd (včetně syncrepl chyb) na úrovni `notice` a výš už zachytává položka `slapd: error messages in log` v šabloně **LDAP Service Health**. Duplikovat to zvlášť by bylo zbytečné.

## Požadavky

- Skript `ldap_repl_lag.sh` nahraný do adresáře `ExternalScripts` Zabbix serveru/proxy, spustitelný.
- Balíček `ldap-utils` (`ldapsearch`) a GNU `date` (coreutils) na Zabbix serveru/proxy.
- Bind účet s právem číst `contextCSN` na obou stranách (repliky i provider).
- Každý host musí mít rozhraní s vyplněným DNS jménem (stejný důvod jako u ostatních LDAP external-check šablon – `{HOST.DNS}` kvůli TLS certifikátu).
- Topologie: jeden provider, žádný multi-master ani chaining – `contextCSN` se zpracovává jako jednohodnotový atribut.

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$LDAP.PORT}` | `636` | TCP port LDAPS, pro repliku i providera. |
| `{$LDAP.BASE.DN}` | `dc=vse,dc=cz` | Base DN / suffix databáze na replikách. |
| `{$LDAP.BIND.DN}` | `uid=monitor,ou=admin,dc=vse,dc=cz` | Bind DN pro čtení `contextCSN` na obou stranách. |
| `{$LDAP.BIND.PASSWORD}` | *(prázdné, Secret text)* | Heslo k `{$LDAP.BIND.DN}`. Nastavit na úrovni hosta – u tří replik je stejné (replikovaný účet), na demo/primary se tato šablona nepoužívá. |
| `{$LDAP.BIND.TIMEOUT}` | `3` | Síťový a vyhledávací časový limit (s) pro každý ze dvou `contextCSN` dotazů. |
| `{$LDAP.REPL.PROVIDER.HOST}` | `isis-appl1.vse.cz` | DNS jméno providera, stejné pro všechny repliky. |
| `{$LDAP.REPL.PROVIDER.BASE}` | `dc=cz` | Base DN / suffix databáze na providerovi. |
| `{$LDAP.REPL.LAG.WARN}` | `300` (5 min) | Práh pro Warning trigger, v sekundách. |
| `{$LDAP.REPL.LAG.HIGH}` | `1800` (30 min) | Práh pro High trigger, v sekundách. |

`{$LDAP.PORT}`, `{$LDAP.BIND.DN}`, `{$LDAP.BIND.PASSWORD}`, `{$LDAP.BIND.TIMEOUT}` jsou záměrně stejná jména jako u šablon Functional Bind Check / Statistics – heslo stačí na hostu nastavit jednou.

## Architektura – proč je pořadí dotazů důležité

Master item (`LDAP: replication lag raw data`, external check, `history: 0`) spustí skript, který provede **dva** `ldapsearch` dotazy v pevném pořadí:

1. nejdřív `contextCSN` **repliky** (tohoto hosta),
2. pak `contextCSN` **providera**.

Pořadí je záměrné: replika nikdy nemůže mít novější `contextCSN`, než co provider potvrdil v minulosti. Dotazem na providera *až po* replice je zaručeno, že `lag_seconds >= 0` – nemůže vyjít falešně záporně jen kvůli časování dvou po sobě jdoucích síťových dotazů.

Výstup: `{"lag_seconds": N, "replica_csn_time": "...", "provider_csn_time": "..."}`, nebo `{"error": "<důvod>"}` při jakémkoli selhání. Na rozdíl od LDAP Statistics tu **není** částečný úspěch – lag potřebuje obě strany, takže jakékoli selhání je úplné.

## Položky

| Položka | Typ | Klíč | Hodnota |
|---|---|---|---|
| LDAP: replication lag raw data | External check (master) | `ldap_repl_lag.sh[...]` | Text: JSON (history: 0) |
| LDAP: replication lag, seconds | Dependent | `ldap.repl.lag.seconds` | Unsigned, s |
| LDAP: replica contextCSN time | Dependent | `ldap.repl.csn.replica_time` | Char |
| LDAP: provider contextCSN time | Dependent | `ldap.repl.csn.provider_time` | Char |
| LDAP: replication lag collection error | Dependent | `ldap.repl.error` | Char, text chyby nebo prázdný řetězec |

Update interval master itemu: 5 minut. Item-level timeout: 15 s (rezerva na dva sekvenční `ldapsearch` dotazy).

## Triggery

| Trigger | Severity | Poznámka |
|---|---|---|
| LDAP: replication lag is critically high on {HOST.NAME} | High | `lag >= {$LDAP.REPL.LAG.HIGH}` (výchozí 1800s). |
| LDAP: replication lag is elevated on {HOST.NAME} | Warning | `lag >= {$LDAP.REPL.LAG.WARN}` (výchozí 300s). Závisí na High triggeru – nehlásí se duplicitně, když už běží High. |
| LDAP: replication lag collection failing on {HOST.NAME} | Warning | `last(...)<>""`; stejný vzor jako v LDAP Statistics – JavaScript preprocessing vždy vrací text chyby nebo `''`, takže se trigger po zotavení sám zavře. `opdata` ukazuje přímo důvod selhání. |

**Prahy 300s/1800s jsou počáteční odhad** (dle tvého zadání – „začneme s tímto návrhem, případné úpravy dle zkušeností z provozu") – doladit podle reálného chování v produkci.

**Důležité rozlišení:** trigger „collection failing" neznamená nutně, že replikace stojí – jen že se nepodařilo lag změřit (viz description triggeru). Skutečné zastavení replikace se projeví buď rostoucím lagem (pokud se dá měřit), nebo chybami v logu (Service Health šablona).

## Instalace

1. Zkopírovat `ldap_repl_lag.sh` do `ExternalScripts` adresáře Zabbix serveru/proxy, nastavit spustitelnost.
2. Ověřit `ldap-utils` a GNU `date` na Zabbix serveru/proxy.
3. V Zabbixu: **Data collection → Templates → Import**, nahrát YAML soubor šablony.
4. Přiřadit šablonu na `ldaptest.vse.cz`, `ldap4.vse.cz`, `ldap5.vse.cz`.
5. Zkontrolovat/doplnit rozhraní s DNS jménem na každém hostu.
6. Nastavit makro `{$LDAP.BIND.PASSWORD}` na úrovni hosta (pokud je již nastavené z jiné LDAP šablony na stejném hostu, není potřeba nic dělat navíc).
7. Podle potřeby upravit `{$LDAP.REPL.LAG.WARN}` / `{$LDAP.REPL.LAG.HIGH}` na úrovni hosta či šablony dle zkušeností z provozu.

## Řešení problémů

- **Trigger „collection failing"** – `opdata` ukazuje přesný důvod (chybějící heslo, nedostupný provider, chybějící `contextCSN`, chyba parsování). Nejčastější příčina chybějícího `contextCSN`: špatně nastavené `{$LDAP.BASE.DN}` / `{$LDAP.REPL.PROVIDER.BASE}` pro daný host.
- **Lag trvale roste** – ověřit stav `syncrepl` na replice (`systemctl status slapd`, log přes Service Health šablonu), síťovou dostupnost k `{$LDAP.REPL.PROVIDER.HOST}`.
- **Lag ukazuje nesmyslně vysoké číslo hned po nasazení** – zkontrolovat, že `date -u -d` na Zabbix serveru správně parsuje formát `YYYY-MM-DD HH:MM:SS` (vyžaduje GNU coreutils, běžné na Debian/Ubuntu).
- **Ruční ověření** – porovnat obě hodnoty přímo:
  ```
  ldapsearch -x -H ldaps://ldaptest.vse.cz:636 -D "uid=monitor,ou=admin,dc=vse,dc=cz" -W -b "dc=vse,dc=cz" -s base contextCSN
  ldapsearch -x -H ldaps://isis-appl1.vse.cz:636 -D "uid=monitor,ou=admin,dc=vse,dc=cz" -W -b "dc=cz" -s base contextCSN
  ```

## Známá omezení

- Platí jen pro topologii jeden provider → N replik bez multi-master/chaining; víceho hodnotový `contextCSN` (více `sid`) skript nezpracovává (bere první nalezenou hodnotu).
- Spolehlivost srovnání `dc=cz` vs. `dc=vse,dc=cz` stojí na předpokladu, že pod `dc=cz` není nic jiného než replikovaná podvětev – při změně topologie nutno přehodnotit.
- Prahy 300s/1800s jsou počáteční odhad, ne provozně ověřené hodnoty.
- Trigger na chybu sběru nerozlišuje „replikace stojí" od „nedaří se to změřit" – obojí vede ke stejné hlášce.

## Changelog

### 7.4-1 (2026-08-01)
- První verze šablony.
- Master item (`ldap_repl_lag.sh`, external check) porovnávající `contextCSN` repliky a providera (v tomto pořadí, aby lag nemohl vyjít záporně).
- Dependent items pro lag v sekundách a oba `contextCSN` časy.
- Dva triggery na lag (Warning/High) s dependency mezi nimi.
- Položka a trigger pro úplné selhání sběru dat, s automatickým uzavřením problému po obnovení (stejný vzor jako LDAP Statistics).
- Sdílená makra `{$LDAP.BIND.DN}` / `{$LDAP.BIND.PASSWORD}` s ostatními LDAP šablonami.
