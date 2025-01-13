use strict;
use warnings;

use DDP;
use PVE::IntegrityControl::DB;

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

sub test {
    print "\n";

    my $vmid = shift;

    print "Calling DB::load with [$vmid] as first param\n";
    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid); };
    $@ =~ s/\s+$//g if $@;
    print "Got error: $@\n" if $@;
    return if $@;

    print "Success\n";
    print "Database in memory:\n" . np($db);

    print "\n";
}

test "wrongvmid";
test 123;
test $vmid;
