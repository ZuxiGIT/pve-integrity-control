use PVE::IntegrityControl::Checker;


sub tests {
    my $vmid = shift;

    print "--> Calling Checker::check with $vmid as first param\n";
    eval { PVE::IntegrityControl::Checker::check($vmid); };
    print "--> Got error: $@" if $@;

    print "\n";

    print "--> Calling Checker::fill_db with $vmid as first param\n";
    eval { PVE::IntegrityControl::Checker::fill_db($vmid); };
    print "--> Got error: $@" if $@;

    print "\n\n";
}

tests 123;
tests "notanumber123";
