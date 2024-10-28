package PVE::IntegrityControlGuestFS;

use strict;
use warnings;

use DDP;
use PVE::Storage;
use PVE::QemuServer::Drive;
use Sys::Guestfs;

my $guestfs_handle = Sys::Guestfs->new();

sub __get_vm_disks {
    my ($vmid) = @_;

    my $storage_conf = PVE::Storage::config();
    my $vm_conf = PVE::QemuConfig->load_config($vmid);
    my $bootdisks = PVE::QemuServer::Drive::get_bootdisks($vm_conf);

    my %res;

    for my $bootdisk (@$bootdisks) {
        next if !PVE::QemuServer::Drive::is_valid_drivename($bootdisk);
        my $drive = PVE::QemuServer::Drive::parse_drive($bootdisk, $vm_conf->{$bootdisk});
        next if !defined($drive);
        next if PVE::QemuServer::Drive::drive_is_cdrom($drive);
        my $volid = $drive->{file};
        my $format = $drive->{format};
        next if !$volid;
        my $diskpath = PVE::Storage::path($storage_conf, $volid);
        $res{$bootdisk}->{file} = $diskpath;
        $res{$bootdisk}->{format} = $format;
    }
    return \%res;
}

sub mount_vm_disks {
    my ($vmid) = @_;

    my $disks = __get_vm_disks($vmid);

    foreach my $disk (keys %$disks) {
        $guestfs_handle->add_drive($disks->{$disk}->{file}, readonly => 1, format => $disks->{$disk}->{format});
    }
    $guestfs_handle->launch();
    my @roots = $guestfs_handle->inspect_os();
    die "inspect_vm: no operating systems found in \"" . join(", ", keys %$disks) . "\"\n" if @roots == 0;

    # Mount up the disks
    foreach my $root (sort @roots) {
        # Sort keys by length, shortest first, so that we end up
        # mounting the filesystems in the correct order.
        my %mps = $guestfs_handle->inspect_get_mountpoints($root);
        my @mps = sort { length $a <=> length $b } (keys %mps);
        for my $mp (@mps) {
            eval { $guestfs_handle->mount_ro($mps{$mp}, $mp) };
            if ($@) {
                print "$@ (ignored)\n"
            }
        }
    }
}

sub umount_vm_disks {
    $guestfs_handle->umount_all();
    $guestfs_handle->shutdown();
}

sub get_file_hash {
    my ($file_path) = @_;

    my ($disk, $path) = split(':', $file_path);

    my @roots = $guestfs_handle->inspect_get_roots();
    if (!grep { $_ eq $disk } @roots) {
        die "Unknown VM disk: $disk\n";
    }

    my $hash = $guestfs_handle->checksum("sha256", $path);

    die "Failed to get hash for $disk:$path\n" if $hash eq '';
    return $hash;
}

1;
