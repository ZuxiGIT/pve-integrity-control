package PVE::IntegrityControl::Checker;

use strict;
use warnings;

use DDP;
use Net::SSLeay;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Log qw(debug error info);

sub __init_openssl_gost_engine {
    debug(__PACKAGE__, "\"__init_openssl_gost_engine\" was called");

    my $engine = Net::SSLeay::ENGINE_by_id("gost");
    debug(__PACKAGE__, "\"__init_openssl_gost_engine\" value corresponding to GOST engine: $engine");

    # 0xffff magic constans means ENGINE_METHOD_ALL
    if (!Net::SSLeay::ENGINE_set_default($engine, 0xffff)) {
        error(__PACKAGE__, "\"__init_openssl_gost_engine\" failed to set GOST engine");
        die "Faield to set up " . __PACKAGE__ . " environment";
    }

    Net::SSLeay::load_error_strings();
    Net::SSLeay::OpenSSL_add_all_algorithms();
    my $ss = Net::SSLeay::P_EVP_MD_list_all();
    info(__PACKAGE__, " digests:\n " . np($ss));
}

sub check {
    my ($vmid) = @_;

    debug(__PACKAGE__, "\"check\" was called with params vmid:$vmid");

    __init_openssl_gost_engine();
    my $digest = Net::SSLeay::EVP_get_digestbyname("md_gost12_256");

    my %db = %{PVE::IntegrityControl::DB::load($vmid)};
    PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);

    foreach my $disk (sort keys %db) {
        foreach my $path (sort keys %{$db{$disk}}) {
            my $hash  = PVE::IntegrityControl::GuestFS::get_file_hash($digest, "$disk:$path");
            if ($db{$disk}{$path} ne  $hash) {
                debug(__PACKAGE__, "\"check\" hash mismatch for $disk:$path: expected $db{$disk}{$path}, got $hash");
                die "ERROR: hash mismatch for $disk:$path\n";
            }
        }
    }
    info(__PACKAGE__, "\"check\" passed successfully");

    PVE::IntegrityControl::GuestFS::umount_vm_disks();
}

sub fill_absent_hashes {
    my ($vmid, $db) = @_;

    __init_openssl_gost_engine();
    my $digest = Net::SSLeay::EVP_get_digestbyname("md_gost12_256");
    PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);

    foreach my $disk (keys %$db) {
        foreach my $file (keys %{$db->{$disk}}) {
            $db->{$disk}->{$file} = PVE::IntegrityControl::GuestFS::get_file_hash($digest, "$disk:$file");
        }
    }

    PVE::IntegrityControl::GuestFS::umount_vm_disks();
}

1;
