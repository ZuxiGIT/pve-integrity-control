package PVE::IntegrityControl::DB;

# It is a workaround to integrate a IntegrityControl database into PVE cluster fs
# To achieve this config file storage is exploited: integrity control database (files with hashes) are stored in
# /etc/pve/<node>/qemu-server/intergrity-control directory under <vmid>.conf name
# a record in this db has format
# |disk:path hash|
#  ^    ^     ^
#  |    |     |
#  |    |     +-- a file sha256 hash
#  |    |
#  +-- a file location, passed by user via cli or REST api
#

use strict;
use warnings;

use DDP;
use PVE::Cluster;
use PVE::IntegrityControl::Log qw(debug error);

my $nodename = PVE::INotify::nodename();

PVE::Cluster::cfs_register_file(
    '/qemu-server/integrity-control/',
    \&__parse_ic_filedb,
    \&__write_ic_filedb
);

sub __parse_ic_filedb {
    my ($filename, $raw, $strict) = @_;

    return if !defined($raw);

    my $res = {};

    my $handle_error = sub {
	    my ($msg) = @_;

	    if ($strict) {
	        die $msg;
	    } else {
	        warn $msg;
	    }
    };

    $filename =~ m|/qemu-server/integrity-control/(\d+)\.conf$|
	|| die "Got invalid ic db filepath: '$filename'";

    my $vmid = $1;

    my @lines = split(/\n/, $raw);
    foreach my $line (@lines) {
	    next if $line =~ m/^\s*$/;
        if ($line =~ m|^/dev/\w+:.+ \S+$|) {
            my ($file_location, $hash) = split(/ /, $line);
            my ($disk, $file_path) = split(':', $file_location);
            $res->{$disk}->{$file_path} = $hash;
        } else {
	        $handle_error->("vm $vmid - unable to parse ic db: $line\n");
        }
    }
    return $res;
}

sub __write_ic_filedb {
    my ($filename, $db) = @_;

    my $raw = '';
    foreach my $disk (sort keys %$db) {
        foreach my $file (sort keys %{$db->{$disk}}) {
            my $hash = $db->{$disk}->{$file};
            $raw .= "$disk:$file $hash\n";
        }
    }

    return $raw;
}

sub __db_path {
    my ($vmid, $node) = @_;

    $node = $nodename if !$node;
    return "nodes/$node/qemu-server/integrity-control/$vmid.conf";
}

sub load {
    my ($vmid, $node) = @_;

    debug(__PACKAGE__, "\"load\" was called with params vmid:$vmid");

    my $dbpath = __db_path($vmid);

    my $db = PVE::Cluster::cfs_read_file($dbpath);

	if (!defined $db) {
        debug(__PACKAGE__, "Integrity control database file \"$dbpath\" does not exist");
        die "Failed to load Integrity control database file\n";
    }

    debug(__PACKAGE__, "loaded IntegirtyControl db for vmid:$vmid\n" . np($db));

    return $db;
}

sub write {
    my ($vmid, $db) = @_;

    debug(__PACKAGE__, "\"write\" was called with params vmid:$vmid");

    my $dbpath = __db_path($vmid);

    PVE::Cluster::cfs_write_file($dbpath, $db);
    debug(__PACKAGE__, "wrote IntegirtyControl db for vmid:$vmid \n" . np($db));
}

sub create {
    my ($vmid) = @_;

    debug(__PACKAGE__, "\"create\" was called with params vmid:$vmid");
    PVE::IntegrityControl::DB::write($vmid, {});
}

1;
