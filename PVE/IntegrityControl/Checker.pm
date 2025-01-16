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

    trace(__PACKAGE__, "return from \"__init_openssl_gost_engine\"");
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
        info(__PACKAGE__, "Check not passed");
        die "Hash mismatch for config file\n";
    }
    info(__PACKAGE__, "Config file hash matched");
}

sub __get_config_file_content {
    my ($vmid) = @_;

    trace(__PACKAGE__, "\"__get_config_file_content\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    my $conf = PVE::QemuConfig->load_current_config($vmid, 1);

    # for sure
    delete $conf->{lock} if defined $conf->{lock};

    debug(__PACKAGE__, "config file content:\n" . np($conf));

    my $raw = PVE::QemuServer::write_vm_config(undef, $conf);
    die "Error generating raw config for $vmid" if $raw eq '';
    debug(__PACKAGE__, "config file raw content:\n$raw");

    return $raw;
}

sub __check_mbr_vbr {
    my $mbr_vbr = shift;

    trace(__PACKAGE__, "\"__check_mbr_vbr\" was called");
    trace(__PACKAGE__, "mbr_vbr:\n" . np($mbr_vbr));

    my $dev = (PVE::IntegrityControl::GuestFS::list_devices())[0];

    if ((my $parttype = PVE::IntegrityControl::GuestFS::part_get_parttype($dev)) ne 'msdos') {
        error(__PACKAGE__, "Wrong vm disk partition table type: expected MBR, got '$parttype'");
        die "Failed to check MBR/VBR hash\n";
    }

    foreach my $entry (keys %{$mbr_vbr}) {
        if ($entry eq 'mbr') {
            my $mbr_raw = PVE::IntegrityControl::GuestFS::pread_device($dev, 512, 0);
            my $hash = __get_hash($mbr_raw);
            my $expected = $mbr_vbr->{mbr};
            if ($expected ne $hash) {
                error(__PACKAGE__, "Hash mismatch for MBR: expected $expected, got $hash");
                info(__PACKAGE__, "Check not passed");
                die "Hash mismatch for MBR\n";
            }
            info(__PACKAGE__, "MBR hash matched");
        } elsif ($entry eq 'vbr') {
            my $part = &$try(\&PVE::IntegrityControl::GuestFS::find_bootable_partition);
            debug(__PACKAGE__, "bootable partition info:\n" . np($part));
            my $vbr_raw = PVE::IntegrityControl::GuestFS::pread_device($dev, 512, $part->{part_start});
            my $hash = __get_hash($vbr_raw);
            my $expected = $mbr_vbr->{vbr};
            if ($expected ne $hash) {
                error(__PACKAGE__, "Hash mismatch for VBR: expected $expected, got $hash");
                info(__PACKAGE__, "Check not passed");
                die "Hash mismatch for VBR\n";
            }
            info(__PACKAGE__, "VBR hash matched");
        }
    }

    trace(__PACKAGE__, "return from \"__check_mbr_vbr\"");
}

sub __get_mbr_vbr_hash {
    my $mbr_vbr = shift;

    trace(__PACKAGE__, "\"__get_mbr_vbr_hash\" was called");
    trace(__PACKAGE__, "mbr_vbr:\n" . np($mbr_vbr));

    my $dev = (PVE::IntegrityControl::GuestFS::list_devices())[0];

    if ((my $parttype = PVE::IntegrityControl::GuestFS::part_get_parttype($dev)) ne 'msdos') {
        error(__PACKAGE__, "Wrong vm disk partition table type: expected MBR, got '$parttype'");
        die "Failed to calculate MBR/VBR hash\n";
    }

    foreach my $entry (keys %{$mbr_vbr}) {
        if ($entry eq 'mbr') {
            my $mbr_raw = PVE::IntegrityControl::GuestFS::pread_device($dev, 512, 0);
            $mbr_vbr->{mbr} = __get_hash($mbr_raw);
            info(__PACKAGE__, "Computed MBR hash: $mbr_vbr->{mbr}");
        } elsif ($entry eq 'vbr') {
            my $part = &$try(\&PVE::IntegrityControl::GuestFS::find_bootable_partition);
            debug(__PACKAGE__, "bootable partition info:\n" . np($part));
            my $vbr_raw = PVE::IntegrityControl::GuestFS::pread_device($dev, 512, $part->{part_start});
            $mbr_vbr->{vbr} = __get_hash($vbr_raw);
            info(__PACKAGE__, "Computed VBR hash: $mbr_vbr->{vbr}");
        }
    }

    trace(__PACKAGE__, "return from \"__get_mbr_vbr_hash\"");
}

sub __verify_input {
    my $vmid = shift;

    die "Passed vmid [$vmid] is not valid\n" if not $vmid =~ m/^\d+$/;
}

sub check {
    my ($vmid) = @_;

    __verify_input($vmid);

    trace(__PACKAGE__, "\"check\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    my %db;
    eval {%db = %{PVE::IntegrityControl::DB::load($vmid)}};
    # FIXME
    if ($@) {
        error(__PACKAGE__, "Intergrity control objects are not defined");
        die $@;
    }

    &$try(\&__init_openssl_gost_engine) if not $digest;

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
            __check_mbr_vbr($db{bootloader});
        } elsif ($entry eq 'files') {
            &$launch_gfs() if keys %{$db{$entry}} and not $launched_gfs;
            foreach my $partition (keys %{$db{$entry}}) {
                my $mounted = 0;
                my $mount_partition = sub {
                    &$launch_gfs() unless $launched_gfs;
                    PVE::IntegrityControl::GuestFS::mount_partition($partition);
                    $mounted = 1;
                };
                foreach my $path (keys %{$db{$entry}{$partition}}) {
                    &$mount_partition() unless $mounted;
                    my $expected = $db{$entry}{$partition}{$path};
                    my $raw = PVE::IntegrityControl::GuestFS::read($path);
                    my $hash = __get_hash($raw);
                    if ($expected ne $hash) {
                        error(__PACKAGE__, "Hash mismatch for $partition:$path: expected $expected, got $hash");
                        info(__PACKAGE__, "Check not passed");
                        die "Hash mismatch for $partition:$path\n";
                    }
                    info(__PACKAGE__, "File [partition: $partition, path: $path] hash matched");
                }
                PVE::IntegrityControl::GuestFS::umount_partition() if $mounted;
            }
        }
    }

    info(__PACKAGE__, "Check passed successfully");

    trace(__PACKAGE__, "return from \"check\"");

    PVE::IntegrityControl::GuestFS::shutdown();

    return;
}

