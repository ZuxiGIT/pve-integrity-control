package PVE::IntegrityControl::Checker;

use strict;
use warnings;

use DDP;
use Net::SSLeay;
use PVE::QemuConfig;
use PVE::Cluster;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Log qw(debug error info trace);

my $digest = 0;

my $try = sub {
    my $sub = shift;

    my $res;
    eval { $res = &$sub(@_); };
    if ($@) {
        error(__PACKAGE__, $@);
        die "Internal error occured\n";
    }
    return $res;
};

sub __init_openssl_gost_engine {
    trace(__PACKAGE__, "\"__init_openssl_gost_engine\" was called");

    my $engine = Net::SSLeay::ENGINE_by_id("gost");

    die "Failed to initialize GOST engine handler\n" if not $engine;
    debug(__PACKAGE__, "GOST engine handler: $engine");

    # 0x0080 magic constant means ENGINE_METHOD_DIGESTS
    if (!Net::SSLeay::ENGINE_set_default($engine, 0x0080)) {
        die "Faield to set up " . __PACKAGE__ . " environment\n";
    }

    Net::SSLeay::load_error_strings();
    Net::SSLeay::OpenSSL_add_all_algorithms();
    my $available_digests = Net::SSLeay::P_EVP_MD_list_all();

    debug(__PACKAGE__, " available digests:\n " . np($available_digests));
    $digest = Net::SSLeay::EVP_get_digestbyname("md_gost12_256");

    die "Failed to initialize GOST engine digest handler\n" if not $digest;
}

sub __get_hash {
    my ($data) = @_;

    trace(__PACKAGE__, "\"__get_hash\" was called");

    return unpack('H*', Net::SSLeay::EVP_Digest($data, $digest));
}

