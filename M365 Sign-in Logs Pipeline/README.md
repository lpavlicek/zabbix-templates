# M365 Sign-in Logs Pipeline

Šablona pro Zabbix 7.4 pro monitorování pipeline, která stahuje sign-in logy z Microsoft Entra ID (M365) přes Graph API a nahrává je do PostgreSQL/TimescaleDB (schéma `logs`/`etl`, projekt `m365logs`).

Cílem šablony je sledovat **zdraví ETL pipeline** — jestli se logy pravidelně stahují a nahrávají a jak moc pipeline zaostává za aktuálním časem (checkpoint lag), ne obsah samotných logů.

## Architektura monitoringu

Stejně jako sesterská šablona pro `m365activity` posílá pipeline data **sama** přes `zabbix_sender` (push model), žádný agent ani SNMP na monitorovaném hostu není potřeba:

```
crontab (m365svc, Ubuntu server s pipeline)
  │
  ▼
m365_monitor.sh
  │  volá
  ▼
m365_zabbix_data.pl  ── čte z PostgreSQL (etl.fetch_state, etl.load_runs)
  │  vrací JSON (jedna sekce na zdroj: signin_interactive, signin_noninteractive)
  ▼
zabbix_sender  ── TLS/PSK, push na Zabbix server
  │
  ▼
m365.data  (TRAP master item, raw JSON, history vypnutá)
  │  JSONPath preprocessing, jeden Dependent item na metriku
  ▼
m365.<zdroj>.checkpoint_lag_minutes / last_run_ok / loads_today / rows_inserted_today / rows_conflict_today
```

## Dva zdroje dat

Pipeline stahuje dva typy sign-inů nezávisle na sobě (vlastní fetch skript, vlastní checkpoint):

- **interactive** — interaktivní přihlášení uživatelů.
- **noninteractive** — service principal / managed identity přihlášení.

## Klíčový rozdíl oproti sesterské šabloně "M365 Activity Reports Pipeline"

Tahle pipeline (na rozdíl od `m365activity`) používá **checkpoint** (`etl.fetch_state.last_success_to`) — stahuje inkrementálně od posledního úspěšně zpracovaného okna, ne vždy celý aktuální stav. Proto má navíc metriku **zpoždění checkpointu** (`checkpoint_lag_minutes`) — kolik minut uplynulo od posledního úspěšně zpracovaného okna dat. To je jiná věc než "doba od posledního běhu loaderu" (`last_run_minutes_ago`, u activity pipeline `last_run_seconds_ago`) — loader může běžet často a úspěšně, ale pokud fetch dlouhodobě nestahuje nová data (např. výpadek Graph API přihlášení), checkpoint lag poroste, i když `last_run_ok` bude pořád 1.

**Pozor na jednotky:** zdrojový JSON z `m365_zabbix_data.pl` vrací `checkpoint_lag_minutes` a `last_run_minutes_ago` **v minutách** (na rozdíl od `m365activity`, kde je vše rovnou ve vteřinách). Šablona to řeší preprocessingem `MULTIPLIER × 60` a položky mají `units: s` — uložená a zobrazená hodnota v Zabbixu je tedy ve vteřinách, i když klíč položky (`m365.interactive.checkpoint_lag_minutes`, `...last_run_minutes_ago`) z historických důvodů pořád obsahuje "minutes" v názvu. Prahové makra (`{$M365_CHECKPOINT_LAG_HIGH}` apod.) jsou zadaná v Zabbix time-suffix notaci (`240m`, `120m`), kterou Zabbix při vyhodnocení triggeru sám převede na vteřiny — srovnání je tedy konzistentní.

## Položky a triggery (na zdroj: interactive / noninteractive)

