package PVE::IntegrityControl::Checker;

use strict;
use warnings;

use DDP;
use Net::SSLeay;
use PVE::QemuConfig;
use PVE::Cluster;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Log qw(debug error info);

my $digest = 0;

sub __init_openssl_gost_engine {
    debug(__PACKAGE__, "\"__init_openssl_gost_engine\" was called");

    my $engine = Net::SSLeay::ENGINE_by_id("gost");
    debug(__PACKAGE__, "\"__init_openssl_gost_engine\" value corresponding to GOST engine: $engine");

    die "failed to obtain GOST engine handler" if !$engine;

    # 0x0080 magic constant means ENGINE_METHOD_DIGESTS
    if (!Net::SSLeay::ENGINE_set_default($engine, 0x0080)) {
        error(__PACKAGE__, "\"__init_openssl_gost_engine\" failed to set GOST engine digests method");
        die "Faield to set up " . __PACKAGE__ . " environment";
    }

    Net::SSLeay::load_error_strings();
    Net::SSLeay::OpenSSL_add_all_algorithms();
    my $available_digests = Net::SSLeay::P_EVP_MD_list_all();

    debug(__PACKAGE__, " available digests:\n " . np($available_digests));
    $digest = Net::SSLeay::EVP_get_digestbyname("md_gost12_256");

    die "Failed to obtain GOST engine digest handler" if not $digest;
}

sub __get_hash {
    my ($data) = @_;

    return unpack('H*', Net::SSLeay::EVP_Digest($data, $digest));
}

sub __check_config_file {
    my ($vmid, $expected) = @_;

    debug(__PACKAGE__, "\"__check_config_file\" was called for vmid:$vmid with expected:$expected\n");

    my $raw = __get_config_file_content($vmid);
    my $hash = __get_hash($raw);
    debug(__PACKAGE__, "\"__check_config_file\" hash:$hash");

    if ($expected ne $hash) {
        debug(__PACKAGE__, "\"__check_config_file\" hash mismatch for config file: expected $expected, got $hash");
        die "ERROR: hash mismatch for config file\n";
    }
}

sub __get_config_file_content {
    my ($vmid) = @_;

    debug(__PACKAGE__, "\"__get_config_file_content\" was called for vmid:$vmid");

    my $conf = PVE::QemuConfig->load_current_config($vmid, 1);
    debug(__PACKAGE__, "\"__get_config_file_content\" conf:\n" . np($conf));
    delete $conf->{lock} if $conf->{lock};

    my $raw = PVE::QemuServer::write_vm_config(undef, $conf);
    die "Error read config file for $vmid" if $raw eq '';
    debug(__PACKAGE__, "\"__get_config_file_content\" content\n$raw");

    return $raw;
}

sub __check_grubx_file {
    my $expected = shift;

    debug(__PACKAGE__, "\"__check_grubx_file\" was called with expected:$expected\n");

    my $hash = __get_hash(__get_grubx_file_content());

    if ($expected ne $hash) {
        debug(__PACKAGE__, "\"__check_grubx_file\" hash mismatch for 'grubx64.efi' file: expected $expected, got $hash");
        die "ERROR: hash mismatch for 'grubx64.efi' file\n";
    }
}

sub __get_grubx_file_content {

    debug(__PACKAGE__, "\"__get_grubx_file_content\"");

    my @files = PVE::IntegrityControl::GuestFS::find("/boot/efi");
    for my $file (@files) {
        next if not $file =~ m|grubx64.efi$|;
        debug(__PACKAGE__, "\"__get_grubx_file_content\" found 'grubx64.efi' file");
        return PVE::IntegrityControl::GuestFS::read("/boot/efi/$file");
    }

    die "Failed to find 'grubx64.efi' file\n";
}

sub __check_input {
    my $vmid = shift;

    die "Passed vmid [$vmid] is not valid\n" if not $vmid =~ m/^\d+$/;
}

sub check {
    my ($vmid) = @_;

    __check_input($vmid);

    debug(__PACKAGE__, "\"check\" was called with params vmid:$vmid");

    __init_openssl_gost_engine() if not $digest;

    my %db;
    eval {%db = %{PVE::IntegrityControl::DB::load($vmid)}};
    if ($@) {
        error(__PACKAGE__, "intergrity control objects are not defined");
        die $@;
    }

    my $mounted = 0;
    my $mount = sub {
        PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);
        $mounted = 1;
    };

    foreach my $entry (sort keys %db) {
        if ($entry eq 'config') {
            __check_config_file($vmid, $db{config});
        } elsif ($entry eq 'bios') {
            &$mount() if not $mounted;
            __check_grubx_file($db{bios});
        } elsif ($entry eq 'files') {
            foreach my $partition (keys %{$db{$entry}}) {
                foreach my $path (keys %{$db{$entry}{$partition}}) {
                    &$mount() if not $mounted;
                    my $raw = PVE::IntegrityControl::GuestFS::read2("$partition:$path");
                    my $hash = __get_hash($raw);
                    if ($db{$entry}{$partition}{$path} ne $hash) {
                        debug(__PACKAGE__, "\"check\" hash mismatch for $partition:$path: expected $db{$entry}{$partition}{$path}, got $hash");
                        die "ERROR: hash mismatch for $partition:$path\n";
                    }
                }
            }
        }
    }

    PVE::IntegrityControl::GuestFS::umount_vm_disks() if $mounted;

    info(__PACKAGE__, "\"check\" passed successfully");

    return 0;
}

sub fill_db {
    my ($vmid) = @_;

    __check_input($vmid);

    debug(__PACKAGE__, "\"fill_db\" was called with params vmid:$vmid");

    __init_openssl_gost_engine() if not $digest;

    my $db = PVE::IntegrityControl::DB::load($vmid);

    my $mounted = 0;
    my $mount = sub {
        PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);
        $mounted = 1;
    };

    foreach my $entry (keys %$db) {
        if ($entry eq 'config') {
            next if $db->{config} ne 'UNDEFINED';
            $db->{config} = __get_hash(__get_config_file_content($vmid));
        } elsif ($entry eq 'bios') {
            next if $db->{bios} ne 'UNDEFINED';
            &$mount() if not $mounted;
            $db->{bios} = __get_hash(__get_grubx_file_content());
        } elsif ($entry eq 'files') {
            foreach my $partition (keys %{$db->{$entry}}) {
                foreach my $path (keys %{$db->{$entry}->{$partition}}) {
                    next if $db->{$entry}->{$partition}->{$path} ne 'UNDEFINED';
                    &$mount() if not $mounted;
                    $db->{$entry}->{$partition}->{$path} =
                        __get_hash(PVE::IntegrityControl::GuestFS::read2("$partition:$path"));
                }
            }
        }
    }

    PVE::IntegrityControl::DB::write($vmid, $db);
    PVE::IntegrityControl::GuestFS::umount_vm_disks() if $mounted;
}

1;
