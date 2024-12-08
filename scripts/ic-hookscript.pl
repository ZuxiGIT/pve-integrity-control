#!/usr/bin/perl

use strict;
use warnings;

use PVE::IntegrityControl::Checker;
use PVE::IntegrityControl::Log qw(debug error info);

# First argument is the vmid
my $vmid = shift;
# Second argument is the phase
my $phase = shift;

if ($phase eq 'pre-start') {

    # First phase 'pre-start' will be executed before the guest
    # is started. Exiting with a code != 0 will abort the start

    debug("PVE::IntegrityControl::Hookscript", "start of vm with vmid:$vmid during '$phase' phase was intercepted");

    if ($ENV{PVE_MIGRATED_FROM}) {
        debug("PVE::IntegrityControl::Hookscript", "vm was started during migration process, check is delayed to 'pre-start' phase during VM resuming process");
        exit(0);
    }
    eval {
        PVE::IntegrityControl::Checker::check($vmid);
    };
    if ($@) {
        debug("PVE::IntegrityControl::Hookscript", "error: $@");
        error("PVE::IntegrityControl::Hookscript", "vm start is not permitted");
        exit(1);
    }

    info("PVE::IntegrityControl::Hookscript", "vm start is permitted");
    exit(0);

} elsif ($phase eq 'post-start') {

    # Second phase 'post-start' will be executed after the guest
    # successfully started.
    if ($ENV{PVE_MIGRATED_FROM}) {
        debug("PVE::IntegrityControl::Hookscript", "vm started, but is suspended until the end of disk and vmstate transfer");
    } else {
        debug("PVE::IntegrityControl::Hookscript", "vm started successfully");
    }

} elsif ($phase eq 'pre-stop') {

    # Third phase 'pre-stop' will be executed before stopping the guest
    # via the API. Will not be executed if the guest is stopped from
    # within e.g., with a 'poweroff'

    print "$vmid will be stopped.\n";

} elsif ($phase eq 'post-stop') {

    # Last phase 'post-stop' will be executed after the guest stopped.
    # This should even be executed in case the guest crashes or stopped
    # unexpectedly.

    print "$vmid stopped. Doing cleanup.\n";

} else {
    die "got unknown phase '$phase'\n";
}

exit(0);
