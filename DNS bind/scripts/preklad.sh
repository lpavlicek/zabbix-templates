CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo -ldflags '-s -w' -trimpath -o bind_stats_zabbix bind_stats.go
