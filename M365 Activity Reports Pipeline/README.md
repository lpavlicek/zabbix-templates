# M365 Activity Reports Pipeline

Šablona pro Zabbix 7.4 pro monitorování pipeline, která stahuje M365 usage/activity reporty (a report o přiřazených licencích) z Microsoft Graph API a nahrává je do PostgreSQL/TimescaleDB (schéma `activity`, sdílená databáze s projektem `m365logs`).

Cílem šablony není sledovat samotný Microsoft 365, ale **zdraví ETL pipeline** — jestli se data pravidelně stahují a nahrávají, a jak stará jsou naposledy úspěšně nahraná data.

## Architektura monitoringu

Na rozdíl od klasických Zabbix šablon (agent/SNMP na monitorovaném hostu) pipeline data **posílá sama** přes `zabbix_sender`:

```
crontab (m365svc, Ubuntu server s pipeline)
  │
  ▼
m365activity_monitor.sh
  │  volá
  ▼
m365activity_zabbix_data.pl  ── čte z PostgreSQL (etl.load_runs, source LIKE 'activity_%')
  │  vrací JSON (jedna sekce na report_type, VŠECHNY ČASY VE VTEŘINÁCH)
  ▼
zabbix_sender  ── TLS/PSK, push na Zabbix server
  │
  ▼
m365activity.data  (TRAP master item, raw JSON, history vypnutá)
  │  JSONPath preprocessing, jeden Dependent item na metriku
  ▼
m365activity.<report>.last_run_ok / last_run_seconds_ago / loads_today / rows_inserted_today / ...
```

Žádný agent ani SNMP na monitorovaném hostu není potřeba — jediné, co Zabbix server potřebuje, je přijímat trapper data (PSK šifrované spojení) na hostu odpovídajícím `zabbix.host` v `conf/zabbix_monitor.yaml` pipeline (výchozí `m365activity_to_db`).

Pipeline běží na Ubuntu serveru (dle popisu šablony) — jde o `m365activity` projekt, viz přiložený archiv (`bin/`, `conf/`, `sql/`, vlastní `README.md` pipeline).

## Sledované reporty

Šablona sleduje 9 zdrojů (report_type), odvozených z `conf/reports.yaml` pipeline:

| Zdroj (`source`) | Report | Frekvence stahování |
|---|---|---|
| `activity_email_activity` | Email Activity | 2× denně (cron) |
| `activity_apps_usage` | M365 Apps Usage | 2× denně (cron) |
| `activity_onedrive_activity` | OneDrive Activity | 2× denně (cron) |
| `activity_sharepoint_activity` | SharePoint Activity | 2× denně (cron) |
| `activity_teams_activity` | Teams User Activity | 2× denně (cron) |
| `activity_apps_activations` | M365 Apps Activations | 2× denně (cron) |
| `activity_copilot_usage` | Copilot Usage | 2× denně (cron) |
| `activity_copilot_chat_activity` | Copilot Chat Activity | **ruční** stahování z M365 admin centra, cca 1× měsíčně |
| `activity_license` | User Licence Assignment | 2× denně (cron) |

**Copilot Chat Activity je zvláštní případ** — tento report nejde stáhnout přes Graph API, stahuje se ručně z administrativního rozhraní (Reports → Usage → Copilot) a soubor se ručně nahraje do `var/raw/pending/` na pipeline serveru. Proto má vlastní, mnohem volnější prahy stálosti dat (`{$M365ACTIVITY_STALE_MONTHLY_*}`, řádově týdny) — s běžnými denními prahy by permanentně hlásil problém.

## Položky a triggery (na report_type)

Pro každý z 9 zdrojů šablona obsahuje stejnou sadu položek (Dependent items, JSONPath z `m365activity.data`):

