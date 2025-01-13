use strict;
use warnings;

use PVE::IntegrityControl::Checker;

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

print qq|
*************************************************************************************

    PVE::IntegrityControl::Checker::check has one param:
      1. vmid - integer (100 < vmid < 999999)

    PVE::IntegrityControl::Checker::fill_db has one param:
      1. vmid - integer (100 < vmid < 999999)

*************************************************************************************
|;

sub tests {
    print "\n\n";

    my $vmid = shift;
    my $res;

    print "Calling Checker::check with '$vmid' as first param\n";
    eval { $res = PVE::IntegrityControl::Checker::check($vmid); };
    if ($@) {
        $@ =~ s/\s+$//g;
        print "Got error: '$@'. For details check journal.";
    } else {
        $res = 'None' if not $res;
        print "Result: [$res]. For details check journal\n";
    }

    print "\n\n";

    print "Calling Checker::fill_db with '$vmid' as first param\n";
    eval { $res = PVE::IntegrityControl::Checker::fill_db($vmid); };
    if ($@) {
        $@ =~ s/\s+$//g;
        print "Got error: '$@'. For details check journal.";
    } else {
        $res = 'None' if not $res;
        print "Result: [$res]. For details check journal\n";
    }

    print "\n\n";
}

tests 123;
tests "notanumber123";
tests  $vmid;
