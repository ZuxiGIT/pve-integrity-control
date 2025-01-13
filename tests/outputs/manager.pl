use strict;
use warnings;

use DDP;
use Capture::Tiny qw(:all);
use IPC::System::Simple qw(run EXIT_ANY);

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

my $ic = '/usr/sbin/ic';

sub call_manager {
    local @ARGV = @_;

    print "calling manager with params:\n", np(@ARGV), "\n";
    my ($out, $err, $exit) = capture {
        run(EXIT_ANY, $^X, $ic, @ARGV);
    };

    if ($exit == 255) {
        # script died
        $err =~ s/\s+$//g;
        print "Got exception error:\n--->$err<---";
    } elsif ($exit != 0) {
        # script returned error
        $err =~ s/\s+$//g;
        print "Return code: $exit. Error: --->$err<---\n";
    } else {
        $out =~ s/\s+$//g;
        print "Return code: $exit. Output: --->$out<---\n";
    }
}

call_manager "disable", $vmid;
call_manager "enable", $vmid;

call_manager "unset-object", $vmid, "--files", "/dev/sda2:/home/testfile";
call_manager "unset-object", $vmid, "--config";
call_manager "unset-object", $vmid, "--bootloader", "1,vbr=1";

call_manager "set-object", $vmid, "--files", "/dev/sda2:/home/testfile", "--config", "--bootloader", "1,vbr=1";