| Položka | Klíč | Popis |
|---|---|---|
| `<Zdroj>: zpoždění checkpointu` | `m365.<zdroj>.checkpoint_lag_minutes` | Kolik vteřin uplynulo od posledního úspěšně zpracovaného okna dat (checkpoint). Vysoká hodnota = pipeline nezpracovává data včas. |
| `<Zdroj>: doba od posledního nahrání` | `m365.<zdroj>.last_run_minutes_ago` | Kolik vteřin uplynulo od posledního dokončeného běhu loaderu (úspěšného i neúspěšného). |
| `<Zdroj>: status posledního nahrání` | `m365.<zdroj>.last_run_ok` | 1 = poslední běh loaderu skončil úspěchem, 0 = selhal nebo ještě nikdy neproběhl. Value mapping "Nahrávání OK". |
| `<Zdroj>: počet nahrání dnes` | `m365.<zdroj>.loads_today` | Kolikrát dnes loader pro tento zdroj proběhl. |
| `<Zdroj>: počet duplicit dnes` | `m365.<zdroj>.rows_conflict_today` | Počet řádků odmítnutých přes `INSERT ... ON CONFLICT DO NOTHING` (duplicity vzniklé překryvem stahovacích oken — očekávané a neškodné, jen informativní metrika). |
| `<Zdroj>: počet nahraných řádků dnes` | `m365.<zdroj>.rows_inserted_today` | Součet skutečně vložených řádků za dnešní den. |

Triggery:

| Trigger | Závažnost | Podmínka |
|---|---|---|
| `M365 <Zdroj>: zpoždění checkpointu > {$M365_CHECKPOINT_LAG_HIGH}` | High | `checkpoint_lag_minutes > práh` (výchozí 4 hodiny) |
| `M365 <Zdroj>: zpoždění checkpointu > {$M365_CHECKPOINT_LAG_WARN}` | Warning | `checkpoint_lag_minutes > práh` (výchozí 2 hodiny), závisí na HIGH triggeru (nezdvojuje se) |
| `M365 <Zdroj>: poslední nahrání selhalo` | Average | `last_run_ok = 0` |

Master item `m365.data` (typ Trap) přijímá raw JSON payload ze zabbix_sender, historii má vypnutou (`history: 0`) — slouží jen jako zdroj pro Dependent items. Kromě metrik použitých v šabloně JSON obsahuje i pole `last_success_to`, `last_run_status`, `last_run_finished_at` a `failed_loads_today` — šablona je nevyužívá, jsou k dispozici pro budoucí rozšíření nebo ruční diagnostiku přes Zabbix **Latest data** (hodnota master itemu).

