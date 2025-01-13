use strict;
use warnings;

use PVE::IntegrityControl::Log qw(info warn debug error);

print "Test logger message is meaningless, so let's test component name\n";


sub test {
    print "\n";

    my $name = shift;

    print "Component name: $name\n";

    no strict 'refs';

    foreach my $log (qw|info warn debug error|) {
        eval { &$log ($name, "test"); };
        if ($@) {
            $@ =~ s/\s+$//g;
            print "Got error: -->$@<--\n";
        } else {
            print "Success, check journal\n";
        }
    }

    print "\n";
}

test 'NotValidName';
test 'IntegrityControl::ModuleName';
test 'PVE::IntegrityControl::ModuleName';
test 'PVE::API2::IntegrityControl::ModuleName';
