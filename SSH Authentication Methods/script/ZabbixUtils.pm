# Perl modul s pomocnými funkcemi pro Zabbix skripty
# Poskytuje funkce pro čtení YAML konfigurací a nastavení logování
#
# Copyright (C) 2025- Lubos Pavlicek <pavlicek@vse.cz>
#

package ZabbixUtils;

use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(read_yaml_config get_logger);

use strict;
use warnings;
use v5.26;
use utf8;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Syslog;
use POSIX qw(strftime);    # potřeba pro Log::Dispatch callback
use File::Basename;

use YAML::Tiny;

=head1 NAME

ZabbixUtils.pm -- Perl pomocný modul pro Zabbix skripty

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';

=head1 EXPORTABLE HELPER FUNCTIONS

=head2 $conf = read_yaml_config( $filename, $logger )

Načítání konfiguračního souboru v YAML formátu s podporou šifrování.
Pokud soubor obsahuje klíč 'sops', je považován za šifrovaný a 
automaticky se zavolá 'sops --decrypt' pro načtení.

=cut

# Načte konfigurační soubor ve formátu YAML
# Podporuje transparentní dešifrování pomocí SOPS (Secrets Operations)
# pokud je soubor šifrován
#
# Parametry:
#   $conf_file - cesta k konfiguračnímu souboru (povinný)
#   $logger    - volitelný Logger::Dispatch objekt pro hlášení chyb
#                pokud není zadán, chyby se vytisknou do STDERR
#
# Vrací:
#   Hashref s konfigurací parsovanou z YAML
#   Vrací prázdný hash {} pokud soubor neexistuje nebo nejde přečíst
#
# Chování:
#   1. Zkontroluje, zda soubor existuje a je čitelný
#   2. Pokud soubor obsahuje klíč 'sops', spustí "sops --decrypt $file"
#   3. Parsuje YAML výstup a vrací konfiguraci
#   4. Pokud dešifrování selže, skončí s chybou
#
# Příklady konfigurace:
#   Nešifrovaný soubor (normální YAML):
#     log:
#       destination: /var/log/script.log
#       min_level: info
#     servers:
#       - url: https://zabbix.example.com
#         key: secret_token
#
#   Šifrovaný soubor (s SOPS metadaty):
#     log:
#       destination: /var/log/script.log
#     servers:
#       - url: https://zabbix.example.com
#         key: ENC[AES256_GCM,data:...,iv:...] # encrypted field
#     sops:
#       age:
#         - recipient: age1...
#           enc: |
#             -----BEGIN AGE ENCRYPTED FILE-----
#             ...
#             -----END AGE ENCRYPTED FILE-----
#
# SOPS požadavky:
#   - SOPS musí být nainstalován a dostupný v PATH
#   - Privátní klíč musí být dostupný pro dešifrování
#   - Pro AGE šifrování: private key v ~/.config/sops/age/keys.txt
#
sub read_yaml_config( $conf_file, $logger=undef ) {
    if (! -r $conf_file) {
        if ($logger) {
            $logger->error( "soubor $conf_file neexistuje či nejde přečíst" );
        }
        else {
            warn "soubor $conf_file neexistuje či nejde přečíst";
        }
        return {};
    }
    my $yaml = YAML::Tiny->read( $conf_file );
    my $config = $yaml->[0];
    if (defined($config->{sops})) {     # pokud je zašifrován, tak dešifruji
        open my $fh, '-|', "sops --decrypt $conf_file" or die "error opening 'sops --decrypt $conf_file': $!";
        my $data = do { local $/; <$fh> };
        $yaml = YAML::Tiny->read_string($data);
        $config = $yaml->[0];
    }
    return $config;
}