sub __check_config_file {
    my ($vmid, $expected) = @_;

    trace(__PACKAGE__, "\"__check_config_file\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "expected:$expected");

    my $raw = __get_config_file_content($vmid);
    my $hash = __get_hash($raw);
    debug(__PACKAGE__, "computed config file hash:$hash");

    if ($expected ne $hash) {
        error(__PACKAGE__, "Hash mismatch for config file: expected $expected, got $hash");
        die "ERROR: hash mismatch for config file\n";
    }
}

sub __get_config_file_content {
    my ($vmid) = @_;

    trace(__PACKAGE__, "\"__get_config_file_content\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    my $conf = PVE::QemuConfig->load_current_config($vmid, 1);
    delete $conf->{lock} if $conf->{lock};
    debug(__PACKAGE__, "config file content:\n" . np($conf));

    my $raw = PVE::QemuServer::write_vm_config(undef, $conf);
    die "Error generating raw config for $vmid" if $raw eq '';
    debug(__PACKAGE__, "config file raw content:\n$raw");

    return $raw;
}

sub __check_grubx_file {
    my $expected = shift;

    trace(__PACKAGE__, "\"__check_grubx_file\" was called");
    trace(__PACKAGE__, "expected:$expected");

    my $hash = __get_grubx_file_hash();

    if ($expected ne $hash) {
        error(__PACKAGE__, "Hash mismatch for 'grubx64.efi' file: expected $expected, got $hash");
        die "ERROR: hash mismatch for 'grubx64.efi' file\n";
    }
}

sub __get_grubx_file_hash {
    trace(__PACKAGE__, "\"__get_grubx_file_hash\" was called");

    my $partition = &$try(\&PVE::IntegrityControl::GuestFS::find_bootable_partition);
    debug(__PACKAGE__, "bootable partition: $partition");

    PVE::IntegrityControl::GuestFS::mount_partition($partition);

    my $hash;

    my @files = PVE::IntegrityControl::GuestFS::find("/");
    for my $file (@files) {
        next if not $file =~ m|grubx64.efi$|;
        debug(__PACKAGE__, "Found 'grubx64.efi' file: $file");
        $hash = __get_hash(PVE::IntegrityControl::GuestFS::read("/$file"));
        debug(__PACKAGE__, "computed bootloader hash: $hash");
    }

    PVE::IntegrityControl::GuestFS::umount_partition();

    if (not $hash) {
        die "Failed to find bootloader\n";
    }

    return $hash;
}

sub __check_input {
    my $vmid = shift;

    die "Passed vmid [$vmid] is not valid\n" if not $vmid =~ m/^\d+$/;
}

sub check {
    my ($vmid) = @_;

    __check_input($vmid);

    trace(__PACKAGE__, "\"check\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    &$try(\&__init_openssl_gost_engine) if not $digest;

    my %db;
    eval {%db = %{PVE::IntegrityControl::DB::load($vmid)}};
    # FIXME
    if ($@) {
        error(__PACKAGE__, "intergrity control objects are not defined");
        die $@;
    }

    my $launched_gfs = 0;
    my $launch_gfs = sub {
        PVE::IntegrityControl::GuestFS::add_vm_disks($vmid);
        $launched_gfs = 1;
    };

    foreach my $entry (sort keys %db) {
        if ($entry eq 'config') {
            __check_config_file($vmid, $db{config});
        } elsif ($entry eq 'bootloader') {
            &$launch_gfs() if not $launched_gfs;
            __check_grubx_file($db{bootloader});
        } elsif ($entry eq 'files') {
            &$launch_gfs() if keys %{$db{$entry}} and not $launched_gfs;
            foreach my $partition (keys %{$db{$entry}}) {
                PVE::IntegrityControl::GuestFS::mount_partition($partition);
                foreach my $path (keys %{$db{$entry}{$partition}}) {
                    my $expected = $db{$entry}{$partition}{$path};
                    my $raw = PVE::IntegrityControl::GuestFS::read($path);
                    my $hash = __get_hash($raw);
                    if ($expected ne $hash) {
                        error(__PACKAGE__, "Hash mismatch for $partition:$path: expected $expected, got $hash");
                        die "ERROR: hash mismatch for $partition:$path\n";
                    }
                }
                PVE::IntegrityControl::GuestFS::umount_partition();
            }
        }
    }

    info(__PACKAGE__, "Check passed successfully");
    return 0;
}

sub fill_db {
    my ($vmid) = @_;

    __check_input($vmid);

    trace(__PACKAGE__, "\"fill_db\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    &$try(\&__init_openssl_gost_engine) if not $digest;

    my %db = %{PVE::IntegrityControl::DB::load($vmid)};

    my $launched_gfs = 0;
    my $launch_gfs = sub {
        PVE::IntegrityControl::GuestFS::add_vm_disks($vmid);
        $launched_gfs = 1;
    };

    foreach my $entry (keys %db) {
        if ($entry eq 'config') {
            next if $db{config} ne 'UNDEFINED';
            $db{config} = __get_hash(&$try(\&__get_config_file_content, $vmid));
        } elsif ($entry eq 'bootloader') {
            next if $db{bootloader} ne 'UNDEFINED';
            &$launch_gfs() if not $launched_gfs;
            $db{bootloader} = __get_grubx_file_hash();
        } elsif ($entry eq 'files') {
            &$launch_gfs() if keys %{$db{$entry}} and not $launched_gfs;
            foreach my $partition (keys %{$db{$entry}}) {
                PVE::IntegrityControl::GuestFS::mount_partition($partition);
                foreach my $path (keys %{$db{$entry}{$partition}}) {
                    next if $db{$entry}{$partition}{$path} ne 'UNDEFINED';
                    $db{$entry}{$partition}{$path} = __get_hash(PVE::IntegrityControl::GuestFS::read($path));
                }
                PVE::IntegrityControl::GuestFS::umount_partition();
            }
        }
    }

    PVE::IntegrityControl::DB::write($vmid, \%db);

    info(__PACKAGE__, "New objects were added successfully");
}

1;
