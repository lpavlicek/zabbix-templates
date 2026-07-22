# Request Tracker by Zabbix agent 2

Šablona pro Zabbix 7.4 pro monitorování menší instalace [Request Tracker](https://www.bestpractical.com/rt/) 6.0.3, běžící pod Apache přes `mod_fcgid` (`ScriptAlias /rt /opt/rt6/sbin/rt-server.fcgi/`).

## Co šablona sleduje

- **Chyby Postfixu** ve sdíleném mail logu (`fatal:`, `panic:`, `reject:`).
- **Kritické chyby RT** ve stejném mail logu (RT loguje přes syslog, tag `RT:`) – úroveň `crit`/`alert`/`emerg` a výpadky DB spojení (`DBI connect(`).
- **Chyby `mod_fcgid`** v Apache error logu (např. `Connection reset by peer` při komunikaci s `rt-server.fcgi`).
- **Stáří posledního přijatého požadavku** – doba od posledního založeného tiketu nebo přijaté odpovědi/korespondence, přes přímý dotaz do databáze RT.
- **Běh a počet procesů** `rt-server.fcgi`.

## Co šablona záměrně nesleduje

Tohle už je (podle zadání) pokryto jinde, a tato šablona to duplicitně neřeší:

- operační systém (CPU, paměť, disky, aktualizace, čas...),
- dostupnost webového rozhraní a platnost certifikátu,
- MySQL/MariaDB server jako takový (běžící procesy, replikace...),
- mail queue Postfixu,
- počty tiketů ve frontách RT.

## Požadavky

1. **Zabbix agent 2** na monitorovaném hostu, s **povolenými aktivními kontrolami** (nutné pro položky typu `log[]`).
2. Na stejném hostu už přilinkovaná šablona **`MySQL by Zabbix agent 2`** – tahle šablona z ní přebírá makra `{$MYSQL.USER}` a `{$MYSQL.PASSWORD}` a sama je nedefinuje.
3. V konfiguraci Zabbix agenta 2 povolené custom queries:
   ```
   Plugins.Mysql.CustomQueriesEnabled=1
   ```
4. Soubor `rt_last_request_age.sql` (přiložen v repozitáři) umístěný v adresáři pro custom queries (`Plugins.Mysql.CustomQueriesPath`, výchozí `/usr/local/share/zabbix/custom-queries/mysql/`).
5. MySQL uživatel použitý přes `{$MYSQL.USER}`/`{$MYSQL.PASSWORD}` musí mít navíc oprávnění:
   ```sql
   GRANT SELECT ON rt6.Transactions TO '<uzivatel>'@'localhost';
   ```
6. Po úpravě konfigurace restartovat `zabbix-agent2`.

## Instalace

1. Naimportovat `RT_Monitoring_by_Zabbix_agent_2.yaml` do Zabbixu (Data collection → Templates → Import).
2. Šablonu přilinkovat na hosta, na kterém už běží šablona `MySQL by Zabbix agent 2` (kvůli sdíleným makrům přihlašovacích údajů).
3. Provést kroky 3–6 z požadavků výše.
4. Zkontrolovat/upravit makra na úrovni hosta – zejména `{$RT.MYSQL.DSN}`, pokud se cesta k socketu nebo způsob připojení k databázi na daném serveru liší (viz sekce Makra).

## Makra

| Makro | Výchozí hodnota | Význam |
|---|---|---|
| `{$RT.LOG.MAIL}` | `/var/log/mail` | Cesta k syslog souboru, kde jsou společně chyby Postfixu i RT (tag `RT:`). |
| `{$RT.LOG.APACHE.ERROR}` | `/var/log/apache2/error.log` | Cesta k Apache error logu virtuálního hostu s `rt-server.fcgi`. |
| `{$RT.PROCESS.NAME}` | `rt-server.fcgi` | Řetězec hledaný v příkazové řádce procesu (matching přes cmdline, ne přes jméno procesu). |
| `{$RT.PROCESS.MIN}` | `1` | Minimální očekávaný počet běžících procesů `rt-server.fcgi`. |
| `{$RT.LASTREQUEST.MAXAGE}` | `24h` | Maximální přípustné stáří posledního tiketu/odpovědi, než se vyhlásí problém. |
| `{$RT.MYSQL.DSN}` | `unix:/run/mysqld/mysqld.sock` | Connection string pro dotaz na stáří posledního požadavku – viz upozornění níže. |

**Upozornění k `{$RT.MYSQL.DSN}`:** parametr je záměrně nastaven explicitně na unix socket, ne ponechán prázdný. Prázdná hodnota by znamenala výchozí `tcp://localhost:3306`, a v našem testovacím prostředí `localhost` přednostně resolvoval na IPv6 `::1`, na kterém docházelo k `i/o timeout`. Pokud instalace používá TCP spojení nebo jiný socket, uprav hodnotu makra na hostu (např. `tcp://127.0.0.1:3306` nebo jinou cestu k socketu).

## Položky a triggery

| Item | Typ | Trigger | Závažnost |
|---|---|---|---|
| Postfix: fatal/panic/reject errors in mail log | Zabbix agent (aktivní), log | Postfix: fatal/panic error or rejected mail | Warning |
| RT: critical errors in mail log | Zabbix agent (aktivní), log | RT: critical error in mail log | High |
| Apache: mod_fcgid errors for rt-server.fcgi | Zabbix agent (aktivní), log | Apache: mod_fcgid error for rt-server.fcgi | Average |
| RT: age of last received request (ticket or correspondence) | Zabbix agent (pasivní), `mysql.custom.query` | RT: no new ticket or reply received in the last {$RT.LASTREQUEST.MAXAGE} | High (závisí na triggeru "process not running") |
| RT: number of running rt-server.fcgi processes | Zabbix agent (pasivní), `proc.num` | RT: rt-server.fcgi is not running | Disaster |

Poznámky k návrhu:
- Apache error log obsahuje i vlastní log RT (přes STDERR) – ten se ale duplikuje s tím, co už chytáme z `/var/log/mail`, takže z Apache logu se záměrně vyhodnocují jen skutečné chyby modulu `mod_fcgid`.
- U mail logu je z úrovně `err` záměrně vyloučeno vyhodnocování (obsahuje v tomto prostředí výhradně `FAILED LOGIN`, které nemá být hlášeno); skutečné vážné problémy typicky projdou i tak přes úroveň `crit`/`alert`/`emerg` nebo přes explicitní odchyt `DBI connect(`.
- Dotaz na stáří posledního požadavku používá `ORDER BY id DESC LIMIT 1` místo `MAX(Created)` – u větší tabulky `Transactions` jde o zásadní rozdíl ve výkonu (viz troubleshooting níže).

## Troubleshooting

**Import selže na `unexpected tag "triggers"`**
Triggery musí být v YAML vnořené pod konkrétní item (`items: - ... triggers: [...]`), ne jako přímá položka šablony. Pokud šablonu ručně upravuješ, dodržuj strukturu podle [oficiální dokumentace Zabbixu](https://www.zabbix.com/documentation/current/en/manual/xml_export_import/templates).

**Regulární výraz v log itemu hlásí `missing closing parenthesis`**
Při ručním psaní/úpravě klíče itemu: v parametrech Zabbix item-key se escapují pouze uvozovky (`"` → `\"`), zpětné lomítko se needubluje. Zdvojení zpětného lomítka (jak by se dalo čekat z jiných kontextů) rozbije regulární výraz.

**`mysql.custom.query` vrací `Cannot fetch data: invalid connection` / `i/o timeout`**
Ověř dvě věci odděleně:
1. **Připojení** – zkus `zabbix_agent2 -t 'mysql.custom.query[{$RT.MYSQL.DSN},<uzivatel>,<heslo>,rt_last_request_age]'` (s reálnými hodnotami místo maker). Pokud selže i ruční `mysql` klient, jde o síťový/oprávnění problém.
2. **Rychlost dotazu** – pokud se ruční `mysql` klient připojí a dotaz jen dlouho trvá, jde o `Plugins.Mysql.CallTimeout` (výchozí přebírá globální `Timeout` z `zabbix_agent2.conf`, obvykle jen několik sekund). V naší instalaci trval původní dotaz s `MAX(Created)` přes celou tabulku `Transactions` cca 6 vteřin – řešením byl přechod na `ORDER BY id DESC LIMIT 1` (viz `rt_last_request_age.sql`), který díky primárnímu klíči najde poslední vyhovující řádek bez plného průchodu tabulky. Pokud by ani to nestačilo, zvaž přidání indexu `CREATE INDEX zbx_trans_type_created ON Transactions (Type, Created);` nebo zvýšení `Plugins.Mysql.CallTimeout` (max. 30 s).

## Verze

**7.4-1** (22.7.2026) – první verze šablony.
