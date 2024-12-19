use DDP;
use PVE::IntegrityControl::DB;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

sub test {
    my $vmid = shift;

    print "--> Calling DB::load with [$vmid] as first param\n";
    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid); };
    print "--> Got error: $@" if $@;
    return if $@;

    print "--> Success\n" if not $@;

    print "--> Database in memory:\n" . np($db);
}

test "wrongvmid";
test 123;
test $vmid;
