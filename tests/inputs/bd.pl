use DDP;
use PVE::IntegrityControl::DB;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

sub test_vmid {
    my $vmid = shift;

    print "--> Calling DB::load with [$vmid] as first param\n";
    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid); };
    print "--> Got error: $@" if $@;
    print "--> Success\n" if not $@;

    print "--> Calling DB::write with [$vmid] as first param\n";
    eval { PVE::IntegrityControl::DB::write($vmid, $db); };
    print "--> Got error: $@" if $@;
    print "--> Success\n" if not $@;
}

sub test_wrong_input_format {
    my %db = (
        config => "1234",
        wrongkey => {},
        bios => "123456",
    );

    print "--> Calling DB::write with vmid: 555 and db:\n" . np (%db), "\n";
    eval { PVE::IntegrityControl::DB::write($vmid, \%db); };
    print "--> Got error: $@" if $@;
}

sub test_wrong_file_format {
    my $bad_db = qq|
config 1234
bios 12345
wrongkey wrongvalue
|;

    my $db_path = '/etc/pve/qemu-server/integrity-control/555.conf';
    open my $dbh, '>', $db_path;
    print $dbh $bad_db;
    close $dbh;

    print "--> Trying to read db from $db_path, containing db in wrong format:\n{\n$bad_db}\n";

    eval { PVE::IntegrityControl::DB::load(555); };
    print "--> Got error: $@" if $@;

    unlink $db_path;
}

test_vmid "teststring";
test_vmid $vmid;

test_wrong_input_format;
test_wrong_file_format;
