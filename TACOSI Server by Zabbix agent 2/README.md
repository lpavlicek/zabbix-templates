# TACOSI Server – šablona pro Zabbix 7.4

Stav: **vygenerována jako YAML** (`tacosi_server_by_zabbix_agent2.yaml`), oprava chyby při importu provedena 2026-08-15. Template group: `lpavlicek templates`.

## Historie importu
- 1. pokus: `Invalid parameter "/3/expression": invalid number of parameters in function "find".` – `find()` bere přesně 4 parametry (`item,<sec|#num>,<operator>,<pattern>`), v expression byly omylem 3 čárky za item (`,,,`) místo 2 (`,,`), tedy 5 argumentů. Opraveno na `find(/item,,"regexp","EXIT_CODE=1$")` a `...EXIT_CODE=2$")` v obou triggerech app testu.

## Kontext
- Aplikace: tacosi (interní TACACS+ server), podman + systemd (quadlet), unit `tacosi.service`.
- Port 49/tcp, jen IPv4 (net.tcp.listen[] to detekuje bez ohledu na IP verzi).
- Zabbix agent na hostech: **Zabbix agent 2** → `systemd.unit.info[...]` (agent2-only).
- tacosi-client interní timeout 5s → item-level `timeout: 7s` (nejisté pole, viz níže).
- Chybové chování tacosi-client (od uživatele, autoritativní):
  - exit 0 = PASS/PASS_ADD/PASS_REPL/SUCCESS
  - exit 1 = FAIL/ERROR/RESTART/FOLLOW/neznámý status (`STATUS=...` na stdout)
  - exit 2 = TRANSPORT_ERROR (stdout) nebo chybné použití/usage (holý text na stderr, žádný prefix)

## Finální design (v YAML)
### Makra
| Makro | Typ | Default |
|---|---|---|
| {$TACOSI.HOST} | Text | localhost (BEZ portu) |
| {$TACOSI.PORT} | Text | 49 |
| {$TACOSI.SERVICE.NAME} | Text | tacosi.service |
| {$TACOSI.SECRET} | Secret text | prázdné, nastavit per host |
| {$TACOSI.TEST.USER} | Text | zabbix |
| {$TACOSI.TEST.PASSWORD} | Secret text | prázdné, nastavit per host |

### UserParameter na hostu (zabbix-agent2, `/etc/zabbix/zabbix_agent2.d/userparameter_tacosi.conf`)
```
UserParameter=tacosi.check[*],out=$(/usr/local/bin/tacosi-client -host "$1:$2" -secret "$3" -action login -user "$4" -password "$5" 2>&1); ec=$?; printf '%s\nEXIT_CODE=%s' "$out" "$ec"
```
Nutno zvýšit `Timeout` v zabbix_agent2.conf (min. 7-10s) a v Administration > General > Timeouts pro "Zabbix agent" (min. 7s).

### Items
1. `net.tcp.listen[{$TACOSI.PORT}]` – numeric, 1m, value mapping "TACOSI: service state" 0/1.
2. `systemd.unit.info[{$TACOSI.SERVICE.NAME}]` – text, 1m.
3. `tacosi.check["{$TACOSI.HOST}","{$TACOSI.PORT}","{$TACOSI.SECRET}","{$TACOSI.TEST.USER}","{$TACOSI.TEST.PASSWORD}"]` – text, 3m, timeout 7s, history 7d.

### Triggery
1. Port neposlouchá – `last(...)=0` – High.
2. Systemd unit není active – `last(...)<>"active"` – High.
3. App test exit 1 – `find(/item,,"regexp","EXIT_CODE=1$")=1` – High, opdata `{ITEM.LASTVALUE1}`, závislost na 1 a 2.
4. App test exit 2 – `find(/item,,"regexp","EXIT_CODE=2$")=1` – High, opdata `{ITEM.LASTVALUE1}`, závislost na 1 a 2.

Žádné nodata triggery.

## Otevřené nejistoty k ověření při dalším importu
- Pole `timeout:` u položky (nenašel jsem přímý příklad v oficiálních šablonách, jen nepřímo doloženo). Pokud import zase selže na tomto poli, smazat řádek a nastavit Timeout ručně v UI.
- `find()` syntaxe teď opravena a validována proti dokumentaci (4 parametry). Zbytek schématu ověřen z reálných Zabbix 7.4 exportů.
