#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
use 5.026;

#use Data::Dumper;
use JSON;

my %HIST = (
'histogram.000000.000000.to.000000.000001' => 'histogram.0ms.16ms',
'histogram.000000.000001.to.000000.000002' => 'histogram.0ms.16ms',
'histogram.000000.000002.to.000000.000004' => 'histogram.0ms.16ms',
'histogram.000000.000004.to.000000.000008' => 'histogram.0ms.16ms',
'histogram.000000.000008.to.000000.000016' => 'histogram.0ms.16ms',
'histogram.000000.000016.to.000000.000032' => 'histogram.0ms.16ms',
'histogram.000000.000032.to.000000.000064' => 'histogram.0ms.16ms',
'histogram.000000.000064.to.000000.000128' => 'histogram.0ms.16ms',
'histogram.000000.000128.to.000000.000256' => 'histogram.0ms.16ms',
'histogram.000000.000256.to.000000.000512' => 'histogram.0ms.16ms',
'histogram.000000.000512.to.000000.001024' => 'histogram.0ms.16ms',
'histogram.000000.001024.to.000000.002048' => 'histogram.0ms.16ms',
'histogram.000000.002048.to.000000.004096' => 'histogram.0ms.16ms',
'histogram.000000.004096.to.000000.008192' => 'histogram.0ms.16ms',
'histogram.000000.008192.to.000000.016384' => 'histogram.0ms.16ms',
'histogram.000000.016384.to.000000.032768' => 'histogram.16ms.32ms',
'histogram.000000.032768.to.000000.065536' => 'histogram.32ms.64ms',
'histogram.000000.065536.to.000000.131072' => 'histogram.64ms.128ms',
'histogram.000000.131072.to.000000.262144' => 'histogram.128ms.256ms',
'histogram.000000.262144.to.000000.524288' => 'histogram.256ms.512ms',
'histogram.000000.524288.to.000001.000000' => 'histogram.512ms.1s',
'histogram.000001.000000.to.000002.000000' => 'histogram.1s.2s',
'histogram.000002.000000.to.000004.000000' => 'histogram.2s.4s',
'histogram.000004.000000.to.000008.000000' => 'histogram.4s.512s',
'histogram.000008.000000.to.000016.000000' => 'histogram.4s.512s',
'histogram.000016.000000.to.000032.000000' => 'histogram.4s.512s',
'histogram.000032.000000.to.000064.000000' => 'histogram.4s.512s',
'histogram.000064.000000.to.000128.000000' => 'histogram.4s.512s',
'histogram.000128.000000.to.000256.000000' => 'histogram.4s.512s',
'histogram.000256.000000.to.000512.000000' => 'histogram.4s.512s',
'histogram.000512.000000.to.001024.000000' => 'histogram.4s.512s',
'histogram.001024.000000.to.002048.000000' => 'histogram.4s.512s',
'histogram.002048.000000.to.004096.000000' => 'histogram.4s.512s',
'histogram.004096.000000.to.008192.000000' => 'histogram.4s.512s',
'histogram.008192.000000.to.016384.000000' => 'histogram.4s.512s',
'histogram.016384.000000.to.032768.000000' => 'histogram.4s.512s',
'histogram.032768.000000.to.065536.000000' => 'histogram.4s.512s',
'histogram.065536.000000.to.131072.000000' => 'histogram.4s.512s',
'histogram.131072.000000.to.262144.000000' => 'histogram.4s.512s',
'histogram.262144.000000.to.524288.000000' => 'histogram.4s.512s',

);

my @keys = qw(
histogram.0ms.16ms
histogram.16ms.32ms
histogram.32ms.64ms
histogram.64ms.128ms
histogram.128ms.256ms
histogram.256ms.512ms
histogram.512ms.1s
histogram.1s.2s
histogram.2s.4s
histogram.4s.512s
infra.cache.count
key.cache.count
mem.cache.message
mem.cache.rrset
mem.http.query_buffer
mem.http.response_buffer
mem.mod.iterator
mem.mod.respip
mem.mod.subnet
mem.mod.validator
mem.streamwait
msg.cache.count
num.answer.bogus
num.answer.rcode.FORMERR
num.answer.rcode.nodata
num.answer.rcode.NOERROR
num.answer.rcode.NOTIMPL
num.answer.rcode.NXDOMAIN
num.answer.rcode.REFUSED
num.answer.rcode.SERVFAIL
num.answer.secure
num.query.aggressive.NOERROR
num.query.aggressive.NXDOMAIN
num.query.authzone.down
num.query.authzone.up
num.query.edns.DO
num.query.edns.present
num.query.flags.AA
num.query.flags.AD
num.query.flags.CD
num.query.flags.QR
num.query.flags.RA
num.query.flags.RD
num.query.flags.TC
num.query.flags.Z
num.query.https
num.query.ipv6
num.query.opcode.NOTIFY
num.query.opcode.QUERY
num.query.ratelimited
num.query.subnet
num.query.tcp
num.query.tcpout
num.query.tls
num.query.type.A
num.query.type.AAAA
num.query.type.HTTPS
num.query.type.MX
num.query.type.NS
num.query.type.PTR
num.query.type.SSHFP
num.query.type.SOA
num.query.type.SRV
num.query.type.SVCB
num.query.type.TXT
num.query.type.other
num.query.udpout
num.rrset.bogus
rrset.cache.count
time.up
total.num.cachehits
total.num.cachemiss
total.num.expired
total.num.prefetch
total.num.queries
total.num.queries_cookie_client
total.num.queries_cookie_invalid
total.num.queries_cookie_valid
total.num.queries_discard_timeout
total.num.queries_ip_ratelimited
total.num.queries_timed_out
total.num.queries_wait_limit
total.num.recursivereplies
total.recursion.time.avg
total.recursion.time.median
total.requestlist.avg
total.requestlist.exceeded
total.requestlist.max
total.requestlist.overwritten
unwanted.queries
unwanted.replies
);

my $list = { };
my $error_msg = '';
for my $key (@keys) {
    ( my $_key = $key ) =~ tr /\./_/;
    $list->{$_key} = 0;
}

while(<>) {
    chomp;
    if (/unbound-control.* (?<error>error: .+)$/) {
        $error_msg = $+{error};
    }
    elsif (/\S=\S/) {
        my($key,$value)=split('=');
        if (defined($HIST{$key})) {
            $key = $HIST{$key};
        }
        ( my $_key = $key ) =~ tr /\./_/;
        if ($key =~ /num.query.type.\S+/) {
            if (! defined($list->{$_key})) {
                $key = 'num_query_type_other';
            }
        }
        if (defined($list->{$_key})) {
            $list->{$_key}+=$value;
        }
    }
}

if ($error_msg) {
    $list = {
        error_msg => $error_msg
    };
}

say encode_json($list);
