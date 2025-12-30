# Perl modul pro komunikaci se Zabbix monitorovacím systémem
#
# Umožňuje posílání dat do Zabbix serveru přes JSON-RPC API.
# Podporuje autentizaci pomocí API tokenů.
#
# Copyright (C) 2025- Lubos Pavlicek <pavlicek@vse.cz>
#
#

package Zabbix;

use Exporter;
@ISA = qw(Exporter);
#@EXPORT_OK = qw(file_to_list_of_regexps file_to_list_of_globs);

use 5.024;
use strict;

use warnings FATAL => 'all';
use utf8;
use open qw( :std :encoding(UTF-8) );
use feature qw(signatures);
no warnings qw(experimental::signatures); # W: Warnings disabled

use Data::Dumper;
#use Net::Domain qw(hostfqdn);
use JSON qw( decode_json encode_json );
#use Crypt::JWT qw(encode_jwt);
use LWP::UserAgent;
use Log::Dispatch;

use Encode 'encode';

=head1 NAME

Zabbix.pm -- Perl modul pro komunikaci se Zabbix API

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00';

=head1 SYNOPSIS

 use Zabbix;
 my $zabbix = new Zabbix( 
    'https://fisadm.vse.cz/zabbix/api_jsonrpc.php',
    '7d817d319e990be01d2d95366778a7b5643e726d6bac7a71932d0902b3bd71df'
 );
 
 my ($hosts, $error) = $zabbix->host_get({ 
    output => ['hostid', 'name'],
    limit => 10
 });

=head1 DESCRIPTION

Modul Zabbix.pm poskytuje jednoduché rozhraní pro komunikaci se 
Zabbix serverem přes JSON-RPC API. Zprostředkovává autentizaci,
odesílání dotazů a zpracování odpovědí.

=cut

# Konstruktor - vytvoří nový objekt Zabbix API klienta
#
# Parametry:
#   $class     - jméno třídy (automaticky předáno při volání new)
#   $api_url   - URL Zabbix API endpoint (povinný)
#                příklad: 'https://zabbix.example.com/api_jsonrpc.php'
#   $api_token - Zabbix API token pro autentizaci (povinný)
#                lze získat z Settings > API tokens v Zabbix UI
#   $logger    - volitelný Logger::Dispatch objekt pro logování
#                pokud není zadán, vytvoří se výchozí logger
#
# Vrací:
#   Objekt Zabbix s inicializovaným HTTP klientem a konfigurací
#
# Vyvolá chybu, pokud chybí povinné parametry (api_url nebo api_token)
#
sub new ($class, $api_url, $api_token, $logger=undef)
{
    #my $error_msg = '';
    my $o = {};
    bless $o, $class;

    $o->{api_url} = $api_url;
    $o->{api_token} = $api_token;
    if (! $api_url) {
        die 'Chybí povinný parametr "api_url"';
    }
    if (! $api_token) {
        die 'Chybí povinný parametr "api_token"';
    }
    if ($logger) {
        $o->{logger} = $logger;
    }
    else {
        $o->{logger} = Log::Dispatch->new(
            outputs => [
                [ 'Screen', min_level => 'notice', stderr => 1, newline => 1 ],
            ],
        );
    }
    my $ua = LWP::UserAgent->new(timeout => 5);
    $o->{ua}        = $ua;

    return $o;
}

# Získá verzi Zabbix API
# Slouží jako jednoduchý test dostupnosti API bez autentizace
#
# Vrací:
#   Seznam: ($version_string, $error_hashref)
#   Při úspěchu: ($version_string, undef)
#   Při chybě: (undef, { http_code => ..., http_message => ... })
#
#   Příklad úspěšné odpovědi: ('6.0.15', undef)
#
sub apiinfo_version ($self) {
    $self->_post_json('apiinfo.version', {}, 0);
}

# Získá seznam hostů ze Zabbix serveru
# Hlavní metoda pro filtrování a vyhledávání hostů dle různých kritérií
#
# Parametry:
#   $self   - Zabbix objekt (automaticky předáno)
#   $params - Hashref s parametry dotazu:
#     Příklady:
#       { output => ['hostid', 'host', 'name'],
#         filter => { status => 0 },
#         limit => 100
#       }
#       { output => ['hostid'],
#         selectInterfaces => ['ip', 'dns'],
#         templateids => '10001'
#       }
#
# Vrací:
#   Seznam: ($result_arrayref, $error_hashref)
#   Při úspěchu: ($hosts_arrayref, undef)
#   Při chybě: (undef, { error => 'chyba_zpráva' })
#
# Podrobnosti na: https://www.zabbix.com/documentation/current/en/api/reference/host/get
#
sub host_get ($self, $params) {
    return $self->_post_json('host.get', $params);
}

# Získá seznam šablon ze Zabbix serveru
# Šablony obsahují definice itemů, triggerů a maker, které se vztahují na hosty
#
# Parametry:
#   $self   - Zabbix objekt (automaticky předáno)
#   $params - Hashref s parametry dotazu:
#     Příklady:
#       { output => ['templateid', 'name'],
#         filter => { name => 'Linux servers' }
#       }
#       { output => ['templateid'],
#         selectMacros => ['macro', 'value']
#       }
#
# Vrací:
#   Seznam: ($result_arrayref, $error_hashref)
#   Při úspěchu: ($templates_arrayref, undef)
#   Při chybě: (undef, { error => 'chyba_zpráva' })
#
# Podrobnosti na: https://www.zabbix.com/documentation/current/en/api/reference/template/get
#
sub template_get ($self, $params) {
    return $self->_post_json('template.get', $params);
}

