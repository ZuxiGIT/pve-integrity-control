#!/usr/bin/perl

use strict;
use warnings;

use Text::Lorem;
use PVE::IntegrityControl::GuestFS;

my $bios_vm = shift;
die "--> bios_vm is not set\n" if not $bios_vm;

my $eufi_vm = shift;
die "--> eufi_vm is not set\n" if not $eufi_vm;

sub generate_text {
    my $size = shift;

    my $text = Text::Lorem->new();
    my $words = '';
    while (bytes::length($words) < $size) {
        $words .= $text->words(100);
    }

    return $words;
}

sub bios_vm_generate_files {

    my ($vmid, $filename, $content) = @_;

    PVE::IntegrityControl::GuestFS::add_vm_disks($vmid, 0);

    PVE::IntegrityControl::GuestFS::mount_partition("/dev/sda2", 0);
    PVE::IntegrityControl::GuestFS::write("/home/$filename", $content);
    PVE::IntegrityControl::GuestFS::chmod(0666, "/home/$filename");
    PVE::IntegrityControl::GuestFS::sync();
    PVE::IntegrityControl::GuestFS::umount_partition();

    PVE::IntegrityControl::GuestFS::shutdown();

    print "--> wrote file '$filename' for vm $vmid\n";
}

sub uefi_vm_generate_files {
    my $vmid = shift;
    my $filename = shift;
    my $content = shift;

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

    PVE::IntegrityControl::GuestFS::add_vm_disks($vmid, 0);

    for my $type (sort keys %partitions) {
        my $partition = $partitions{$type};
        PVE::IntegrityControl::GuestFS::mount_partition($partition, 0);
        if ($type eq 'ext4') {
            PVE::IntegrityControl::GuestFS::write("/home/$filename", $content);
            PVE::IntegrityControl::GuestFS::chmod(0666, "/home/$filename");
        } else {
            PVE::IntegrityControl::GuestFS::write("/$filename", $content);
            PVE::IntegrityControl::GuestFS::chmod(0666, "/$filename");
        }
        PVE::IntegrityControl::GuestFS::sync();
        PVE::IntegrityControl::GuestFS::umount_partition();
        print "--> wrote file '$filename' for vm $vmid with $type fs\n";
    }

    PVE::IntegrityControl::GuestFS::shutdown();
}


my $text_size = 1024 * 1024; # 1 Mb
my $text = generate_text $text_size;
print "--> generated ~ $text_size bytes of text\n";

bios_vm_generate_files $bios_vm, "testfile", $text;
uefi_vm_generate_files $eufi_vm, "testfile", $text;
