use strict;
use warnings;

use DDP;
use PVE::IntegrityControl::DB;

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

print qq|
*************************************************************************************

    PVE::IntegrityControl::DB::write has two params:
      1. vmid - integer (100 < vmid < 999999)
      2. db - hash in specific format

    PVE::IntegrityControl::DB::load has one param:
      1. vmid - integer (100 < vmid < 999999)

*************************************************************************************
|;

sub test_vmid {
    print "\n";

    my $vmid = shift;

    print "Calling DB::load with [$vmid] as first param\n";
    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid); };
    $@ =~ s/\s+$//g if $@;
    print "Got error: $@\n" if $@;
    return if $@;
    print "Success\n" if not $@;

    print "Database in memory:\n" . np($db) . "\n";

    print "Calling DB::write with [$vmid] as first param\n";
    eval { PVE::IntegrityControl::DB::write($vmid, $db); };
    $@ =~ s/\s+$//g if $@;
    print "Got error: $@\n" if $@;
    print "Success\n" if not $@;


    print "\n";
}

sub test_wrong_input_format {
    print "\n";

    my %db = (
        config => "1234",
        wrongkey => {},
        bootloader => {
            mbr => "122321",
            vbr => "345253",
        },
    );

    print "Calling DB::write with vmid: 555 and db:\n" . np (%db), "\n";
    eval { PVE::IntegrityControl::DB::write(555, \%db); };
    $@ =~ s/\s+$//g if $@;
    print "Got error: $@\n" if $@;

    print "\n";
}

sub test_wrong_file_format {
    print "\n";

    my $bad_db = qq|
config 1234
bootloader
    mbr 1234
    vbr 12424
wrongkey wrongvalue
|;

    my $db_path = '/etc/pve/qemu-server/integrity-control/555.conf';
    open my $dbh, '>', $db_path;
    print $dbh $bad_db;
    close $dbh;

    print "Trying to read db from $db_path, containing db in wrong format:\n{$bad_db}\n";

    eval { PVE::IntegrityControl::DB::load(555); };
    $@ =~ s/\s+$//g if $@;
    print "Got error: $@\n" if $@;

    unlink $db_path;

    print "\n";
}

test_vmid 123;
test_vmid "teststring";
test_vmid $vmid;

test_wrong_input_format;
test_wrong_file_format;
