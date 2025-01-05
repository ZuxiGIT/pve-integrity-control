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
        print "--> exit code: $exit\n";
        print "--> Got exception error:\n$err";
    } elsif ($exit != 0) {
        # script returned error
        print "--> exit code: $exit\n";
        print "--> Got script error:\n$err" if $err;
    } else {
        print "--> exit code: $exit\n";
        print "--> Got result:\n$out" if $out;
    }

    print "--> check journal\n\n";
}

call_manager "disable", $vmid;
call_manager "enable", $vmid;

call_manager "unset-object", $vmid, "--files", "/dev/sda9:/home/testfile";
call_manager "unset-object", $vmid, "--config";
call_manager "unset-object", $vmid, "--bootloader";

call_manager "set-object", $vmid, "--files", "/dev/sda9:/home/testfile", "--config", "--bootloader";