Čtyři grafy (samostatně pro interactive/noninteractive): "Počet nahraných řádků dnes" a "Zpoždění checkpointu".

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$M365_CHECKPOINT_LAG_HIGH}` | `240m` (4 h) | Kritické zpoždění checkpointu. |
| `{$M365_CHECKPOINT_LAG_WARN}` | `120m` (2 h) | Varovné zpoždění checkpointu. |

Prahy jde upravit globálně na šabloně, nebo per host.

## Nasazení

1. Nainstalovat a nakonfigurovat samotnou pipeline `m365logs` na Ubuntu serveru, který ji provozuje (viz `README.md` v přiloženém archivu — adresářová struktura, TimescaleDB, Perl/PowerShell závislosti, cron, PSK klíč). To je mimo rozsah tohoto Zabbix repozitáře.
2. V Zabbixu: **Data collection → Templates → Import**, nahrát `M365 Sign-in Logs Pipeline.yaml`. Skupina šablon `lpavlicek templates` se vytvoří automaticky, pokud ještě neexistuje.
3. Vytvořit v Zabbixu hosta se jménem **přesně odpovídajícím** `zabbix.host` v `conf/zabbix_monitor.yaml` pipeline (výchozí `m365_to_db`) a přiřadit mu tuto šablonu. Host nepotřebuje žádné rozhraní (agent/SNMP) — data chodí jako trapper push.
4. Povolit na Zabbix serveru příjem trapper dat s PSK šifrováním pro tohoto hosta (Host → Encryption → PSK), identita a klíč musí odpovídat `conf/zabbix_monitor.yaml` na straně pipeline (samostatný klíč od `m365activity`, i kdyby běžel na stejném Zabbix serveru).
5. Upravit prahové hodnoty zpoždění checkpointu (makra výše), pokud se očekávaná frekvence fetch/load na konkrétním nasazení liší od výchozích 30/15 minut.
6. Ověřit příjem dat — po prvním běhu `m365_monitor.sh` by měl `m365.data` mít neprázdnou hodnotu a všechny odvozené položky by se měly naplnit ihned (Dependent items se přepočítají při přijetí master itemu).

## Řešení problémů

- **Položky se nikdy nenaplní / `m365.data` je prázdný** — ověřit na straně pipeline, že `m365_monitor.sh` běží v cronu a v `logs/zabbix_monitor.log` nejsou chyby (špatný PSK, nedostupný Zabbix server). Ověřit, že jméno hosta v Zabbixu přesně odpovídá `zabbix.host` v `conf/zabbix_monitor.yaml`.
- **Trigger "zpoždění checkpointu" hlásí problém hned po instalaci** — normální, pokud zdroj ještě není v `etl.fetch_state` (čerstvé nasazení) — pipeline v tom případě vrací sentinel 99999 minut, což je vždy nad prahem.
- **Zpoždění checkpointu roste, i když `last_run_ok = 1`** — to je smysl mít obě metriky odděleně: loader běží úspěšně, ale fetch dlouhodobě nedodává nová data (typicky výpadek Graph API přihlášení nebo throttling) — zkontrolovat `logs/cron_fetch_interactive.log` / `cron_fetch_noninteractive.log` na straně pipeline.
- **`rows_conflict_today` roste** — očekávané a neškodné, jde o duplicity odchytené přes `ON CONFLICT DO NOTHING` díky přesahu (overlap) stahovacích oken. Není to chyba, jen informativní metrika.

## Kontrola proti doporučením pro Zabbix 7.4 a opravy

Šablona měla vyplněný `vendor` blok (`lpavlicek`, `7.4-2`) a validní UUID (26 unikátních UUID4, ověřeno) — nebylo potřeba doplňovat. Logika maker/triggerů/dependencies byla na rozdíl od sesterské šablony `M365 Activity Reports Pipeline` v pořádku (žádné nesouhlasící makro). Opravil jsem tři drobnosti:

1. **Chybějící template-level tagy** — šablona neměla `tags:` na úrovni template vůbec. Doplněno `class: software`, `target: m365logs`.
2. **Překlep v názvu grafu** — "Zpoždění checkpointu: **nointeractive**" (chybělo "n") opraveno na "noninteractive".
3. **Nefunkční `yaxismax: '0'`** — 3 ze 4 grafů měly nastavené `yaxismax: '0'`, ale bez odpovídajícího `ymax_type_1: FIXED` je toto pole v Zabbixu bez efektu (max osy Y se počítá automaticky) — jen matoucí mrtvá hodnota, která by mohla svést k mylnému dojmu, že je graf omezený na maximum 0. Odstraněno. (`ymin_type_1: FIXED` beze zadaného `yaxismin` zůstalo — minimum 0 je pro tyto vždy nezáporné metriky žádoucí a je to výchozí chování.)
4. Drobný typografický bug (dvojitá mezera) v popisu jednoho triggeru — opraveno.

Dvě věci jsem **neměnil**, jen zmiňuji jako pozorování:
- Klíče položek `checkpoint_lag_minutes` / `last_run_minutes_ago` obsahují "minutes", i když uložená/zobrazená hodnota je díky `MULTIPLIER × 60` a `units: s` ve skutečnosti ve vteřinách (viz sekce výše) — přejmenování klíče položky by ale v Zabbixu znamenalo ztrátu návaznosti na historická data, proto jsem to neměnil bez vyžádání.
- Čtyři samostatné grafy (po jedné sérii) místo dvou souhrnných grafů se dvěma sériemi (interactive + noninteractive pohromadě), jak je to udělané u sesterské šablony `M365 Activity Reports Pipeline`. Funkčně v pořádku, jen jiný styl — dejte vědět, pokud to chcete sjednotit.

## Changelog

### 7.4-2 (2026-08-17, kontrola a drobné opravy)
- Umístěno do tohoto repozitáře.
- Doplněny template-level tagy `class: software`, `target: m365logs`.
- Opraven překlep v názvu grafu ("nointeractive" → "noninteractive").
- Odstraněno nefunkční pole `yaxismax: '0'` ze 3 grafů (bez `ymax_type_1: FIXED` bez efektu).
- Opravena dvojitá mezera v popisu jednoho triggeru.
