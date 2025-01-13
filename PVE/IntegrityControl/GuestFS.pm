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
    eval {
        no strict 'refs';
        $res = &$sub(@_);
    };
    if ($@) {
        error(__PACKAGE__, $@);
        die "Internal error occured\n";
    }
    return $res;
};

my $guestfs_handle = Sys::Guestfs->new();

my $try_gfs = sub {
    my $sub = shift;

    return &$try("Sys::Guestfs::$sub", $guestfs_handle, @_);
};

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

    trace(__PACKAGE__, "return from \"__get_vm_disks\"");

    return %res;
}

sub add_vm_disks {
    my ($vmid, $ro) = @_;

    $ro = 1 if not defined $ro;

    trace(__PACKAGE__, "\"add_vm_disks\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "readonly:$ro");

    my %disks = __get_vm_disks($vmid);

    if (keys %disks > 1) {
        error(__PACKAGE__, "Current implementation supports only one-disked vms");
        die "Unsupported number of disks\n";
    }

    foreach my $disk (keys %disks) {
        my $disk_path = $disks{$disk}{file};
        my $disk_format = $disks{$disk}{format};

        debug(__PACKAGE__, "adding disk $disk_path");
        &$try_gfs("add_drive", $disk_path, readonly => $ro, format => $disk_format);
        debug(__PACKAGE__, "added disk $disk_path");
    }

    debug(__PACKAGE__, "launching guestfs...");
    &$try_gfs("launch");
    debug(__PACKAGE__, "launched guestfs");

    my $dev = (list_devices())[0];

    my $parttype = &$try_gfs("part_get_parttype", $dev);
    debug(__PACKAGE__, "partition table type for $dev: $parttype");

    debug(__PACKAGE__, "Successfully added disks for vm $vmid");

    trace(__PACKAGE__, "return from \"add_vm_disks\"");
}

sub mount_partition {
    my ($partition, $ro) = @_;

    $ro = 1 if not defined $ro;

    trace(__PACKAGE__, "\"mount_partition\" was called");
    trace(__PACKAGE__, "partition:$partition");
    trace(__PACKAGE__, "readonly:$ro");

    if ($ro) {
        &$try_gfs("mount_ro", $partition, "/");
    } else {
        &$try_gfs("mount", $partition, "/");
    }

    debug(__PACKAGE__, "Successfully mounted partition $partition [ro? $ro]");
}

sub umount_partition {
    trace(__PACKAGE__, "\"umount_partition\" was called");

    my $partition = (&$try_gfs("mounts"))[0];

    &$try_gfs("umount", "/");

    debug(__PACKAGE__, "Successfully unmounted partition $partition");
}

sub sync {
    &$try_gfs("sync");
}

sub shutdown {
    sync();
    &$try_gfs("shutdown");
}

sub chmod {
    my $mode = shift;
    my $path = shift;

    &$try_gfs("chmod", $mode, $path);
}

sub find_bootable_partition {
    trace(__PACKAGE__, "\"find_bootable_partition\" was called");

    my $dev = (list_devices())[0];

    my @parts = &$try_gfs("part_list", $dev);

    foreach my $part (@parts) {
        return $part if &$try_gfs("part_get_bootable", $dev, $part->{part_num});
    }

    die "No bootable partition was found\n";
}

sub part_get_parttype {
    my $dev = shift;
    return &$try_gfs("part_get_parttype", $dev);
}

sub list_devices {
    trace(__PACKAGE__, "\"list_devices\" was called");
    return &$try_gfs("list_devices");
}

sub read {
    my ($path) = @_;
    return &$try_gfs("read_file", $path);
}

sub pread_device {
    my ($dev, $count, $offset) = @_;
    return &$try_gfs("pread_device", $dev, $count, $offset);
}

sub drop_caches {
    my $level = shift;
    return &$try_gfs("drop_caches", $level);
}

sub stat {
    my $path = shift;

    return &$try_gfs("statns", $path);
}

sub find {
    my $dir = shift;

    return &$try_gfs("find", $dir);
}

sub write {
    my $file = shift;
    my $content = shift;

    return &$try_gfs("write", $file, $content);
}

1;