# Získá jednu konkrétní šablonu podle jména a vrací již zpracovanou strukturu
# Toto je wrapper okolo template_get(), který filtruje a normalizuje výstup
#
# Parametry:
#   $self          - Zabbix objekt (automaticky předáno)
#   $template_name - Jméno hledané šablony (string)
#
# Vrací:
#   Hashref se strukturou:
#     {
#       name       => "Jméno šablony",
#       templateid => "10042",
#       macros     => {
#         "ssh.port" => "22",
#         "smtp.server" => "mail.example.com",
#         ...
#       }
#     }
#
# Poznámka: Maker jsou převedeny z formátu {$MACRO.NAME} na lowercase klíče
#           se zabranými znaky, např. {$SSH.PORT} -> ssh.port
#
# Vyvolá chybu, pokud šablona není nalezena
#
#$VAR1 = [
#          {
#            'macros' => [
#                          {
#                            'value' => '22',
#                            'macro' => '{$SSH.PORT}'
#                          }
#                        ],
#            'name' => 'SSH authentication methods',
#            'templateid' => '11080'
#          }
#        ];

sub template_get2 ($self, $template_name) {
    my $params = {
        output => ['templateid', 'name'],
        selectMacros => [ 'macro', 'value' ],
        filter => {
            name => [$template_name],
        }
    };
    my ($result, $error) = $self->template_get($params);
    #say Dumper($result, $error);
    my $templ = shift (@$result);
    my $template->{name}       = $templ->{name};
    $template->{templateid} = $templ->{templateid};
    for my $macro (@{$templ->{macros}}) {
        my $macro_name = lc($macro->{macro});
        $macro_name =~ s/^{\$//;
        $macro_name =~ s/}$//;
        $template->{macros}->{$macro_name} = $macro->{value};
    }

    return $template
}

# Odešle historické údaje do Zabbix serveru (history.push API metoda)
# Umožňuje přímé vkládání custom metriky bez potřeby agenta
#
# Parametry:
#   $self   - Zabbix objekt (automaticky předáno)
#   $params - Arrayref s hashrefs obsahujícími data:
#     Struktura jedné položky:
#       {
#         host => "hostname",           # jméno nebo IP hostitele
#         key => "custom.metric.key",   # klíč položky (item key)
#         value => "hodnota",           # hodnota k uložení (JSON string pro komplexní data)
#         # volitelně:
#         clock => 1632000000           # Unix timestamp (výchozí: aktuální čas)
#       }
#
#     Příklad:
#       [
#         { host => 'server1', key => 'ssh.auth.methods', value => '{"available":true}' },
#         { host => 'server2', key => 'backup.status', value => 'ok' }
#       ]
#
# Vrací:
#   Chybový message (string) pokud došlo k chybě
#   undef pokud bylo vše úspěšné
#
# Poznámka: Vrací první nalezenou chybu - nemusí obsahovat ALL chyby
#
sub history_push ($self, $params) {
    my ($result, $error) = $self->_post_json('history.push', $params);
    if ($error) {
        return $error;
    }
    for my $data (@{ $result->{data} }) {
        if ($data->{error}) {
            return $data->{error};
        }
    }
    return;
}

# Interní pomocná metoda pro komunikaci se Zabbix API
# Formuluje JSON-RPC 2.0 dotaz, odešle ho HTTP POST a zpracuje odpověď
#
# Parametry:
#   $self   - Zabbix objekt (automaticky předáno)
#   $method - Jméno API metody (string), např. 'host.get', 'history.push'
#   $params - Hashref s parametry pro API metodu
#   $auth   - Volitelný boolean (výchozí 1), zda přidat autentizační token
#             nastavit na 0 pro metody, které nevyžadují autentizaci
#             (např. apiinfo.version)
#
# Vrací:
#   Seznam: ($result, $error)
#   Při úspěchu: ($result_hashref, undef)
#     kde $result je výsledek z odpovědi API (result pole)
#   Při chybě: (undef, $error_hashref)
#     kde $error obsahuje:
#       http_code => HTTP kód (např. 401, 500)
#       http_message => HTTP zpráva (např. "Unauthorized")
#     nebo Zabbix API error odpověď
#
# Technické detaily:
#   - Konstruuje JSON-RPC 2.0 request
#   - Přidává Bearer token do Authorization headeru (pokud $auth=1)
#   - Odesílá HTTP POST do $self->{api_url}
#   - Dekóduje JSON odpověď a vrací result/error pole
#
sub _post_json ($self, $method, $params, $auth = 1) {

    my $request = {
        jsonrpc => '2.0',
        method  => $method,
        params  => $params,
        id      => 1,
    };
    my $json = encode_json($request);
    #say Dumper($json);
    my %headers = (
        'Content-Type' => 'application/json',
        Accept         => 'application/json',
    );
    if ($auth) {
        $headers{Authorization} = 'Bearer ' . $self->{api_token};
    };

    my $response = $self->{ua}->post( $self->{api_url}, %headers, Content => $json );

    #say Dumper($response);
    if (! $response->is_success) {
        #$self->{logger}->error("ERROR: " . $response->status_line);
        return (undef, { http_code => $response->code, http_message => $response->message });
    }

    my $return = decode_json ($response->decoded_content);
    return ($return->{result}, $return->{error});
}
