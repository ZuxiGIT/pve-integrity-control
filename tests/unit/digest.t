use strict;
use warnings;

use Test::More;

BEGIN {
    package DDP;
    sub import {
        no strict 'refs';
        *{caller() . '::np'} = sub { return '' };
    }
    $INC{'DDP.pm'} = __FILE__;

    package Net::SSLeay;
    our $engine_result;
    our $set_default_result;
    our $digest_lookup_result;
    our $digest_result;
    our @calls;

    sub import { return }
    sub ENGINE_by_id {
        push @calls, [ ENGINE_by_id => @_ ];
        return $engine_result;
    }
    sub ENGINE_set_default {
        push @calls, [ ENGINE_set_default => @_ ];
        return $set_default_result;
    }
    sub load_error_strings {
        push @calls, [ load_error_strings => @_ ];
        return;
    }
    sub OpenSSL_add_all_algorithms {
        push @calls, [ OpenSSL_add_all_algorithms => @_ ];
        return;
    }
    sub P_EVP_MD_list_all {
        push @calls, [ P_EVP_MD_list_all => @_ ];
        return ['fake-digest'];
    }
    sub EVP_get_digestbyname {
        push @calls, [ EVP_get_digestbyname => @_ ];
        return $digest_lookup_result;
    }
    sub EVP_Digest {
        push @calls, [ EVP_Digest => @_ ];
        return $digest_result;
    }
    $INC{'Net/SSLeay.pm'} = __FILE__;

    package PVE::IntegrityControl::Log;
    sub import {
        my ($class, @names) = @_;
        my $caller = caller();
        no strict 'refs';
        *{"${caller}::$_"} = sub { return } for @names;
    }
    $INC{'PVE/IntegrityControl/Log.pm'} = __FILE__;
}

use lib '.';
require PVE::IntegrityControl::Digest;

sub reset_fake_ssl {
    $Net::SSLeay::engine_result = 'engine-handle';
    $Net::SSLeay::set_default_result = 1;
    $Net::SSLeay::digest_lookup_result = 'digest-handle';
    $Net::SSLeay::digest_result = '';
    @Net::SSLeay::calls = ();
}

ok(!PVE::IntegrityControl::Digest::is_initialized(), 'Digest starts uninitialized');

reset_fake_ssl();
$Net::SSLeay::engine_result = 0;
my $engine_error = eval {
    PVE::IntegrityControl::Digest::init_openssl_gost_engine();
    return '';
};
$engine_error = $@ if $@;
like($engine_error, qr/^Failed to initialize GOST engine handler/, 'rejects a missing GOST engine');
ok(!PVE::IntegrityControl::Digest::is_initialized(), 'missing engine leaves Digest uninitialized');

reset_fake_ssl();
$Net::SSLeay::set_default_result = 0;
my $default_error = eval {
    PVE::IntegrityControl::Digest::init_openssl_gost_engine();
    return '';
};
$default_error = $@ if $@;
like($default_error, qr/^Faield to set up PVE::IntegrityControl::Digest environment/, 'propagates engine setup failure');
ok(!PVE::IntegrityControl::Digest::is_initialized(), 'setup failure leaves Digest uninitialized');

reset_fake_ssl();
$Net::SSLeay::digest_lookup_result = 0;
my $digest_error = eval {
    PVE::IntegrityControl::Digest::init_openssl_gost_engine();
    return '';
};
$digest_error = $@ if $@;
like($digest_error, qr/^Failed to initialize GOST engine digest handler/, 'rejects a missing GOST digest');
ok(!PVE::IntegrityControl::Digest::is_initialized(), 'missing digest leaves Digest uninitialized');

reset_fake_ssl();
PVE::IntegrityControl::Digest::init_openssl_gost_engine();
ok(PVE::IntegrityControl::Digest::is_initialized(), 'successful initialization stores the digest handle');
is_deeply(
    \@Net::SSLeay::calls,
    [
        [ ENGINE_by_id => 'gost' ],
        [ ENGINE_set_default => 'engine-handle', 0x0080 ],
        [ load_error_strings => () ],
        [ OpenSSL_add_all_algorithms => () ],
        [ P_EVP_MD_list_all => () ],
        [ EVP_get_digestbyname => 'md_gost12_256' ],
    ],
    'initializes the expected engine and md_gost12_256 digest in order',
);

@Net::SSLeay::calls = ();
$Net::SSLeay::digest_result = "\x00\x7f\x80\xff";
is(
    PVE::IntegrityControl::Digest::get_hash("source\x00data"),
    '007f80ff',
    'converts the binary digest to lowercase hexadecimal',
);
is_deeply(
    \@Net::SSLeay::calls,
    [[ EVP_Digest => "source\x00data", 'digest-handle' ]],
    'hashing forwards original bytes and the initialized digest handle',
);

done_testing();
