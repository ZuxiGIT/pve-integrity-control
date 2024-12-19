#!/usr/bin/perl


use Text::Lorem;
use PVE::IntegrityControl::GuestFS;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid, 0);

sub generate_text {
    my $size = shift;

    my $text = Text::Lorem->new();
    my $words;
    while (bytes::length($words) < $size) {
        $words .= $text->words(5);
    }

    return $words;
}

sub generate_files {
    my $filename = shift;
    my $content = shift;

    my %mountpoints = (
        ext4 => "/home/",
        ext3 => "/mnt/ext3",
        ext2 => "/mnt/ext2",
        fat32 => "/mnt/fat32",
        fat16 => "/mnt/fat16",
        fat12 => "/mnt/fat12",
        minix => "/mnt/minix",
    );

    for my $type (sort keys %mountpoints) {
        my $basedir = $mountpoints{$type};
        PVE::IntegrityControl::GuestFS::__test_write_file("$basedir/$filename", $type . "\n" . $content);
    }
}


my $text = generate_text 1024 * 1024; # 1 Mb
generate_files "foo", $text;

PVE::IntegrityControl::GuestFS::umount_vm_disks();
