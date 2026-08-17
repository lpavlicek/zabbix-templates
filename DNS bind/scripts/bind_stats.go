package main

import (
    "encoding/json"
    "flag"
    "fmt"
    "net"
    "net/http"
    "os"
    "strings"
    "time"
)

// Struktura pro mapování JSONu z BIND
type BindData struct {
	Version    string         `json:"version"`
	BootTime   string         `json:"boot-time"`
	ConfigTime string         `json:"config-time"`
	QTypes     map[string]int `json:"qtypes"`
	NSStats    map[string]int `json:"nsstats"`
}

func main() {
	// Parametry příkazové řádky
	bindURL := flag.String("url", "http://127.0.0.1:8053/json/v1/server", "URL statistik BINDu")
    fqdn := GetFQDN()
    optHostname := flag.String("hostname", fqdn, "Hostname pro Zabbix")
	flag.Parse()

	// Stažení dat
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(*bindURL)
	if err != nil {
		fmt.Printf("%s bind.error_msg \"Chyba HTTP: %v\"\n", *optHostname, err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Printf("%s bind.error_msg \"Chyba statusu: %s\"\n", *optHostname, resp.Status)
		return
	}

	var data BindData
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		fmt.Printf("%s bind.error_msg \"Chyba parsování JSON: %v\"\n", *optHostname, err)
		return
	}

	// Výpis výsledků
	fmt.Printf("%s bind.version %s\n", *optHostname, data.Version)

	// Časy
	printTime(*optHostname, "boot-time", data.BootTime)
	printTime(*optHostname, "config-time", data.ConfigTime)

	// QTypes
	qtypesToTrack := []string{"A", "NS", "SOA", "PTR", "MX", "TXT", "AAAA", "SRV", "DNSKEY", "HTTPS", "SVCB", "CNAME", "DS"}
	otherSum := 0
	trackedMap := make(map[string]bool)

	for _, qt := range qtypesToTrack {
		val := data.QTypes[qt]
		fmt.Printf("%s bind.qtypes.%s %d\n", *optHostname, qt, val)
		trackedMap[qt] = true
	}

	for k, v := range data.QTypes {
		if !trackedMap[k] {
			otherSum += v
		}
	}
	fmt.Printf("%s bind.qtypes.other %d\n", *optHostname, otherSum)

	// NSStats
	nsStatsToTrack := []string{
		"Requestv4", "Requestv6", "ReqEdns0", "ReqTSIG", "ReqTCP", "AuthQryRej",
		"RecQryRej", "XfrRej", "Response", "TruncatedResp", "RespEDNS0", "RespTSIG",
		"QrySuccess", "QryAuthAns", "QryNoauthAns", "QryReferral", "QryNxrrset",
		"QryNXDOMAIN", "QryDropped", "QryFailure", "XfrReqDone", "RateDropped",
		"RateSlipped", "QryUDP", "QryTCP", "CookieIn", "CookieNew", "CookieBadTime",
		"CookieNoMatch", "CookieMatch", "ECSOpt", "QryBADCOOKIE", "TCPConnHighWater",
	}

	for _, ns := range nsStatsToTrack {
		fmt.Printf("%s bind.nsstats.%s %d\n", *optHostname, ns, data.NSStats[ns])
	}

	// OK hlášení
	fmt.Printf("%s bind.error_msg \"\"\n", *optHostname)
}

func GetFQDN() string {
    hostname, err := os.Hostname()
    if err != nil {
        return ""
    }

    addrs, err := net.LookupHost(hostname)
    if err != nil {
        return hostname
    }

    for _, addr := range addrs {
        names, err := net.LookupAddr(addr)
        if err == nil && len(names) > 0 {
            return strings.TrimSuffix(names[0], ".")
        }
    }

    return hostname
}

func printTime(hostname, key, isoStr string) {
	// BIND dává čas ve formátu 2024-03-20T10:00:00.000Z
	t, err := time.Parse("2006-01-02T15:04:05.000Z", isoStr)
	if err != nil {
		// Zkusíme formát bez milisekund, pokud by se lišil
		t, err = time.Parse(time.RFC3339, isoStr)
	}

	if err == nil {
		fmt.Printf("%s bind.%s %d\n", hostname, key, t.Unix())
	}
}
