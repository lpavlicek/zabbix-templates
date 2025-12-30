#!/usr/bin/perl

use 5.026;
use strict;
use warnings FATAL => 'all';
use utf8;
use open qw( :std :encoding(UTF-8) );
use feature qw(signatures);
no warnings qw(experimental::signatures); # W: Warnings disabled

use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use File::Basename;
use JSON qw( decode_json encode_json );
use Net::DNS;
use Socket qw(inet_pton inet_ntop AF_INET6 AF_INET);
use List::Util qw /uniq/;

use lib dirname(__FILE__);
use lib 'lib/';

use Zabbix;
use ZabbixUtils qw ( read_yaml_config get_logger );

my $opt_debug     = 0;
my $opt_conf_file = 'conf/ssh.auth_methods.yaml';
my $opt_help      = 0;

GetOptions(
	'config=s' => \$opt_conf_file,
	'debug'    => \$opt_debug,
	'help'     => \$opt_help
) or pod2usage(1);
pod2usage( -verbose => 2 ) if $opt_help;

my ( $script_name, $path, $suffix ) = fileparse( $0, qr{\.[^.]*$} );          

my $logger = get_logger( $opt_debug );                                                                              
                                                                              
my $config = read_yaml_config( $opt_conf_file, $logger );                     
$logger = get_logger( $opt_debug, $config );

_main();
exit;

