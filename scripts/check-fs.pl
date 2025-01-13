#!/usr/bin/perl
#
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Checker;

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

PVE::IntegrityControl::GuestFS::add_vm_disks($vmid);
PVE::IntegrityControl::Checker::__init_openssl_gost_engine();

sub get_files_hashes {
    my $filename = shift;

    my %partitions = (
        ext2 => "/dev/sda2",
        ext3 => "/dev/sda3",
        fat16 => "/dev/sda4",
        fat32 => "/dev/sda5",
        fat12 => "/dev/sda6",
        minix => "/dev/sda7",
        ntfs => "/dev/sda8",
        ext4 => "/dev/sda9"
    );

    for my $type (sort keys %partitions) {
        my $partition = $partitions{$type};
        PVE::IntegrityControl::GuestFS::mount_partition($partition, 0);

        my $path;
        if ($type eq 'ext4') {
            $path = "/home/$filename";
        } else {
            $path = "/$filename";
        }

        my $content = PVE::IntegrityControl::GuestFS::read($path);
        my $hash = PVE::IntegrityControl::Checker::__get_hash($content);
        print "[$type] hash for /$filename is $hash\n";
        PVE::IntegrityControl::GuestFS::sync();
        PVE::IntegrityControl::GuestFS::umount_partition();
    }
}

get_files_hashes "testfile";
