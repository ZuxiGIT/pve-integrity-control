package PVE::IntegrityControl::DB;

# To store IntegrityControl database PVE cluster fs (pmxfs) is used.
# IntegrityControl database associated with some <vmid> VM is stored in
# /etc/pve/nodes/<node>/qemu-server/intergrity-control directory under <vmid>.conf name.
#
# db file for some <vmid> VM has following structure:
#
# config <hash>
# bios <hash>
# files
#   <partition>:<path> <hash>
#       ^         ^     ^
#       |         |     |
#       |         |     +-- a file hash, computed using gost12 256 bit algorithm
#       |         +--- file location (e.g. /path/to/file)
#       +-- partition containing file (e.g. /dev/sda1)
#
# after parsing file db hash has following structure:
# db {
#   bios => <hash>,
#   config => <hash>,
#   files => {
#     <partition#1> => {
#       <path#1> => <hash>,
#       <file#2> => <hash>,
#     },
#     <partition#2> => {
#       <path#3> => <hash>,
#     },
#   },
# }
#

use strict;
use warnings;

use DDP;
use File::Copy;
use PVE::Cluster;
use PVE::IntegrityControl::Log qw(debug error info);

my $nodename = PVE::INotify::nodename();

PVE::Cluster::cfs_register_file(
    '/qemu-server/integrity-control/',
    \&__parse_ic_filedb,
    \&__write_ic_filedb
);

sub __parse_ic_filedb {
    my ($filename, $raw, $strict) = @_;

    return if !defined($raw);

    debug(__PACKAGE__, "\"__parse_ic_filedb\" filename:$filename");
    debug(__PACKAGE__, "\"__parse_ic_filedb\" raw:[$raw]");

    my $res = {};

    $filename =~ m|/qemu-server/integrity-control/(\d+)\.conf$|
	|| die "Got invalid ic db filepath: '$filename'";

    my $vmid = $1;

    my @lines = split(/\n/, $raw);
    foreach my $line (@lines) {
	    next if $line =~ m/^\s*$/;
        if ($line =~ m|^bios (\w+)$|) {
            my $hash = $1;
            $res->{bios} = $hash;
        } elsif ($line =~ m|^config (\w+)$|) {
            my $hash = $1;
            $res->{config} = $hash;
        } elsif ($line =~ m|^files$|) {
            next
        } elsif ($line =~ m|^\s+(/dev/\w+):((?:\/[a-z_\-\s0-9\.]+)+) (\w+)$|) {
            my ($partition, $path, $hash) = ($1, $2, $3);
            $res->{files}->{$partition}->{$path} = $hash;
        } else {
	        die "vm $vmid - unable to parse ic db: $line\n";
        }
    }
    return $res;
}

sub __write_ic_filedb {
    my ($filename, $db) = @_;

    my $raw = '';
    foreach my $entry (sort keys %$db) {
        if ($entry eq 'config') {
            $raw .= "config $db->{config}\n";
        } elsif ($entry eq 'bios' ) {
            # currently is not implemented
            $raw .= "bios $db->{bios}\n";
        } elsif ($entry eq 'files') {
            $raw .= "files\n";
            foreach my $partition (sort keys %{$db->{$entry}}) {
                foreach my $path (sort keys %{$db->{$entry}->{$partition}}) {
                    my $hash = $db->{$entry}->{$partition}->{$path};
                    $raw .= "\t$partition:$path $hash\n";
                }
            }
            last;
        } else {
            error(__PACKAGE__, "\"__write_ic_filedb\" unreachable");
            die __PACKAGE__ . " unreachable";
        }
    }

    return $raw;
}

sub __db_path {
    my ($vmid, $node) = @_;

    $node = $nodename if !$node;
    return "nodes/$node/qemu-server/integrity-control/$vmid.conf";
}

sub load_or_create {
    my ($vmid, $node) = @_;

    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid, $node)};
    if ($@) {
        info(__PACKAGE__, "There is no IntegrityControl DB for $vmid VM");
        info(__PACKAGE__, "Creating new one for $vmid VM");
        PVE::IntegrityControl::DB::create($vmid);
        $db = {}
    }
    return $db;
}

sub load {
    my ($vmid, $node) = @_;

    debug(__PACKAGE__, "\"load\" was called with params vmid:$vmid");

    my $dbpath = __db_path($vmid, $node);
    debug(__PACKAGE__, "\"load\" db path:$dbpath");

    my $db = PVE::Cluster::cfs_read_file($dbpath);

	if (!defined $db) {
        debug(__PACKAGE__, "Integrity control database file \"$dbpath\" does not exist");
        die "Failed to load Integrity control database file for VM $vmid\n";
    }

    debug(__PACKAGE__, "\"load\" success");
    debug(__PACKAGE__, "\"load\" IntegirtyControl db\n" . np($db));

    return $db;
}

sub write {
    my ($vmid, $db) = @_;

    debug(__PACKAGE__, "\"write\" was called with params vmid:$vmid");
    debug(__PACKAGE__, "\"write\" IntegirtyControl db\n" . np($db));

    my $dbpath = __db_path($vmid);
    debug(__PACKAGE__, "\"write\" db path:$dbpath");

    PVE::Cluster::cfs_write_file($dbpath, $db);
    debug(__PACKAGE__, "\"write\" success");
}

sub create {
    my ($vmid) = @_;

    debug(__PACKAGE__, "\"create\" was called with params vmid:$vmid");
    PVE::IntegrityControl::DB::write($vmid, {});
}

sub sync{
    my ($vmid, $targetnode) = @_;

    #test if DB exists
    load($vmid);

    my $basedir = "/etc/pve/";
    my $currdb = $basedir .__db_path($vmid);
    my $newdb = $basedir . __db_path($vmid, $targetnode);

    debug(__PACKAGE__, "\"sync\" curr_db:$currdb, new_db:$newdb");

    if (!copy($currdb, $newdb))
    {
        error(__PACKAGE__, "Failed to synchronize db with $targetnode for $vmid");
        die;
    }
}

1;
