# Instalace S3 Storage Monitoring šablony pro Zabbix

## Krok 1: Příprava external scriptu

1. Na Zabbix serveru/proxy nainstalujte s3cmd, v Debianu/Ubuntu je to
```bash
sudo apt install s3cmd
```
2. Zkopírujte script `s3_usage_check.sh` do adresáře `/usr/lib/zabbix/externalscripts/` na Zabbix serveru/proxy
3. Nastavte správná oprávnění:
```bash
chmod +x /usr/lib/zabbix/externalscripts/s3_usage_check.sh
```

## Krok 2: Konfigurace s3cmd

1. Vytvořte konfigurační soubor s3cmd (např. `/etc/zabbix/external_scripts.d/s3cmd.conf`):
```ini
[default]
access_key = YOUR_ACCESS_KEY
secret_key = YOUR_SECRET_KEY
host_base = your-s3-endpoint.com
host_bucket = your-s3-endpoint.com
use_https = True
```

2. Nastavte oprávnění ke konfiguračnímu souboru:
```bash
chmod 440 /etc/zabbix/external_scripts.d/s3cmd.conf
chgrp zabbix /etc/zabbix/external_scripts.d/s3cmd.conf
```

3. Otestujte funkčnost konfigurace:
```bash
s3cmd du -c /etc/zabbix/external_scripts.d/s3cmd.conf
```

4. Otestujte funkčnost skriptu s konfiguraci:
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/s3_usage_check.sh /etc/zabbix/external_scripts.d/s3cmd.conf
```


## Krok 3: Import šablony do Zabbix

1. V Zabbix web rozhraní přejděte na **Configuration → Templates**
2. Klikněte na **Import**
3. Nahrajte soubor `S3_Storage_Usage.xml`
4. Potvrďte import


## Krok 4: Přiřazení šablony k hostu

1. Vytvořte nebo upravte host
2. Přiřaďte šablonu "S3 Storage Usage"

## Krok 5: Upravte makra na úrovni hostu podle potřeby

Po přiřazení šablony upravte makra pro konkrétní host:

- **{$S3.CONFIG_FILE}**: Cesta ke konfiguračnímu souboru s3cmd (default: `/etc/zabbix/external_scripts.d/s3_usage.cfg`)
- **{$S3.MAX_CAPACITY}**: Maximální kapacita v bytech (default: 1TB = 1099511627776)
- **{$S3.MAX_OBJECTS}**: Maximální počet objektů (default: 1000000)
- **{$S3.WARNING_PERCENT}**: Procento pro warning (default: 75)
- **{$S3.HIGH_PERCENT}**: Procento pro high severity (default: 90)


## Co šablona obsahuje

### Items (položky):
- **S3 Storage Raw Data**: Raw výstup z s3cmd du
- **S3 Total Usage (bytes)**: Celkové využití v bytech
- **S3 Total Objects Count**: Celkový počet objektů
- **S3 Storage Usage Percentage**: Procentuální využití kapacity
- **S3 Objects Usage Percentage**: Procentuální využití počtu objektů

### Discovery Rules:
- **S3 Buckets Discovery**: Automatické objevování bucketů
  - **S3 Bucket [BUCKET] Size (bytes)**: Velikost jednotlivých bucketů
  - **S3 Bucket [BUCKET] Objects Count**: Počet objektů v bucketech

### Triggers:
- Warning při překročení nastaveného procenta (default 75%)
- High severity při překročení nastaveného procenta (default 90%)
- Pro kapacitu i počet objektů

### Graphs:
- **S3 Storage Usage**: Graf celkového využití
- **S3 Storage Usage Percentage**: Graf procentuálního využití
- **S3 Bucket [BUCKET] Usage**: Grafy pro jednotlivé buckety (discovery)

## Troubleshooting

### Chyby external scriptu:
1. Zkontrolujte oprávnění souboru
2. Ověřte cestu k s3cmd v PATH
3. Otestujte script manuálně: `sudo -u zabbix /usr/lib/zabbix/externalscripts/s3_usage_check.sh /etc/zabbix/external_scripts.d/s3cmd.conf`

### Chyby preprocessing:
1. Zkontrolujte formát výstupu s3cmd
2. Otestujte regulární výrazy v Zabbix preprocessing testu

### Discovery nefunguje:
1. Zkontrolujte, že raw data obsahují očekávaný formát
2. Otestujte JavaScript preprocessing krok

## Monitorované hodnoty

Šablona parsuje výstup ve formátu:
```
   875341248     372 objects s3://bis001/
159667031968   13729 objects s3://pgbackrest/
------------
160542373216 Total
```

A extrahuje:
- Velikost každého bucketu
- Počet objektů v každém bucketu
- Celkovou velikost
- Celkový počet objektů