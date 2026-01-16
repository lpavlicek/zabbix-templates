# Zabbix Template: Open LDAP Port

Šablona pro monitorování dostupnosti nešifrovaného LDAP portu 389/tcp ze Zabbix serveru/proxy.

## Účel

Tato šablona slouží k detekci bezpečnostního rizika, kdy je LDAP server dostupný přes nešifrovaný port 389 ze sítě. LDAP komunikace by měla být buď šifrovaná (LDAPS na portu 636) nebo omezená pouze na localhost.

## Vlastnosti

- **Monitorovaný port:** 389/tcp (nešifrovaný LDAP)
- **Interval kontroly:** 5 minut
- **Trigger priorita:** Average (střední)
- **Verze Zabbix:** 7.4

## Co šablona monitoruje

### Item
- **Název:** Open LDAP port 389
- **Klíč:** `net.tcp.service[ldap,,]`
- **Typ:** Simple check
- **Popis:** Test dostupnosti LDAP portu 389/tcp

### Trigger
- **Název:** Otevřený LDAP port ({HOST.NAME})
- **Podmínka:** Spustí se, když je port 389 dostupný (hodnota = 1) posledních 10 minut
- **Recovery:** Automaticky se vyřeší, když port není dostupný (hodnota = 0)

## Bezpečnostní kontext

⚠️ **Bezpečnostní varování:** LDAP server po instalaci obvykle má otevřenou nešifrovanou komunikaci na portu 389, což představuje bezpečnostní riziko. Citlivá data (včetně hesel) mohou být přenášena nešifrovaně.

### Doporučení
1. Použijte LDAPS (port 636) pro šifrovanou komunikaci
2. Omezte nešifrovanou komunikaci pouze na localhost
3. Zakažte port 389 pro vzdálený přístup pomocí firewallu

## Instalace

1. Stáhněte soubor `Open_LDAP_port.yaml`
2. V Zabbix webovém rozhraní přejděte na **Configuration** → **Templates**
3. Klikněte na **Import**
4. Vyberte stažený YAML soubor
5. Klikněte na **Import**

## Použití

1. Přiřaďte šablonu k hostům s LDAP serverem
2. Zabbix server/proxy automaticky začne testovat dostupnost portu 389
3. Pokud je port otevřený, vytvoří se alert se střední prioritou

## Value Mapping

| Hodnota | Význam |
|---------|--------|
| 0 | OK - port není dostupný (bezpečné) |
| 1 | CHYBA - port je otevřen (bezpečnostní riziko) |

## Tagy

- **Class:** software
- **Component:** ldap
- **Scope:** security (u triggeru)

## Požadavky

- Zabbix Server/Proxy verze 7.4 nebo vyšší
- Síťová dostupnost mezi Zabbix serverem/proxy a monitorovaným hostem
- Port 389/tcp musí být testovatelný ze Zabbix serveru/proxy

## Autor

- **Vendor:** lpavlicek
- **Verze:** 7.4-2

## Licence

[Doplňte licenci dle vašich potřeb]

## Podpora

Pro hlášení chyb nebo návrhy na vylepšení prosím vytvořte issue v tomto repozitáři.