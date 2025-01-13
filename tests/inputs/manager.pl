use strict;
use warnings;

use DDP;
use Capture::Tiny qw(:all);
use PVE::CLI::ic;
use IPC::System::Simple qw(run EXIT_ANY);

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

my $ic = '/usr/sbin/ic';

my @subcommands = sort keys %{$PVE::CLI::ic::cmddef};

{
    $" = "\n    ";
    print qq|
*************************************************************************************

    path: $ic

    manager has subcommands with params:

    @subcommands

**************************************************************************************

|;
}

sub call_manager {
    local @ARGV = @_;

    print "\n";
    print "Calling manager with params:\n", np(@ARGV), "\n";
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
    print "\n";
}

call_manager ;
call_manager "status", "zzz";
call_manager "status", $vmid;

call_manager "unset-object", $vmid, "--fff";
call_manager "unset-object", $vmid, "--files", "zzzzzzzz";
call_manager "unset-object", $vmid, "--files", "/dev/sda2:/home/testfile";
call_manager "unset-object", $vmid, "--config";
call_manager "unset-object", $vmid, "--bootloader", "1,vbr=1";

call_manager "set-object", $vmid, "--fff";
call_manager "set-object", $vmid, "--files", "zzzzzzzz";
call_manager "set-object", $vmid, "--files", "/dev/sda2:/home/testfile", "--config", "--bootloader", "1,vbr=1";
