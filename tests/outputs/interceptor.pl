use strict;
use warnings;

use DDP;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Capture::Tiny qw(:all);
use IPC::System::Simple qw(run EXIT_ANY);

use PVE::Storage;
use PVE::Tools;
use PVE::IntegrityControl::DB;

my $vmid = shift;
die "vmid is not set\n" if not $vmid;

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

die "Failed to find 'snippets' dir\n" if $snippetsdir eq '';

my $hookscriptname = "ic-hookscript.pl";
my $hookscriptpath = "$snippetsdir/$hookscriptname";


print qq|
*************************************************************************************

    hookscript path: $hookscriptpath

    hookscript has two return values:
      0 - integrity control check passed
      0 - integrity control check not passed

*************************************************************************************
|;

sub run_hookscript {
    print "\n";

    local @ARGV = @_;

    print "running script with params:\n", np(@ARGV), "\n";
    my ($out, $err, $exit) = capture {
        run(EXIT_ANY, $^X, $hookscriptpath, @ARGV);
    };

    if ($exit == 255) {
        # script died
        print "Got exception error: $err";
    } else {
        print "Return code: $exit. For details check journal\n";
    }
    print "\n";
}

sub corrupt_db {
    my $vmid = shift;

    my $hash = "1111111";
    print "Corrupting database record 'config' with hash '$hash' value\n";
    my $db = PVE::IntegrityControl::DB::load($vmid);

    my $old_hash = $db->{config};
    $db->{config} = "111111111";

    PVE::IntegrityControl::DB::write($vmid, $db);

    return $old_hash;
}


sub restore_db {
    my $vmid = shift;
    my $hash = shift;

    print "Restoring database record 'config' with hash '$hash' value\n";
    my $db = PVE::IntegrityControl::DB::load($vmid);

    $db->{config} = $hash;

    PVE::IntegrityControl::DB::write($vmid, $db);
}

run_hookscript $vmid, "pre-start";
my $old_hash = corrupt_db $vmid;
run_hookscript $vmid, "pre-start";
restore_db $vmid, $old_hash;
