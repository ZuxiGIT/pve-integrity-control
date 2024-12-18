use strict;
use warnings;

use DDP;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Capture::Tiny qw(:all);
use IPC::System::Simple qw(run EXIT_ANY);

use PVE::Storage;
use PVE::Tools;

my $vmid = shift;
die "--> vmid is not set\n" if not $vmid;

my $scfg = PVE::Storage::config();
my $snippetsdir = '';
foreach my $id (sort keys %{$scfg->{ids}}) {
    my $volume_cfg = $scfg->{ids}->{$id};
    next if !grep {$_ eq 'snippets'} keys %{$volume_cfg->{content}};
    my $plugin = PVE::Storage::Plugin->lookup($volume_cfg->{type});
    $snippetsdir = $plugin->get_subdir($volume_cfg, 'snippets');
    next if $snippetsdir eq '';
    last;
}

die "--> Failed to find 'snippets' dir\n" if $snippetsdir eq '';
print "--> Snippet dir: $snippetsdir\n";

my $hookscriptname = "ic-hookscript.pl";
my $hookscriptpath = "$snippetsdir/$hookscriptname";

print "--> hookscriptpath: $hookscriptpath\n";

# open HOOKSCRIPT, "$hookscriptpath" or die "--> Failed to open hookscript\n";
# undef $/;
# my $hookscript = <HOOKSCRIPT>;

sub run_hookscript {
    local @ARGV = @_;

    print "--> running script with params:\n", np(@ARGV), "\n";
    my ($out, $err, $exit) = capture {
        run(EXIT_ANY, $^X, $hookscriptpath, @ARGV);
    };

    if ($exit == 255) {
        # script died
        print "--> Got exception error: $err";
    } elsif ($exit == 1) {
        # script returned error
        print "--> Got script error: check journal\n";
    } else {
        print "--> Got result: check journal\n";
    }
}

# 1 parameter not a number
run_hookscript "test", "test";
# 2 number is not valid phase name
run_hookscript "111", "somestring";
# number of params is not 2
run_hookscript "111", "pre-stop", "test";

# valid test cases
run_hookscript $vmid, "pre-stop";
run_hookscript $vmid, "post-stop";
run_hookscript $vmid, "post-start";
run_hookscript $vmid, "pre-start";

