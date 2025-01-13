#!/usr/bin/perl

use strict;
use warnings;

use Time::HiRes;
use PVE::IntegrityControl::Checker;
use PVE::IntegrityControl::Log qw(debug error info warn);

# First argument is the vmid
my $vmid = shift;
# Second argument is the phase
my $phase = shift;

sub check_params {
    if (not $vmid =~ m/^\d+$/) {
        die "First parameter '$vmid' is not an integer\n";
    }

    if (!grep { $_ eq $phase } ('pre-start', 'pre-stop', 'post-start', 'post-stop')) {
        die "Second parameter '$phase' is not a valid phase\n";
    }

    # remainign params
    if (@ARGV != 0) {
        die "Expected 2 params, but got " . (2 + scalar(@ARGV)) . "\n";
    }
}

check_params();

if ($phase eq 'pre-start') {

    # First phase 'pre-start' will be executed before the guest
    # is started. Exiting with a code != 0 will abort the start

    info("PVE::IntegrityControl::Hookscript", "Start of vm $vmid was intercepted");
    debug("PVE::IntegrityControl::Hookscript", "Phase '$phase'");

    if ($ENV{PVE_MIGRATED_FROM}) {
        warn("PVE::IntegrityControl::Hookscript", "vm was started during migration process, check is delayed to 'pre-start' phase during VM resuming process");
        exit(0);
    }
    my $time = Time::HiRes::time();
    eval {
        PVE::IntegrityControl::Checker::check($vmid);
    };
    my $total = Time::HiRes::time() - $time;
    debug("PVE::IntegrityControl::Hookscript", "total: $total sec");
    if ($@) {
        info("PVE::IntegrityControl::Hookscript", $@);
        info("PVE::IntegrityControl::Hookscript", "vm start is not permitted");
        exit(1);
    }

    info("PVE::IntegrityControl::Hookscript", "vm start is permitted");

} elsif ($phase eq 'post-start') {

    # Second phase 'post-start' will be executed after the guest
    # successfully started.
    if ($ENV{PVE_MIGRATED_FROM}) {
        warn("PVE::IntegrityControl::Hookscript", "vm started, but is suspended until the end of disk and vmstate transfer");
    } else {
        info("PVE::IntegrityControl::Hookscript", "vm started successfully");
    }

    debug("PVE::IntegrityControl::Hookscript", "Phase '$phase': do nothing...");

} elsif ($phase eq 'pre-stop') {

    # Third phase 'pre-stop' will be executed before stopping the guest
    # via the API. Will not be executed if the guest is stopped from
    # within e.g., with a 'poweroff'

    debug("PVE::IntegrityControl::Hookscript", "Phase '$phase': do nothing...");

} elsif ($phase eq 'post-stop') {

    # Last phase 'post-stop' will be executed after the guest stopped.
    # This should even be executed in case the guest crashes or stopped
    # unexpectedly.

    debug("PVE::IntegrityControl::Hookscript", "Phase '$phase': do nothing...");

} else {
    die "Unknown phase '$phase'\n";
}

exit(0);