# Hlavní funkce skriptu
# Iteruje přes všechny Zabbix servery definované v konfiguraci,
# pro každý server načte hostitele s danou šablonou a provede SSH testy
sub _main {

    for my $server ( @{$config->{ servers }} ) {
        my $fisadm = new Zabbix( $server->{url}, $server->{key} );
        #my ($version, $error2) = $fisadm->apiinfo_version;
        my $hosts = get_ssh_hosts($fisadm, $config->{template_name} );
        $logger->info( sprintf 'zabbix server \'%s\', get %s hosts', $server->{url}, scalar(@$hosts) );
        for my $host (@$hosts) {
            #say Dumper($host);
            my $response = {};
            my @ssh_checks = ();
            my $ssh_available = 0;
            for my $ip (@{$host->{ips}}) {
                my $ssh_check = host_ssh_auth_check($ip, $host->{macros}->{'ssh.port'} // 22);
                push @ssh_checks, $ssh_check;
                if ($ssh_check->{available}) {
                    $ssh_available = 1;
                }
            }
            #@ssh_checks = uniq @ssh_checks;  # toto je zbytečné, neboť unikátní jsou již $host->{ips}
            $response->{ssh_checks} = \@ssh_checks;
            if ($ssh_available) {   # TODO: nejen když je available
                $response->{sshfp_record} = test_sshfp($host->{fqdn}, $host->{macros}->{'ssh.port'} // 22);
            }
            my $json_value = encode_json( $response );
            #say "value = $json_value";
            my $params = [
                { host => $host->{host}, key => $config->{push_key}, value=> $json_value },
            ];
            my $error = $fisadm->history_push($params);
            if ($error) {
                $logger->warn(sprintf 'update host %s (%s) with error: %s',$host->{name} // '', $host->{host} // '', $error );
                #say Dumper($params, $host);
            }
            else {
                $logger->info(sprintf 'update host %s (%s), ssh_available: %s, ips: %s, sshfp_exists: %s (%s)', $host->{name}, $host->{host}, $ssh_available, scalar(@ssh_checks), $response->{sshfp_record}->{exists} // 'bad', $response->{sshfp_record}->{dns_name} // '???' );
            }
        }
    }

}

# Načte hosty z Zabbix serveru podle šablony
# 
# Parametry:
#   $zabbix       - objekt Zabbix API klienta
#   $template_name - název šablony, podle níž se filtrují hostitel
#
# Vrací:
#   Referenci na pole hashů s informacemi o hostech (hostid, name, host, macros, ips, fqdn)
#
sub get_ssh_hosts ($zabbix, $template_name) {
    
    my $template = $zabbix->template_get2($template_name);
#$VAR1 = {
#          'macros' => {
#                        'ssh.port' => '22'
#                      },
#          'templateid' => '11080',
#          'name' => 'SSH authentication methods'
#        };

    my $params = {
        output =>  [ 'hostid', 'host', 'name' ],
        selectInterfaces =>  [ 'interfaceid', 'ip', 'dns', 'useip' ],
        #selectParentTemplates => [ 'templateid', 'name' ],
        templateids => $template->{templateid},
        #selectMacros => 'extend',
        selectMacros => [ 'macro', 'value' ],
        filter  => { 
            status => 0         # jen enabled hosts
        },
    };
    my ($result, $error) = $zabbix->host_get($params);

    my @hosts = ();
	for my $host (@$result) {
        my $host2 = {
            hostid => $host->{hostid},
            name   => $host->{name},
            host   => $host->{host},
        };
        for my $tmacro (keys %{$template->{macros}} ) {
            $host2->{macros}->{$tmacro} = $template->{macros}->{$tmacro};
        }
        for my $macro (@{$host->{macros}}) {
            my $macro_name = lc($macro->{macro});
            $macro_name =~ s/^{\$//;
            $macro_name =~ s/}$//;
            $host2->{macros}->{$macro_name} = $macro->{value};
        }
        # IP adresy
        my @ips = ();
        my $fqdn;
        for my $intf (@{$host->{interfaces}}) {
            if ($intf->{useip}) {
                my $ip = $intf->{ip};
                next if ($ip eq '::1' or $ip =~ /^127\./);
                push @ips, normalize_ip($ip);
            }
            else {
                my @dns_ip = get_ip_addresses($intf->{dns});
                push @ips, @dns_ip;
                if (! $fqdn and @dns_ip) {
                    $fqdn = $intf->{dns};
                }
            }
            @ips = uniq ( @ips );
            $host2->{ips} = \@ips;
            if (! $fqdn ) {
                $fqdn = ip_to_fqdn (@ips);
                if (! $fqdn) {
                    my $fqdn = name_to_fqdn($host->{name});
                    if (! $fqdn) {
                        $fqdn = $host->{name};
                    }
                }
            }
            $host2->{fqdn} = $fqdn;
        }
	    push @hosts, $host2;
    }
    #say Dumper(@hosts);
    return \@hosts;
}

# Rozlišuje DNS jméno a vrací pole IP adres (IPv4 a IPv6)
#
# Parametry:
#   $hostname - DNS jméno k rozlišení
#
# Vrací:
#   Pole IP adres (normalizovaných IPv6 adres), prázdné pole pokud nejsou nalezeny
#
sub get_ip_addresses {
    my ($hostname) = @_;
    my @ip_addresses = ();

    # Vytvoření resolveru
    my $resolver = Net::DNS::Resolver->new;

    # Dotaz na A záznamy (IPv4)
    my $a_query = $resolver->query($hostname, 'A');
    if ($a_query) {
        foreach my $rr ($a_query->answer) {
            next unless $rr->type eq 'A';
            push @ip_addresses, $rr->address;
        }
    }

    # Dotaz na AAAA záznamy (IPv6)
    my $aaaa_query = $resolver->query($hostname, 'AAAA');
    if ($aaaa_query) {
        foreach my $rr ($aaaa_query->answer) {
            next unless $rr->type eq 'AAAA';
            push @ip_addresses, normalize_ip($rr->address);
        }
    }

    # Vrací pole unikátních IP adres, pokud žádné nejsou nalezeny, vrací prázdné pole
    return @ip_addresses;
}

# Testuje dostupnost SSH na daném hostu a zjišťuje dostupné autentizační metody
#
# Metodologií: spustí ssh příkaz s kombinací voleb, která:
#   - Deaktivuje interaktivní prvky (Batchmode=yes)
#   - Přeskakuje ověření klíče hostitele
#   - Zakázuje všechny identity a certifikáty
#   - Vyžaduje specifické (neexistující) uživatelské jméno
#   Výstup SSH v debug režimu ukazuje dostupné autentizační metody
#
# Parametry:
#   $hostip - IP adresa hostitele k testování
#   $port   - SSH port (výchozí 22)
#
# Vrací:
#   Hashref se strukturou:
#     {
#       ip_address => "IP_ADRESA",
#       available => true|false,
#       authentication_methods => ["password", "publickey", ...]  # pouze pokud dostupné
#     }
#
sub host_ssh_auth_check ( $hostip, $port = 22 ) {
    my $ssh_check = {
        ip_address => $hostip,
        available  => JSON::false
    };
    my @cmd = qw(/usr/bin/ssh -v -n -F none
                    -o Batchmode=yes
                    -o StrictHostKeyChecking=no
                    -o UserKnownHostsFile=/dev/null
                    -o PreferredAuthentications=no
                    -o IdentityFile=/dev/null
                    -o IdentityAgent=none
                    -o CertificateFile=/dev/null
                    -o ConnectTimeout=5
                    );
    push @cmd, '-p', $port;
    push @cmd,'DOES_NOT_EXIST@' . $hostip, '2>&1';
    if ($opt_debug) { say join ' ',@cmd; };
    open (my $fh, '-|', join (' ', @cmd)) or die "Can't start /usr/bin/ssh: $!";
    while (<$fh>) {
        chomp;
        if (/debug1: Authentications that can continue:\s+(?<methods>.*)\s+$/) {
            $ssh_check->{authentication_methods} = 
            my @methods = ();
            push @methods, split ',', $+{methods};
            $ssh_check->{authentication_methods} = \@methods;
            $ssh_check->{available} = JSON::true;
            $logger->debug( join (' ', $hostip . ':', @methods) ) if $opt_debug;
        }
        elsif (/debug1: connect to address .*: Connection refused/) {
            # TODO
            #push @methods, 'connection_refused';
        }
    }
    close $fh;
    return $ssh_check;
}

# Testuje SSHFP DNS záznamy a porovnává je s veřejnými klíči na hostiteli
#
# Parametry:
#   $fqdn - plně kvalifikované jméno domény hostitele
#   $port - SSH port (výchozí 22)
#
# Vrací:
#   Hashref se strukturou:
#     {
#       exists => true|false,                    # existují SSHFP záznamy?
#       dns_name => "dns.jméno",
#       dns_keys => [
#         {
#           algorithm => "rsa"|"ed25519"|"ecdsa",
#           fp => "OTISK",                        # fingerprint
#           fptype => 1|2,                        # 1=SHA1, 2=SHA256
#           in_sshfp => 1|0,                      # je v SSHFP záznamu?
#           on_host => 1|0                        # je na hostiteli?
#         },
#         ...
#       ],
#       keys_match => true|false                  # všechny klíče se shodují?
#     }
#
sub test_sshfp ($fqdn, $port = 22) {
    my $response = {
        exists => JSON::false,
        dns_name => $fqdn,
        keys_match => JSON::true,
    };
    my $resolver = Net::DNS::Resolver->new();
    my $reply = $resolver->query( $fqdn, 'SSHFP' );
    if (! $reply) {
        return $response;
    }
    $response->{exists} = JSON::true;

    my @sshfp_keys = ();
    my $scan_keys  = host_ssh_keyscan($fqdn);
    foreach my $rr ($reply->answer) {
        next unless $rr->type eq 'SSHFP';
        my $key = {
            fp          => $rr->fp,
            fptype      => $rr->fptype,
            algorithm   => $rr->algorithm,
            in_sshfp    => 1,
        };

        if ($rr->fptype == 2 and $scan_keys->{$rr->algorithm} and lc($scan_keys->{$rr->algorithm}) eq lc($rr->fp)) {
            $key->{on_host} = 1;
            delete $scan_keys->{$rr->algorithm};
        }
        else {
            $key->{on_host} = 0;
            $response->{keys_match} = JSON::false;
        }
        push @sshfp_keys, $key;
    }
    for my $algorithm (keys %$scan_keys) {
        my $key = {
            fp          => $scan_keys->{$algorithm},
            fptype      => 2,
            algorithm   => $algorithm,
            in_sshfp    => 0,
            on_host     => 1,
        };
        push @sshfp_keys, $key;
        $response->{keys_match} = JSON::false;
    }
    $response->{dns_keys} = \@sshfp_keys;
    return $response;
}

# Skenuje veřejné SSH klíče hostitele pomocí ssh-keyscan
# Filtruje na SHA256 otisk (fptype=2) a ignoruje SHA1 (fptype=1)
#
# Poznámka: Aktuálně funguje pouze s IPv4 (-4 příznak)
#
# Parametry:
#   $host - DNS jméno nebo IP adresa hostitele
#   $port - SSH port (výchozí 22)
#
# Vrací:
#   Hashref mapující algoritmus na SHA256 otisk: { "1" => "...", "3" => "...", ... }
#   kde klíč je číslo algoritmu (1=RSA, 3=ECDSA, atd.)
#
sub host_ssh_keyscan ($host, $port = 22) {
    my $keys = {};
    my @cmd = qw(/usr/bin/ssh-keyscan -4 -D); 
    push @cmd, '-p', $port, $host, '2>&1';
    if ($opt_debug) { $logger->debug( join ' ', @cmd ); };
    open (my $fh, '-|', join (' ', @cmd)) or die "Can't start /usr/bin/ssh-keyscan: $!";
    while (<$fh>) {
        chomp;
        # ; test1.example.cz:22 SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u1
        # test1.example.cz IN SSHFP 3 1 b7d72e7a03960c64148c91e6b9525a901e4ad97e
        # test1.example.cz IN SSHFP 3 2 3d924c7fb63d90d2c29a372a548943777be8cde042c10790aae46e3bcf197a9a
        if (/^(?<hostname>\S+)\s+IN\s+SSHFP\s+(?<algorithm>\d+)\s+(?<fptype>\d+)\s+(?<fp>[0-9a-fA-F]+)$/) {
            next if ($+{fptype} == 1);
            $keys->{$+{algorithm}} = $+{fp};
            $logger->debug( $_ ) if $opt_debug;
        }
    }
    close $fh;
    return $keys;
}

# Normalizuje IPv6 adresy do standardní notace
# Převádí komprimované formy (2001:718:1e02:18::106) na plné formy (2001:718:1e02:18:0:0:0:106)
# a naopak. Zabraňuje redundantnímu testování stejné IP adresy v různých formátech.
#
# Parametry:
#   $ip - IPv4 nebo IPv6 adresa
#
# Vrací:
#   IPv4 adresa bez změny, IPv6 adresa v normalizované notaci
#
sub normalize_ip ($ip) {
    if ($ip =~ /:/) {
        return inet_ntop (AF_INET6, inet_pton (AF_INET6, $ip))
    }
    return $ip;
}

# Zjišťuje FQDN pomocí reverse DNS lookup (PTR záznamy) k IP adresám
# Vrací první nalezené FQDN
#
# Parametry:
#   @ips - seznam IP adres k testování
#
# Vrací:
#   FQDNString nebo undef pokud není nalezen
#
sub ip_to_fqdn ( @ips ) {
    for my $ip (@ips) {
        my ($ptr) = rr($ip);
        if ($ptr) {
            return $ptr->ptrdname;
        }
    }
}

# Zjišťuje FQDN podle reverse DNS lookup
# Pokud se nepodaří reverse lookup, vrací normalizované jméno z DNS
#
# Parametry:
#   $name - hostname nebo IP adresa
#
# Vrací:
#   FQDN String nebo undef pokud není nalezen
#
sub name_to_fqdn ( $name ) {
	my ($rr) = rr($name);
	if ($rr) {
		return $rr->name;
	}
}
