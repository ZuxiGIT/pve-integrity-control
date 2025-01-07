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

sub extract {
    my ($param, $key) = @_;

    my $res = $param->{$key};
    delete $param->{$key};

    return $res;
}

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

    my $verify_hash_format = sub {
        my $entry = shift;
        my $hash = shift;
        if (ref $hash ne '' or not $hash =~ m|\w+|) {
            error(__PACKAGE__, "Wrong db file format, unexpected hash value [$hash] for '$entry'");
            die "Wrong db file format for vm $vmid\n";
        }
    };

    my @lines = split(/\n/, $raw);

    while(@lines) {
        my $line = shift @lines;
	    next if $line =~ m/^\s*$/;

        if ($line =~ m|^bootloader$|) {
            my $exit = 0;
            until($exit) {
                my $bootloader_line = shift @lines;
                last unless $bootloader_line;
                debug(__PACKAGE__, "bootloader_line [$bootloader_line]");
                if ($bootloader_line =~ m{^\s+(mbr|vbr) (\w+)$}) {
                    my ($br, $hash) = ($1, $2);
                    debug(__PACKAGE__, "br $br");
                    &$verify_hash_format("bootloader::$br", $hash);
                    $res->{bootloader}->{$br} = $hash;
                    next;
                }
                $exit = 1;
                unshift @lines, $bootloader_line if $bootloader_line;
            }
            next;
        } elsif ($line =~ m|^config (\w+)$|){
            my $hash = $1;
            &$verify_hash_format('config file', $hash);
            $res->{config} = $hash;
            next;
        } elsif ($line =~ m|^files$|) {
            my $exit = 0;
            # loop for file array proccessing
            until ($exit) {
                my $file_line = shift @lines;
                last unless $file_line;
                debug(__PACKAGE__, "file_line: [$file_line]");
                if ($file_line =~ m|^\s+(/dev/\w+):((?:\/[a-zA-Z_\-\s0-9\.]+)+) (\w+)$|) {
                    my ($partition, $path, $hash) = ($1, $2, $3);
                    &$verify_hash_format("$partition:$path", $hash);
                    $res->{files}->{$partition}->{$path} = $hash;
                } else {
                    # failed to parse file with hash, exitiing loop
                    $exit = 1;
                    unshift @lines, $file_line if $file_line;
                }
            }
            next;
        }

        error(__PACKAGE__, "Wrong db file format, failed to parse line: [$line]");
        die "Wrong db file format for vm $vmid\n";
    }

    trace(__PACKAGE__, "return from \"__parse_ic_filedb\"");
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

    my $verify_hash_format = sub {
        my $entry = shift;
        my $hash = shift;
        if (ref $hash ne '' or not $hash =~ m|\w+|) {
            error(__PACKAGE__, "Wrong db format, unexpected hash value [$hash] for '$entry'");
            die "Wrong db format for vm $vmid\n";
        }
    };

    my $raw = '';
    foreach my $entry (sort keys %$db) {
        if ($entry eq 'config') {
            my $hash = extract($db, 'config');
            &$verify_hash_format('config file', $hash);
            $raw .= "config $hash\n";
        } elsif ($entry eq 'bootloader' ) {
            $raw .= "bootloader\n";
            foreach my $entry (keys %{$db->{bootloader}}) {
                my $hash = extract($db->{bootloader}, $entry);
                &$verify_hash_format("bootloader::$entry", $hash);
                $raw .= "\t$entry $hash\n";
            }
            extract($db, 'bootloader');
        } elsif ($entry eq 'files') {
            $raw .= "files\n";
            foreach my $partition (sort keys %{$db->{$entry}}) {
                foreach my $path (sort keys %{$db->{$entry}->{$partition}}) {
                    my $hash = extract($db->{files}->{$partition}, $path);
                    &$verify_hash_format("$partition:$path", $hash);
                    $raw .= "\t$partition:$path $hash\n";
                }
                extract($db->{files}, $partition);
            }
            extract($db, 'files');
        } else {
            error(__PACKAGE__, "Wrong db format, unexpected entry '$entry'");
            die "Wrong db format for vm $vmid\n";
        }
    }

    if (%{$db}) {
        error(__PACKAGE__, "Wrong db format, unexpected entries:\n" . np($db));
        die "Wrong db format for vm $vmid\n";
    }

    $raw =~ s/\s+$//;
    debug(__PACKAGE__, "string to write: [$raw]");

    trace(__PACKAGE__, "return from \"__write_ic_filedb\"");
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

    trace(__PACKAGE__, "return from \"load_or_create\"");
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

    trace(__PACKAGE__, "return from \"load\"");
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

    trace(__PACKAGE__, "return from \"write\"");
}

sub create {
    my ($vmid) = @_;

    trace(__PACKAGE__, "\"create\" was called");
    trace(__PACKAGE__, "vmid:$vmid");

    PVE::IntegrityControl::DB::write($vmid, {});
    info(__PACKAGE__, "Successfully created integrity control database for vm $vmid");

    trace(__PACKAGE__, "return from \"create\"");
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
