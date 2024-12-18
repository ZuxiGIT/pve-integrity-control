use DDP;
use Capture::Tiny qw(:all);
use IPC::System::Simple qw(run EXIT_ANY);

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

my $ic = '/usr/sbin/ic';

sub call_manager {
    local @ARGV = @_;

    print "--> calling manager with params:\n", np(@ARGV), "\n";
    my ($out, $err, $exit) = capture {
        run(EXIT_ANY, $^X, $ic, @ARGV);
    };

    if ($exit == 255) {
        # script died
        print "--> Got exception error:\n$err";
    } elsif ($exit != 0) {
        # script returned error
        print "--> Got script error: $err\n";
    } else {
        print "--> Got result: $out\n";
    }
}

call_manager ;
call_manager "status", "zzz";
call_manager "status", $vmid;

call_manager "unset-object", $vmid, "--fff";
call_manager "unset-object", $vmid, "--files", "zzzzzzzz";
call_manager "unset-object", $vmid, "--files", "/dev/sda9:/root/testfile";
call_manager "unset-object", $vmid, "--config";
call_manager "unset-object", $vmid, "--bios";

call_manager "set-object", $vmid, "--fff";
call_manager "set-object", $vmid, "--files", "zzzzzzzz";
call_manager "set-object", $vmid, "--files", "/dev/sda9:/root/testfile", "--config", "--bios";

