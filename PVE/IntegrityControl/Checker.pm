package PVE::IntegrityControl::Checker;

use strict;
use warnings;

use DDP;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;

sub check {
    my ($vmid) = @_;

    my %db = %{PVE::IntegrityControl::DB::load($vmid)};
    PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);

    foreach my $disk (sort keys %db) {
        foreach my $path (sort keys %{$db{$disk}}) {
            die "ERROR: hash mismatch for $disk:$path\n"
            if $db{$disk}{$path} ne PVE::IntegrityControl::GuestFS::get_file_hash("$disk:$path");
        }
    }
}

1;