| Položka | Klíč | Popis |
|---|---|---|
| `<Report>: status posledního nahrání` | `m365activity.<report>.last_run_ok` | 1 = poslední běh loaderu skončil úspěchem, 0 = selhal nebo ještě nikdy neproběhl. Value mapping "Nahrávání OK". |
| `<Report>: doba od posledního nahrání` | `m365activity.<report>.last_run_seconds_ago` | Kolik vteřin uplynulo od posledního **úspěšného** běhu loaderu. Když loader ještě nikdy neproběhl, pipeline vrací sentinel ~69 dní, takže se korektně vyhodnotí jako "starý". |
| `<Report>: počet nahrání dnes` | `m365activity.<report>.loads_today` | Kolikrát dnes loader pro tento report proběhl (úspěšně i neúspěšně). |
| `<Report>: počet nahraných/aktualizovaných řádků dnes` | `m365activity.<report>.rows_inserted_today` | Součet UPSERTnutých řádků za dnešní den. |
| `User Licence Assignment: počet změn licencí dnes` | `m365activity.license.rows_conflict_today` | Jen u licenčního reportu — počet uživatelů, kterým se dnes zjistila změna přiřazených SKU. U ostatních reportů nemá koncept "konfliktu" smysl, položka tam proto ani neexistuje. |

Triggery:

| Trigger | Závažnost | Podmínka |
|---|---|---|
| `<Report>: poslední nahrání selhalo` | Average | `last_run_ok = 0` |
| `<Report>: data starší než {$M365ACTIVITY_STALE_HIGH}` (Copilot Chat: `..._MONTHLY_HIGH`) | High | `last_run_seconds_ago > práh` |
| `<Report>: data starší než {$M365ACTIVITY_STALE_WARN}` (Copilot Chat: `..._MONTHLY_WARN`) | Warning | `last_run_seconds_ago > práh`, závisí na HIGH triggeru (nezdvojuje se) |

Master item `m365activity.data` (typ Trap) přijímá raw JSON payload ze zabbix_sender, historii má vypnutou (`history: 0`) — slouží jen jako zdroj pro Dependent items, samotná hodnota se v Zabbixu neukládá.

Dva souhrnné grafy přes všech 9 zdrojů: "Doba od posledního nahrání" a "Počet nahraných/aktualizovaných řádků dnes".

## Makra

| Makro | Výchozí hodnota | Popis |
|---|---|---|
| `{$M365ACTIVITY_STALE_HIGH}` | `50h` | Kritická stálost dat pro reporty s 1× denním cronem — pokryje výpadek celého jednoho cyklu. |
| `{$M365ACTIVITY_STALE_WARN}` | `26h` | Varovná stálost — o něco víc než interval mezi běhy (24 h) s rezervou. |
| `{$M365ACTIVITY_STALE_MONTHLY_HIGH}` | `35d` | Kritická stálost pro Copilot Chat (ruční měsíční stahování). |
| `{$M365ACTIVITY_STALE_MONTHLY_WARN}` | `28d` | Varovná stálost pro Copilot Chat. |

Prahy jde upravit globálně na šabloně, nebo per host, pokud se cron interval na konkrétním nasazení liší.

## Nasazení

1. Nainstalovat a nakonfigurovat samotnou pipeline `m365activity` na serveru, který ji provozuje (viz `README.md` v přiloženém archivu — adresářová struktura, Perl/PowerShell závislosti, DB migrace, cron, PSK klíč). To je mimo rozsah tohoto Zabbix repozitáře.
2. V Zabbixu: **Data collection → Templates → Import**, nahrát `M365 Activity Reports Pipeline.yaml`. Skupina šablon `lpavlicek templates` se vytvoří automaticky, pokud ještě neexistuje.
3. Vytvořit v Zabbixu hosta se jménem **přesně odpovídajícím** `zabbix.host` v `conf/zabbix_monitor.yaml` pipeline (výchozí `m365activity_to_db`) a přiřadit mu tuto šablonu. Host nepotřebuje žádné rozhraní (agent/SNMP) — data chodí jako trapper push.
4. Povolit na Zabbix serveru příjem trapper dat s PSK šifrováním pro tohoto hosta (Zabbix frontend: Host → Encryption → PSK, vygenerovaný klíč a identita musí odpovídat `conf/zabbix_monitor.yaml` na straně pipeline).
5. Upravit prahové hodnoty stálosti dat (makra výše) na úrovni hosta, pokud se cron interval na konkrétním nasazení liší od výchozích 2×/1× denně.
6. Ověřit příjem dat — po prvním běhu `m365activity_monitor.sh` by měl `m365activity.data` mít neprázdnou hodnotu a všechny odvozené položky by se měly naplnit (Dependent items se přepočítají hned při přijetí master itemu, není potřeba čekat na další interval).

## Řešení problémů

