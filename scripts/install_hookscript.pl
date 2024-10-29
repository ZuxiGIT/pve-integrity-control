use strict;
use warnings;

use DDP;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use PVE::Storage;
use PVE::Tools;

my $hookscriptname = "ic-hookscript.pl";
my $hookscriptpath = dirname(abs_path($0)) . "/" . $hookscriptname;
my $scfg = PVE::Storage::config();

my $snippetsdir = '';
foreach my $id (sort keys %{$scfg->{ids}}) {
    my $volume_cfg = $scfg->{ids}->{$id};
    next if !$volume_cfg->{path};
    my $plugin = PVE::Storage::Plugin->lookup($volume_cfg->{type});
    $snippetsdir = $plugin->get_subdir($volume_cfg, 'snippets');
    next if $snippetsdir eq '';
    last;
}

die "Failed to find 'snippets' dir\n" if $snippetsdir eq '';

my $dst = "$snippetsdir/$hookscriptname";
PVE::Tools::file_copy($hookscriptpath, $dst, undef, 0007);

print "Snippet dir: $snippetsdir\n";
print "Installed hookscript: $hookscriptpath -> $dst\n";
