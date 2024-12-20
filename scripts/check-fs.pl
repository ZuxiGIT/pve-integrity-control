#!/usr/bin/perl
#
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Checker;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);
PVE::IntegrityControl::Checker::__init_openssl_gost_engine();

sub get_files_hashes {
    my $filename = shift;

    my %mountpoints = (
        ext4 => "/home",
        ext3 => "/mnt/ext3",
        ext2 => "/mnt/ext2",
        fat32 => "/mnt/fat32",
        fat16 => "/mnt/fat16",
        fat12 => "/mnt/fat12",
        minix => "/mnt/minix",
    );

    for my $type (sort keys %mountpoints) {
        my $basedir = $mountpoints{$type};
        my $content = PVE::IntegrityControl::GuestFS::read("$basedir/$filename");
        my $hash = PVE::IntegrityControl::Checker::__get_hash($content);
        print "--> [$type] hash for $basedir/$filename is $hash\n";
    }
}

get_files_hashes "testfile";

PVE::IntegrityControl::GuestFS::umount_vm_disks();
