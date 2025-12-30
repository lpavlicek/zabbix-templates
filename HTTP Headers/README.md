# Zabbix HTTP Headers Monitoring Template

A comprehensive Zabbix template for monitoring HTTP security headers and response codes across multiple URLs.

## Features

- **Security Headers Monitoring**: HSTS, CSP, Referrer-Policy, X-Frame-Options
- **Deprecated Headers Detection**: X-Powered-By, X-XSS-Protection, Feature-Policy
- **HTTP Protocol Version Checking**: HTTP/2 support verification
- **Status Code Monitoring**: Track HTTP response codes and errors
- **Flexible Configuration**: Per-URL customization of monitored headers
- **Low-Level Discovery**: Automatic item creation based on configured URLs

## Requirements

- Zabbix 7.4 or higher
- `curl` installed on Zabbix server/proxy
- External script support enabled in Zabbix configuration

## Installation

### 1. Install External Script

Copy the `http_headers_curl.sh` script to your Zabbix external scripts directory:

```bash
sudo cp http_headers_curl.sh /usr/lib/zabbix/externalscripts/
sudo chmod +x /usr/lib/zabbix/externalscripts/http_headers_curl.sh
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/http_headers_curl.sh
```

### 2. Import Template

1. In Zabbix UI, go to **Data collection** → **Templates**
2. Click **Import**
3. Select `HTTP Headers.yaml`
4. Click **Import**

### 3. Configure Targets

Link the template to a host and configure the `{$HTTP_HEADERS_TARGETS}` macro with your URLs.

## Configuration

### Macro: `{$HTTP_HEADERS_TARGETS}`

Define one or more URLs to monitor, separated by commas. Each URL can include optional parameters using pipe (`|`) separators.

#### Basic Examples

```
https://example.com
https://example.com,https://api.example.com,https://admin.example.com
```

#### Advanced Examples with Parameters

```
https://example.com|method=GET|follow=0
https://admin.example.com|method=GET|http2=0|hsts=1|referrer=1
https://static.example.com|deprecated=1
https://api.example.com|method=GET|http2=1|hsts=1|frame=1|referrer=1|deprecated=1
```

### Available Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `method` | `GET`, `HEAD` | `HEAD` | HTTP method for fetching headers |
| `follow` | `0`, `1` | `1` | Whether curl should follow redirects |
| `http2` | `0`, `1` | `1` | Trigger alert if HTTP/2 is not used |
| `hsts` | `0`, `1` | `1` | Trigger alert if HSTS header is missing |
| `frame` | `0`, `1` | `0` | Trigger alert if clickjacking protection is missing |
| `referrer` | `0`, `1` | `0` | Trigger alert if Referrer-Policy is missing |
| `deprecated` | `0`, `1` | `0` | Trigger alerts for deprecated headers |

### Macro: `{$HTTP_HEADERS_HSTS_MIN_VALUE}`

Minimum required `max-age` value for HSTS header in seconds.

- **Default**: `15552000` (180 days)
- **Recommended**: At least 6 months (15552000 seconds)

## Monitored Headers

### Security Headers

#### HTTP Strict Transport Security (HSTS)
- **Checked**: Presence and `max-age` value
- **Trigger**: Alert if missing or `max-age` < configured minimum
- **Reference**: [OWASP HSTS Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Strict_Transport_Security_Cheat_Sheet.html)

#### Content Security Policy (CSP) - frame-ancestors
- **Checked**: Presence of `frame-ancestors` directive
- **Trigger**: Alert if clickjacking protection is missing (when `frame=1`)
- **Reference**: [MDN CSP frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/frame-ancestors)

#### Referrer-Policy
- **Checked**: Presence of header
- **Trigger**: Alert if missing (when `referrer=1`)
- **Reference**: [MDN Referrer-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy)

### Deprecated Headers (when `deprecated=1`)

#### X-Frame-Options
- **Status**: Deprecated - use CSP `frame-ancestors` instead
- **Trigger**: Warning if present
- **Reference**: [MDN X-Frame-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options)

