package PVE::IntegrityControlChecker;

use strict;
use warnings;

use DDP;
use PVE::IntegrityControlDB;
use PVE::IntegrityControlGuestFS;

sub check {
    my ($vmid) = @_;

    my %db = %{PVE::IntegrityControlDB::load($vmid)};
    PVE::IntegrityControlGuestFS::mount_vm_disks($vmid);

    foreach my $disk (sort keys %db) {
        foreach my $path (sort keys %{$db{$disk}}) {
            die "ERROR: hash mismatch for $disk:$path\n"
            if $db{$disk}{$path} ne PVE::IntegrityControlGuestFS::get_file_hash("$disk:$path");
        }
    }
}

1;
