package PVE::IntegrityControl::DB;

# To store IntegrityControl database PVE cluster fs (pmxfs) is used.
# IntegrityControl database associated with some <vmid> VM is stored in
# /etc/pve/nodes/<node>/qemu-server/intergrity-control directory under <vmid>.conf name.
#
# db file for some <vmid> VM has following structure:
#
# config <hash>
# bootloader <hash>
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
#   bootloader => <hash>,
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
use PVE::IntegrityControl::Log qw(debug error info trace);

my $nodename = PVE::INotify::nodename();

PVE::Cluster::cfs_register_file(
    '/qemu-server/integrity-control/',
    \&__parse_ic_filedb,
    \&__write_ic_filedb
);

sub __parse_ic_filedb {
    my ($filename, $raw, $strict) = @_;

    return if !defined($raw);

    trace(__PACKAGE__, "\"__parse_ic_filedb\" was called");
    trace(__PACKAGE__, "filename:$filename");
    trace(__PACKAGE__, "raw:[$raw]");

    my $res = {};

    $filename =~ m|/qemu-server/integrity-control/(\d+)\.conf$|
	|| die "Got invalid ic db filepath: '$filename'";

    my $vmid = $1;
    debug(__PACKAGE__, "vmid:$vmid");

    my @lines = split(/\n/, $raw);
    foreach my $line (@lines) {
	    next if $line =~ m/^\s*$/;
        if ($line =~ m|^bootloader (\w+)$|) {
            my $hash = $1;
            $res->{bootloader} = $hash;
        } elsif ($line =~ m|^config (\w+)$|) {
            my $hash = $1;
            $res->{config} = $hash;
        } elsif ($line =~ m|^files$|) {
            next
        } elsif ($line =~ m|^\s+(/dev/\w+):((?:\/[a-z_\-\s0-9\.]+)+) (\w+)$|) {
            my ($partition, $path, $hash) = ($1, $2, $3);
            $res->{files}->{$partition}->{$path} = $hash;
        } else {
	        error(__PACKAGE__, "Wrong file format, unable to parse line: '$line'");
            die "Wrong db file format for vm $vmid\n";
        }
    }

    return $res;
}

sub __write_ic_filedb {
    my ($filename, $db) = @_;

    trace(__PACKAGE__, "\"__write_ic_filedb\" was called");
    trace(__PACKAGE__, "filename:$filename");
    trace(__PACKAGE__, "db:\n" . np($db));

    $filename =~ m|/qemu-server/integrity-control/(\d+)\.conf$|
	|| die "Got invalid ic db filepath: '$filename'";

    my $vmid = $1;
    debug(__PACKAGE__, "vmid:$vmid");

    my $raw = '';
    foreach my $entry (sort keys %$db) {
        if ($entry eq 'config') {
            $raw .= "config $db->{config}\n";
        } elsif ($entry eq 'bootloader' ) {
            $raw .= "bootloader $db->{bootloader}\n";
        } elsif ($entry eq 'files') {
            $raw .= "files\n" if keys %{$db->{$entry}};
            foreach my $partition (sort keys %{$db->{$entry}}) {
                foreach my $path (sort keys %{$db->{$entry}->{$partition}}) {
                    my $hash = $db->{$entry}->{$partition}->{$path};
                    $raw .= "\t$partition:$path $hash\n";
                }
            }
        } else {
            error(__PACKAGE__, "Wrong db format, unexpected entry '$entry'");
            die "Wrong db format for vm $vmid\n";
        }
    }

    return $raw;
}

sub __db_path {
    my ($vmid, $node) = @_;

    $node = $nodename if !$node;

    trace(__PACKAGE__, "\"__db_path\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "node:$node");

    return "nodes/$node/qemu-server/integrity-control/$vmid.conf";
}

sub load_or_create {
    my ($vmid, $node) = @_;

    trace(__PACKAGE__, "\"load_or_create\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "node:$node") if $node;

    my $db;
    eval { $db = PVE::IntegrityControl::DB::load($vmid, $node)};
    if ($@) {
        info(__PACKAGE__, "There is no IntegrityControl DB for vm $vmid");
        info(__PACKAGE__, "Creating new one for vm $vmid");
        PVE::IntegrityControl::DB::create($vmid);
        $db = {}
    }
    return $db;
}

sub __verify {
    my $vmid = shift;

    die "Bad argument for vmid, expected number, but got [$vmid]\n" if not $vmid =~ m|^\d+$|;
}

sub load {
    my ($vmid, $node) = @_;

    __verify($vmid);

    trace(__PACKAGE__, "\"load\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "node:$node") if $node;

    my $dbpath = __db_path($vmid, $node);
    debug(__PACKAGE__, "db path for vm $vmid: $dbpath");

    my $db = PVE::Cluster::cfs_read_file($dbpath);

	if (!defined $db) {
        error(__PACKAGE__, "Integrity control database file \"$dbpath\" does not exist");
        die "Failed to load Integrity control database file for vm $vmid\n";
    }

    info(__PACKAGE__, "Successfully loaded integrity control database for vm $vmid");
    debug(__PACKAGE__, "Loaded integirty control db\n" . np($db));

    return $db;
}

sub write {
    my ($vmid, $db) = @_;

    __verify($vmid);

    trace(__PACKAGE__, "\"write\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "db:\n" . np($db));

    my $dbpath = __db_path($vmid);
    debug(__PACKAGE__, "db path for vm $vmid: $dbpath");

    PVE::Cluster::cfs_write_file($dbpath, $db);

    info(__PACKAGE__, "Successfully wrote integrity control database for vm $vmid");
}

sub create {
    my ($vmid) = @_;

    trace(__PACKAGE__, "\"create\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    PVE::IntegrityControl::DB::write($vmid, {});
    info(__PACKAGE__, "Successfully created integrity control database for vm $vmid");
}

sub sync{
    my ($vmid, $targetnode) = @_;

    trace(__PACKAGE__, "\"sync\" was called");
    trace(__PACKAGE__, "vmid:$vmid");
    trace(__PACKAGE__, "targetnode:$targetnode");

    #test if DB exists
    load($vmid);

    my $basedir = "/etc/pve/";
    my $currdb = $basedir .__db_path($vmid);
    my $newdb = $basedir . __db_path($vmid, $targetnode);

    debug(__PACKAGE__, "curr_db:$currdb, new_db:$newdb");

    if (!copy($currdb, $newdb))
    {
        error(__PACKAGE__, "Failed to synchronize db with $targetnode for $vmid");
        die "Failed to sync\n";
    }
    info(__PACKAGE__, "Successfully synced integrity control database for vm $vmid with node $targetnode");
}

1;
