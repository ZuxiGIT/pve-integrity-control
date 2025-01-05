package PVE::IntegrityControl::GuestFS;

use strict;
use warnings;

use DDP;
use PVE::Storage;
use PVE::QemuServer::Drive;
use PVE::QemuConfig;
use Sys::Guestfs;

use PVE::IntegrityControl::Log qw(error info warn debug trace);

my $try = sub {
    my $sub = shift;

    my $res;
    eval { $res = &$sub(@_); };
    if ($@) {
        error(__PACKAGE__, $@) if $@;
        die "Internal error occured\n";
    }
    return $res;
};

my $guestfs_handle = Sys::Guestfs->new();

sub __get_vm_disks {
    my ($vmid) = @_;

    trace(__PACKAGE__, "\"__get_vm_disks\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    my $storage_conf = undef;
    my $vm_conf = undef;
    my $bootdisks = undef;

    &$try(sub {
        my $vmid = shift;
        $storage_conf = PVE::Storage::config();
        $vm_conf = PVE::QemuConfig->load_config($vmid);
        $bootdisks = PVE::QemuServer::Drive::get_bootdisks($vm_conf);
    }, $vmid);

    debug(__PACKAGE__, "storage config for vmid:$vmid\n" . np($storage_conf));
    debug(__PACKAGE__, "config for vmid:$vmid\n" . np($vm_conf));
    debug(__PACKAGE__, "bootdisks for vmid:$vmid\n" . np($bootdisks));

    my %res;

    for my $bootdisk (@$bootdisks) {
        next if !PVE::QemuServer::Drive::is_valid_drivename($bootdisk);
        my $drive = PVE::QemuServer::Drive::parse_drive($bootdisk, $vm_conf->{$bootdisk});
        next if !defined($drive);
        next if PVE::QemuServer::Drive::drive_is_cdrom($drive);
        my $volid = $drive->{file};
        my $format = $drive->{format} || 'raw';
        next if !$volid;
        my $diskpath = PVE::Storage::path($storage_conf, $volid);
        $res{$bootdisk}->{file} = $diskpath;
        $res{$bootdisk}->{format} = $format;
    }
    debug(__PACKAGE__, "vm $vmid disks:\n" . np(%res));
    return \%res;
}

sub mount_vm_disks {
    my ($vmid, $ro) = @_;

    $ro = 1 if not defined $ro;

    trace(__PACKAGE__, "\"mount_vm_disks\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "readonly:$ro");

    my $disks = __get_vm_disks($vmid);

    foreach my $disk (keys %$disks) {
        my $disk_path = $disks->{$disk}->{file};
        my $disk_format = $disks->{$disk}->{format};

        debug(__PACKAGE__, "adding disk $disk_path");
        $guestfs_handle->add_drive($disk_path, readonly => $ro, format => $disk_format);
        debug(__PACKAGE__, "added drive $disk_path");
    }
    debug(__PACKAGE__, "launching guestfs...");
    $guestfs_handle->launch();
    debug(__PACKAGE__, "launched guestfs");

    debug(__PACKAGE__, "inspecting os...");
    my @roots = $guestfs_handle->inspect_os();
    if (@roots == 0) {
        error(__PACKAGE__, "inspect_vm: no operating systems found in \"" . join(", ", keys %$disks) . "\"\n");
        die "Faied to mount vm disks\n";
    }

    debug(__PACKAGE__, "got roots:\n" . np(@roots));

    # Mount up the disks
    foreach my $root (sort @roots) {
        # Sort keys by length, shortest first, so that we end up
        # mounting the filesystems in the correct order.
        debug(__PACKAGE__, "inspecting for mountpoints $root...");
        my %mps = $guestfs_handle->inspect_get_mountpoints($root);
        debug(__PACKAGE__, "got mountpoints\n" . np(%mps));
        my @mps = sort { length $a <=> length $b } (keys %mps);
        for my $mp (@mps) {
            debug(__PACKAGE__, "mounting mountable $mps{$mp} to mountpoint $mp");
            eval {
                if ($ro) {
                    $guestfs_handle->mount_ro($mps{$mp}, $mp);
                } else {
                    $guestfs_handle->mount($mps{$mp}, $mp);
                }
            };
            if ($@) {
                warn(__PACKAGE__, "error occured: $@ (ignored)");
            }
        }
    }
    info(__PACKAGE__, "Successfully mounted disks for vm $vmid");
}

sub umount_vm_disks {
    trace(__PACKAGE__, "\"umount_vm_disks\" was called");

    $guestfs_handle->umount_all();
    $guestfs_handle->shutdown();

    info(__PACKAGE__, "Successfully unmounted all disks");
}

sub read {
    my ($path) = @_;
    return $guestfs_handle->read_file($path);;
}

sub read2 {
    my ($file_path) = @_;

    my ($disk, $path) = split(':', $file_path);

    my @roots = $guestfs_handle->inspect_get_roots();
    if (!grep { $_ eq $disk } @roots) {
        error(__PACKAGE__, "unknown vm disk $disk");
        die "Failed to get file hash\n";
    }

    return $guestfs_handle->read_file($path);
}

sub drop_caches {
    my $level = shift;
    return $guestfs_handle->drop_caches($level);
}

sub stat {
    my $path = shift;

    return $guestfs_handle->statns($path);
}

sub find {
    my $dir = shift;

    return $guestfs_handle->find($dir);
}

sub write {
    my $file = shift;
    my $content = shift;

    return $guestfs_handle->write($file, $content);
}

1;
