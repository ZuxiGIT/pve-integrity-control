package PVE::IntegrityControl::Checker;

use strict;
use warnings;

use DDP;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Log qw(debug error);

sub check {
    my ($vmid) = @_;

    debug(__PACKAGE__, "\"check\" was called with params vmid:$vmid");

    my %db = %{PVE::IntegrityControl::DB::load($vmid)};
    PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);

    foreach my $disk (sort keys %db) {
        foreach my $path (sort keys %{$db{$disk}}) {
            my $hash  = PVE::IntegrityControl::GuestFS::get_file_hash("$disk:$path");
            if ($db{$disk}{$path} ne  $hash) {
                error(__PACKAGE__, "hash mismatch for $disk:$path: expected $db{$disk}{$path}, got $hash");
                die "ERROR: hash mismatch for $disk:$path\n"
            }
        }
    }
}

1;