#### X-XSS-Protection
- **Status**: Deprecated - should be removed or set to 0
- **Trigger**: Warning if present with value > 0
- **Reference**: [OWASP Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html#x-xss-protection)

#### X-Powered-By
- **Status**: Information disclosure - should be removed
- **Trigger**: Warning if present
- **Reference**: [OWASP Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html#x-powered-by)

#### Feature-Policy
- **Status**: Deprecated - renamed to Permissions-Policy
- **Trigger**: Warning if present
- **Reference**: [MDN Permissions-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Permissions-Policy)

## Monitored Metrics

### Per-URL Items

- **HTTP Status Code**: Response status code (200, 404, 500, etc.)
- **HTTP Protocol Version**: HTTP version (2, 1.1, 1.0)
- **HSTS max-age**: Value in seconds
- **Referrer-Policy**: Policy value
- **CSP frame-ancestors**: Directive value
- **X-Frame-Options**: Header value
- **Error Details**: curl errors (SSL issues, connection problems)
- **Raw Headers**: Complete HTTP response headers

### Aggregate Items

- **HSTS Overall Status**: Aggregated HSTS compliance across all URLs
- **Status Code Overall Status**: Aggregated HTTP status across all URLs

## Triggers

### High Priority
- **Error retrieving HTTP headers**: curl-level errors (SSL, connection issues)

### Average Priority
- **HTTP Strict Transport Security missing or short**: HSTS header missing or insufficient `max-age`
- **HTTP error status**: Status code ≥ 400

### Warning Priority
- **No HTTP status code**: Request didn't return a status code
- **Referrer policy missing**: Required Referrer-Policy header is missing
- **Frame clickjacking defense missing**: No X-Frame-Options or CSP frame-ancestors
- **Deprecated header present**: X-Powered-By, X-XSS-Protection, Feature-Policy, or X-Frame-Options detected

### Info Priority
- **HTTP2 required but missing**: HTTP/2 support expected but not available

## Troubleshooting

### Common Issues

#### HTTP/2 Not Detected
Most common causes:
- HTTP/2 module not enabled in web server
- Using `mod_php` instead of `php-fpm` (Apache)
- Web server configuration doesn't support HTTP/2

#### HSTS Alerts
- Verify the `Strict-Transport-Security` header is present
- Check that `max-age` value meets minimum requirement
- Ensure HTTPS is properly configured

#### Script Execution Errors
```bash
# Test script manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/http_headers_curl.sh "https://example.com" "HEAD" "1"

# Check script permissions
ls -la /usr/lib/zabbix/externalscripts/http_headers_curl.sh

# Verify curl is available
which curl
```

#### No Data Collected
- Check Zabbix server/proxy logs: `/var/log/zabbix/zabbix_server.log`
- Verify external scripts are enabled in `zabbix_server.conf`
- Confirm `{$HTTP_HEADERS_TARGETS}` macro is properly configured

## Example Configurations

### Basic Security Monitoring
```
https://example.com|hsts=1
```
Monitors HSTS header only.

### Comprehensive Security Monitoring
```
https://example.com|http2=1|hsts=1|frame=1|referrer=1|deprecated=1
```
Monitors HTTP/2, HSTS, clickjacking protection, referrer policy, and deprecated headers.

### Multiple URLs with Different Requirements
```
https://example.com|http2=1|hsts=1|referrer=1,https://legacy.example.com|http2=0|deprecated=0,https://api.example.com|method=GET|frame=1
```

### Static Content CDN (Less Strict)
```
https://static.example.com|http2=1|hsts=0|frame=0|referrer=0
```

## Security Best Practices

1. **Enable HSTS** with `max-age` ≥ 6 months (15552000 seconds)
2. **Use HTTP/2** for better performance and security
3. **Implement CSP `frame-ancestors`** instead of X-Frame-Options
4. **Remove deprecated headers**: X-Powered-By, X-XSS-Protection, Feature-Policy
5. **Set Referrer-Policy** to control referrer information leakage
6. **Regular monitoring** of security headers across all public-facing URLs

## License

This template is provided as-is for use with Zabbix monitoring systems.

## Author

**lpavlicek**  
Version: 7.4-1

## Contributing

Issues, suggestions, and pull requests are welcome!

## References

- [OWASP Secure Headers Project](https://owasp.org/www-project-secure-headers/)
- [OWASP HTTP Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html)
- [MDN Web Security](https://developer.mozilla.org/en-US/docs/Web/Security)
- [Zabbix Documentation](https://www.zabbix.com/documentation/current/)
