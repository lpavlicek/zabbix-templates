# syslog-ng by Zabbix agent 2 – šablona pro Zabbix 7.4

Stav: **verze 7.4-4** (2026-10-17). Na hostu `levandule` běží (7.4-2/7.4-3, dump přes cron – přechod na systemd timer čeká). Soubory: `syslog-ng by Zabbix agent 2.yaml`, `README.md` (EN), `host/syslogng-stats-dump`, `host/syslogng-stats-dump.service`, `host/syslogng-stats-dump.timer`, `host/zabbix-maxconn.conf`, `host/logrotate-syslog-ng-maxconn`. Group `lpavlicek templates`. Generátor `/home/claude/syslogng/generate.py` – všech 17 UUID zafixováno (shodná od 7.4-2).

## Kontext
Centrální log server `levandule`: **SUSE SLES 15, bez sudo**, syslog-ng 4.6.0. Konfigurace: `conf.d/levandule.conf` – `s_levandule_udp` = udp() + tcp() 514 (`max-connections(800)`, `log_iw_size(40000)`) + tcp() 1470 (80, Cisco); `s_levandule_tcp` = syslog() 601 (80). `src` = system() + internal(). Interní zprávy → `/var/log/messages` (root, 0640). Žádný `so_keepalive`.
Incident: vyčerpání slotů na 514. 2026-10-12: 788 established / 783 unikátních klientů → reálná zátěž; doporučeno zvýšit max-connections (+ úměrně log_iw_size, LimitNOFILE).

## stats prometheus (4.6.0)
Labely `id`, `driver`, `transport`, `address`, `direction`. `syslogng_socket_rejected_connections_total` chybí (ani legacy stats).

## Design (bez sudo)
- systemd timer `syslogng-stats-dump.timer` (OnCalendar=minutely, AccuracySec=1s) → oneshot `syslogng-stats-dump.service` (root, StateDirectory=syslogng-stats 0755, TimeoutStartSec=30s, LogLevelMax=notice, ProtectSystem=full, RestrictAddressFamilies=AF_UNIX, …) → `syslog-ng-ctl stats prometheus` → `/var/lib/syslogng-stats/stats.prom` (mktemp+mv, 0644).
- Master `vfs.file.contents[{$SYSLOGNG.STATS.FILE}]` history 0; `vfs.file.time[...,modify]` + `fuzzytime(...,{$SYSLOGNG.STATS.MAXAGE})=0` HIGH.
- Dependent `syslogng.stats.status` (JS) + trigger.
- syslog-ng filtr na `Number of allowed concurrent connections reached` ze `src` → `/var/log/syslog-ng-maxconn.log` root:zabbix 0640, logrotate copytruncate; active log item + trigger `nodata(...,{$SYSLOGNG.REJECT.PERIOD})=0` HIGH, manual close.
- LLD (PROMETHEUS_TO_JSON max_connections, stream/input), prototypy connections/max/utilization, HIGH 95 % / WARN 80 %.

## Historie
- 7.4-1 sudo + UserParameter – nenasazena (SLES bez sudo).
- 7.4-2 cron + soubor; trigger rejected `count()>0` – nevypínal se (count se přepočítá jen při nové hodnotě) – nalezl uživatel.
- 7.4-3 trigger → `nodata()=0`.
- 7.4-4 cron → systemd timer (na žádost uživatele); v šabloně změněny jen popisy.

## Nejistoty
- `nodata()=0` po restartu Zabbix serveru: pokud nodata v prvních `sec` sekundách po startu vrací 0, invertovaný trigger se falešně spustí – neověřeno.
- `LogLevelMax=notice` – zda potlačí i hlášky systemd o každém běhu (Starting/Finished), závisí na verzi systemd – ověřit na SLES.
- Hardening služby (ProtectSystem=full, AF_UNIX) ověřen jen `systemd-analyze verify`, ne na SLES.
- Vyšší stats level a rejected čítač – neověřeno.
- Log item unsupported do prvního odmítnutí (soubor neexistuje).
