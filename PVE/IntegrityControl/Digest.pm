package PVE::IntegrityControl::Digest;

use strict;
use warnings;

use DDP;
use Net::SSLeay;
use PVE::IntegrityControl::Log qw(debug trace);

my $digest = 0;

sub init_openssl_gost_engine {
    trace(__PACKAGE__, "\"init_openssl_gost_engine\" was called");

    my $engine = Net::SSLeay::ENGINE_by_id("gost");
    die "Failed to initialize GOST engine handler\n" if not $engine;
    debug(__PACKAGE__, "GOST engine handler: $engine");

    if (!Net::SSLeay::ENGINE_set_default($engine, 0x0080)) {
        die "Faield to set up " . __PACKAGE__ . " environment\n";
    }

    Net::SSLeay::load_error_strings();
    Net::SSLeay::OpenSSL_add_all_algorithms();
    my $available_digests = Net::SSLeay::P_EVP_MD_list_all();
    debug(__PACKAGE__, " available digests:\n " . np($available_digests));
    $digest = Net::SSLeay::EVP_get_digestbyname("md_gost12_256");
    die "Failed to initialize GOST engine digest handler\n" if not $digest;

    trace(__PACKAGE__, "return from \"init_openssl_gost_engine\"");
}

sub is_initialized {
    return $digest ? 1 : 0;
}

sub get_hash {
    my ($data) = @_;
    trace(__PACKAGE__, "\"get_hash\" was called");
    return unpack("H*", Net::SSLeay::EVP_Digest($data, $digest));
}

1;