- **Položky se nikdy nenaplní / `m365activity.data` je prázdný** — ověřit na straně pipeline, že `m365activity_monitor.sh` běží v cronu a v `logs/zabbix_monitor.log` nejsou chyby (`ERROR ... zabbix_sender selhal`, špatný PSK, nedostupný Zabbix server). Ověřit, že jméno hosta v Zabbixu přesně odpovídá `zabbix.host` v `conf/zabbix_monitor.yaml`.
- **Trigger "data starší než ..." hlásí problém hned po instalaci** — normální, pokud loader pro daný report ještě neproběhl (sentinel ~69 dní > práh). Zmizí po prvním úspěšném běhu.
- **Copilot Chat pořád hlásí starý report, i když byl nedávno ručně nahrán** — ověřit, že soubor byl skutečně umístěn do `var/raw/pending/` na pipeline serveru (přesně podle názvu z admin centra, viz poznámka o mezerách v názvu souboru v README pipeline) a že proběhl `load_activity_reports.pl` (ručně nebo příštím cronem).
- **`rows_conflict_today` u ostatních reportů než license** — tato položka u nich v šabloně záměrně neexistuje, koncept "konfliktu" (změny SKU) dává smysl jen u licenčního reportu.

## Kontrola proti doporučením pro Zabbix 7.4 a opravy

Šablona už měla při předání vyplněný `vendor` blok (`lpavlicek`, `7.4-1`) a validní UUID (70 unikátních UUID4, ověřeno) — nebylo potřeba doplňovat. Při kontrole jsem ale našel a opravil dvě věcné chyby a jednu neúplnost:

1. **Nefunkční triggery na stálost Copilot Chat dat.** Makra byla definovaná jako `{$M365ACTIVITY_MONTHLY_STALE_HIGH}` / `{$M365ACTIVITY_MONTHLY_STALE_WARN}`, ale oba triggery u Copilot Chat je odkazovaly pod jinými (a navzájem odlišnými) překlepy: `{$M365ACTIVITY_STALE_MONTLY_HIGH}`, `{$M365ACTIVITY_STALE_MONTLHY_HIGH}`. Protože žádné z těchto jmen neodpovídalo skutečně definovanému makru, Zabbix by tyto dva triggery nedokázal vyhodnotit (neexistující makro v expression) — de facto byly od začátku nefunkční. Opraveno sjednocením na `{$M365ACTIVITY_STALE_MONTHLY_HIGH}` / `{$M365ACTIVITY_STALE_MONTHLY_WARN}` (stejná konvence pořadí slov jako u `{$M365ACTIVITY_STALE_HIGH}`/`_WARN`), včetně opravy závislosti (dependency) mezi WARN a HIGH triggerem, která musí název i expression cílového triggeru přesně odpovídat.
2. **Špatný název triggeru.** WARN trigger na stálost dat u položky `m365activity.copilot_chat.last_run_seconds_ago` se jmenoval "M365 Activity **Copilot Usage**: data starší než ...", i když šlo o **Copilot Chat** (zjevně kopírováno z analogického triggeru u Copilot Usage a nepřejmenováno). Opraveno na "Copilot Chat".
3. **Chybějící Copilot Chat v souhrnných grafech.** Oba grafy ("Doba od posledního nahrání" a "Počet nahraných řádků dnes") obsahovaly 8 z 9 zdrojů — Copilot Chat v nich chyběl (zjevně přidán do items/triggerů později, ale do grafů se nedostal). Doplněno jako devátá série (barva `607D8B`) do obou grafů.

Menší pozorování, které jsem **neměnil** (jen kosmetické, nic nerozbíjí): u položek a triggerů pro "M365 Apps Activations" a "M365 Apps Usage" je v názvu zdvojené "M365" (např. "M365 Activity **M365** Apps Activations: ..."), zatímco ostatních 7 reportů má název bez tohoto zdvojení. Necháno beze změny, protože je to čistě kosmetická věc — dejte vědět, pokud to chcete sjednotit.

## Changelog

### 7.4-1 (2026-08-17)
- Umístěno do tohoto repozitáře.
- Opraveny nefunkční triggery stálosti dat u Copilot Chat (nesouhlasící názvy maker, viz výše).
- Opraven chybný název triggeru "Copilot Usage" → "Copilot Chat".
- Doplněna chybějící série Copilot Chat do obou souhrnných grafů.
- Doplněny template-level tagy `class: software`, `target: m365activity` (šablona je neměla vůbec, na rozdíl od ostatních šablon v repozitáři).
