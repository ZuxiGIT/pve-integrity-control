use PVE::IntegrityControl::Checker;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

sub corrupt_db {
    my $vmid = shift;

    my $hash = "1111111";
    print "--> Corrupting database record 'config' with hash '$hash' value\n";
    my $db = PVE::IntegrityControl::DB::load($vmid);

    my $old_hash = $db->{config};
    $db->{config} = "111111111";

    PVE::IntegrityControl::DB::write($vmid, $db);

    return $old_hash;
}


sub restore_db {
    my $vmid = shift;
    my $hash = shift;

    print "--> Restoring database record 'config' with hash '$hash' value\n";
    my $db = PVE::IntegrityControl::DB::load($vmid);

    $db->{config} = $hash;

    PVE::IntegrityControl::DB::write($vmid, $db);
}

sub test {
    my $vmid = shift;
    print "--> Checking Vm $vmid\n";
    eval { PVE::IntegrityControl::Checker::check($vmid); };
    print "--> Got error: $@" if $@;
    print "--> Success\n" if not $@;
    print "--> check journal\n";
}

test $vmid;
my $hash = corrupt_db $vmid;
test $vmid;
restore_db $vmid, $hash;