sub fill_db {
    my ($vmid) = @_;

    __verify_input($vmid);

    trace(__PACKAGE__, "\"fill_db\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    my %db = %{PVE::IntegrityControl::DB::load($vmid)};

    &$try(\&__init_openssl_gost_engine) if not $digest;

    my $launched_gfs = 0;
    my $launch_gfs = sub {
        PVE::IntegrityControl::GuestFS::add_vm_disks($vmid);
        $launched_gfs = 1;
    };

    my $new_obj = 0;
    foreach my $entry (keys %db) {
        if ($entry eq 'config') {
            next if $db{$entry} ne 'UNDEFINED';
            $db{$entry} = __get_hash(&$try(\&__get_config_file_content, $vmid));
            info(__PACKAGE__, "Computed config file hash: $db{$entry}");
            $new_obj = 1;
        } elsif ($entry eq 'bootloader') {
            next if ($db{$entry}->{mbr} // '') ne 'UNDEFINED' and ($db{$entry}->{vbr} // '') ne 'UNDEFINED';
            &$launch_gfs() if not $launched_gfs;
            __get_mbr_vbr_hash($db{$entry});
            $new_obj = 1;
        } elsif ($entry eq 'files') {
            foreach my $partition (keys %{$db{$entry}}) {
                my $mounted = 0;
                my $mount_partition = sub {
                    &$launch_gfs() unless $launched_gfs;
                    PVE::IntegrityControl::GuestFS::mount_partition($partition);
                    $mounted = 1;
                };
                foreach my $path (keys %{$db{$entry}{$partition}}) {
                    next if $db{$entry}{$partition}{$path} ne 'UNDEFINED';
                    &$mount_partition() unless $mounted;
                    $db{$entry}{$partition}{$path} = __get_hash(PVE::IntegrityControl::GuestFS::read($path));
                    info(__PACKAGE__, "Computed file [partitinon: $partition, path: $path] hash: $db{$entry}{$partition}{$path}");
                    $new_obj = 1;
                }
                PVE::IntegrityControl::GuestFS::umount_partition() if $mounted;
            }
        }
    }

    PVE::IntegrityControl::DB::write($vmid, \%db);

    info(__PACKAGE__, "New objects were added successfully") if $new_obj;

    trace(__PACKAGE__, "return from \"fill_db\"");

    return;
}

1;
