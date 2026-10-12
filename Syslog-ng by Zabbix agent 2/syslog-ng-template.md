# syslog-ng by Zabbix agent 2 – šablona pro Zabbix 7.4

Stav: **verze 7.4-2 vygenerována** (2026-10-12), čeká na import. Soubory: `syslog-ng by Zabbix agent 2.yaml`, `README.md` (EN), `host/syslogng-stats-dump`, `host/cron.d-syslogng-stats`, `host/zabbix-maxconn.conf`, `host/logrotate-syslog-ng-maxconn`. Group `lpavlicek templates`. Generátor `/home/claude/syslogng/generate.py` (UUID v1 zafixovány) – po importu upravovat export od uživatele, ne přegenerovat.

## Kontext
Centrální log server: **SUSE SLES 15, bez sudo**, syslog-ng 4.6.0. Konfigurace (archiv od uživatele): `conf.d/levandule.conf` – `s_levandule_udp` = udp() + tcp() 514 (`max-connections(800)`, `log_iw_size(40000)`) + tcp() 1470 (80, Cisco); `s_levandule_tcp` = syslog() 601 (80). `src` = system() + internal(). Interní zprávy → `/var/log/messages` (root, 0640). Žádný `so_keepalive`.
Incident: vyčerpání slotů na 514. 2026-10-12: 788 established / 783 unikátních klientů → reálná zátěž; doporučeno zvýšit max-connections (+ úměrně log_iw_size, LimitNOFILE).

## stats prometheus (4.6.0)
Labely `id`, `driver`, `transport`, `address`, `direction`. `syslogng_socket_rejected_connections_total` chybí (ani legacy stats).

## Design 7.4-2 (bez sudo)
- root cron 1m: `syslog-ng-ctl stats prometheus` → `/var/lib/syslogng-stats/stats.prom` (mktemp+mv, 0644, adresář root 0755).
- Master `vfs.file.contents[{$SYSLOGNG.STATS.FILE}]` history 0; `vfs.file.time[...,modify]` + `fuzzytime(...,{$SYSLOGNG.STATS.MAXAGE})=0` HIGH.
- Dependent `syslogng.stats.status` (JS) + trigger.
- syslog-ng filtr na `Number of allowed concurrent connections reached` ze `src` → `/var/log/syslog-ng-maxconn.log` root:zabbix 0640, logrotate copytruncate; active log item + `count(...,{$SYSLOGNG.REJECT.PERIOD})>0` HIGH.
- LLD (PROMETHEUS_TO_JSON max_connections, stream/input), prototypy connections/max/utilization, HIGH 95 % / WARN 80 %.
- 7.4-1 (sudo + UserParameter) nenasazena, nahrazena.

## Nejistoty
- Vyšší stats level a rejected čítač – neověřeno.
- Log item unsupported do první odmítnutí (soubor neexistuje) – rozbitý filtr šablona nepozná.
- Import nepotvrzen.
