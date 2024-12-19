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
        $words .= $text->words(100);
    }

    return $words;
}

sub generate_files {
    my $filename = shift;
    my $content = shift;

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
        PVE::IntegrityControl::GuestFS::write("$basedir/$filename", $type . "\n" . $content);
        print "--> wrote file $basedir/$filename\n";
    }
}

my $text_size = 1024 * 1024; # 1 Mb
my $text = generate_text $text_size;
print "--> generated ~ $text_size bytes of text\n";
generate_files "testfile", $text;

PVE::IntegrityControl::GuestFS::umount_vm_disks();
