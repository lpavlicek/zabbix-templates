# Zabbix Šablona: HTTP to HTTPS Redirect Check (v7.4)

Tato šablona je navržena pro **monitorování vynuceného přesměrování (redirect) z HTTP na HTTPS** pro seznam hostnames definovaných pomocí uživatelského makra. Využívá Zabbix Low-Level Discovery (LLD) a HTTP Agenty k automatickému vytváření kontrolních položek a triggerů pro každý alias.

## 🚀 Funkce

* **Low-Level Discovery (LLD):** Automaticky detekuje a vytváří monitorovací položky pro každý hostname v makru `{$HTTP_REDIRECT_ALIASES}`.
* **Kontrola Status Kódu:** Ověřuje, zda HTTP požadavek vrací kód přesměrování (301, 302, 303).
* **Kontrola Cíle:** Ověřuje, zda cílová adresa v hlavičce `Location` začíná na `https://`.
* **Detekce Selhání:** Upozorňuje na selhání připojení nebo neočekávané status kódy (např. 200 OK, 404 Not Found).

## ⚙️ Kompatibilita

| Komponenta | Verze |
| :--- | :--- |
| **Zabbix Server** | 7.4 a vyšší |
| **Typ hosta** | Host bez Zabbix Agenta (Agentless) |

## 📥 Instalace a Konfigurace

### Krok 1: Import šablony

1.  Stáhněte si soubor `HTTP to HTTPS Redirect Check.yaml`.
2.  V Zabbix Frontend přejděte na **Configuration** -> **Templates**.
3.  Klikněte na **Import** a nahrajte soubor `HTTP to HTTPS Redirect Check.yaml`.

### Krok 2: Přiřazení šablony

1.  Přejděte na **Configuration** -> **Hosts**.
2.  Vyberte hosta (server), který bude monitorován, a přejděte do záložky **Templates**.
3.  Připojte šablonu **`HTTP to HTTPS Redirect Check`**.

### Krok 3: Konfigurace Uživatelkého Makra (Klíčový krok)

Po přiřazení šablony musíte definovat, které hostnames se mají kontrolovat. To se provádí pomocí uživatelského makra.

1.  Na úrovni **Hosta** (nebo přímo v šabloně) přejděte do záložky **Macros**.
2.  Přidejte nebo upravte následující makro:

| Makro | Hodnota | Popis |
| :--- | :--- | :--- |
| `{$HTTP_REDIRECT_ALIASES}` | `example.com,www.example.com,192.168.1.1` | Seznam aliasů oddělených čárkou. |

## 📊 Monitorované Prvky

Šablona využívá LLD k dynamickému vytváření následujících **Item Prototypes** a **Trigger Prototypes** pro každý detekovaný hostname (`{#HOSTNAME}`).

### Položky (Items)

| Název | Klíč | Typ | Popis |
| :--- | :--- | :--- | :--- |
| `HTTP Redirect Check for {#HOSTNAME}` | `http.redirect.check[{#HOSTNAME}]` | HTTP Agent | Provede HEAD požadavek na `http://{#HOSTNAME}` a vrátí hlavičky a status kód. |
| `HTTP Status Code for {#HOSTNAME}` | `http.redirect.status[{#HOSTNAME}]` | Dependent | Získá HTTP status kód (např. 301, 200) z hlavního Itemu. |
| `HTTP Redirect Location for {#HOSTNAME}` | `http.redirect.location[{#HOSTNAME}]` | Dependent | Získá hodnotu hlavičky `Location` (cílová URL přesměrování). |
| `HTTP Redirect is HTTPS for {#HOSTNAME}` | `http.redirect.is_https[{#HOSTNAME}]` | Dependent | Vrací `1` pokud cílová URL v `Location` hlavičce začíná na `https://`, jinak `0`. |

### Spouštěče (Triggers)

| Název | Priorita | Podmínka | Popis |
| :--- | :--- | :--- | :--- |
| **HTTP redirect check failed for {#HOSTNAME}** | **HIGH** | `status = 0` | Selhání připojení nebo nedostupnost cílového serveru. |
| **HTTP does not redirect to HTTPS for {#HOSTNAME}** | **WARNING** | `status != 301, 302, 303` | HTTP požadavek nevrátil přesměrovací kód (např. 200 OK, 404 Not Found). |
| **HTTP redirect target is not HTTPS for {#HOSTNAME}**| **AVERAGE** | `is_https = 0 AND status != 0` | Přesměrování proběhlo, ale cílová URL v hlavičce `Location` není HTTPS. |

## 🛠️ Uživatelská Makra

| Makro | Výchozí hodnota | Popis |
| :--- | :--- | :--- |
| `{$HTTP_REDIRECT_ALIASES}`| *(prázdné)* | Čárkami oddělený seznam DNS jmen/IP adres k ověření. |
| `{$HTTP_REDIRECT_TIMEOUT}` | `10` | Timeout pro HTTP požadavek v sekundách. |

---

## 💡 Jak LLD funguje

1.  **Master Item:** Položka **`HTTP Redirect Hostnames List`** (typ **Calculated**) přečte a vrátí hodnotu makra `{$HTTP_REDIRECT_ALIASES}`.
2.  **Preprocessing LLD:** Pravidlo **`HTTP Redirect Endpoints Discovery`** vezme tento čárkami oddělený seznam.
3.  **JavaScript:** Preprocessing kód bezpečně rozdělí řetězec, odstraní prázdné a bílé znaky a převede jej na požadovaný JSON formát pro LLD, kde je proměnná `{#HOSTNAME}` definována.
4.  **Generování:** Pro každý prvek v JSON poli vytvoří Zabbix sadu monitorovacích položek a triggerů.

*(Tento proces zajišťuje, že LLD je robustní, i když uživatel zadá seznam s nadbytečnými mezerami nebo čárkami.)*