# Vytvoří a konfiguruje Logger::Dispatch objekt pro logování
# Umožňuje logovat na konzolu a/nebo do souboru či syslogu
#
# Parametry:
#   $debug  - volitelný boolean (výchozí undef)
#             pokud true, nastaví level na 'debug', jinak na 'info' nebo 'notice'
#   $config - volitelný hashref s konfigurací logování
#             načtený z konfiguračního souboru pomocí read_yaml_config()
#
# Konfigurace (z $config parametru):
#   $config->{log} = {
#     destination => "syslog" | "/path/to/logfile",
#                   # povinný pro file/syslog logging
#     min_level   => "debug" | "info" | "notice" | "warning" | "error" | "critical",
#                   # minimální úroveň logování (výchozí: info)
#     facility    => "local0" | "local1" | ... | "local7",
#                   # syslog facility (výchozí: local0, pouze pro syslog)
#     ident       => "script_name",
#                   # identifikátor v logu (výchozí: jméno skriptu)
#   }
#
# Vrací:
#   Logger::Dispatch objekt s konfigurovanými výstupy
#
# Logování na konzolu:
#   - Pokud je TERM prostředí definováno (interaktivní režim): level 'info'
#   - Jinak (cron, daemon): level 'notice'
#   - S debug příznakem: vždy 'debug'
#
# Logování do souboru (pokud je $config zadán):
#   - Vytvoří Log::Dispatch::File handler
#   - Přidá timestamp v ISO 8601 formátu
#   - Formát: YYYY-MM-DDTHH:MM:SS+0000 [LEVEL] [IDENT] zpráva
#   - Režim append (pokud soubor existuje, připisuje se)
#   - Příklad:
#     2025-09-10T19:02:12+0000	info	ssh_auth_methods	update host server1 (10042)
#
# Logování do syslogu (pokud destination='syslog'):
#   - Vytvoří Log::Dispatch::Syslog handler
#   - Identifikátor (ident) se přidá k syslog zprávám
#   - Facility určuje, kam se zprávy v syslogu ukončí (local0-7)
#
# Příklady použití:
#   # Jen konzola
#   my $logger = get_logger();
#   $logger->info("Starting script");
#
#   # Jen debug režim
#   my $logger = get_logger(1);
#   $logger->debug("Detailed information");
#
#   # Soubor + konzola
#   my $config = read_yaml_config('config.yaml');
#   my $logger = get_logger(0, $config);
#   $logger->info("Data logged to file");
#
#   # Syslog + konzola
#   my $logger = get_logger(0, { log => { destination => 'syslog' } });
#
sub get_logger ( $debug = undef, $config = undef ) {

    my $log_min_level = defined($ENV{TERM}) ? 'info' : 'notice';
    $log_min_level = 'debug' if $debug;
    my $logger = Log::Dispatch->new(
        outputs => [
            [ 'Screen', min_level => $log_min_level, stderr => 1, newline => 1 ],
        ],
    );

    if ($config and defined( $config->{log}->{destination} ) ) {
        my $ident = $config->{log}->{ident};
        if (! $ident) {
            my ( $script_name, $path, $suffix ) = fileparse( $0, qr{\.[^.]*$} );
            $ident = basename( $script_name );
        }
        if ($config->{log}->{destination} eq 'syslog') {
            $logger->add(
                Log::Dispatch::Syslog->new(
                    min_level => $config->{log}->{min_level} // 'info',
                    facility  => $config->{log}->{facility}  // 'local0',
                    ident     => $ident,
                )
            );
        }
        else {
            $logger->add(
                Log::Dispatch::File->new(
                    name      => 'file1',
                    min_level => $config->{log}->{min_level} // 'info',
                    filename  => $config->{log}->{destination},
                    #binmode => ':encoding(UTF-8)',
                    newline => 1,
                    #close_after_write => 1,
                    mode => 'append',
                    callbacks => sub {my %p=@_; return join("\t",strftime('%Y-%m-%dT%H:%M:%S%z', localtime), $p{level}, $ident, $p{message})}
                )
            );
        }
    };

    return $logger;
}

1;
