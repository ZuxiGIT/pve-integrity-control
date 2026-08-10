use strict;
use warnings;

use Storable qw(dclone);
use Test::More;

BEGIN {
    package DDP;
    sub import {
        no strict 'refs';
        *{caller() . '::np'} = sub { return '' };
    }
    $INC{'DDP.pm'} = __FILE__;

    package PVE::INotify;
    sub nodename { return 'test-node' }
    $INC{'PVE/INotify.pm'} = __FILE__;

    package PVE::Cluster;
    our ($registered_path, $parser, $writer);
    sub import { return }
    sub cfs_register_file {
        ($registered_path, $parser, $writer) = @_;
        return;
    }
    sub cfs_read_file { return }
    sub cfs_write_file { return }
    $INC{'PVE/Cluster.pm'} = __FILE__;

    package PVE::IntegrityControl::Log;
    sub import {
        my ($class, @names) = @_;
        my $caller = caller();
        no strict 'refs';
        *{"${caller}::$_"} = sub { return } for @names;
    }
    $INC{'PVE/IntegrityControl/Log.pm'} = __FILE__;
}

use lib '.';
require PVE::IntegrityControl::DB;

is(
    $PVE::Cluster::registered_path,
    '/qemu-server/integrity-control/',
    'registers the expected pmxcfs path',
);
ok(ref($PVE::Cluster::parser) eq 'CODE', 'registers the real parser callback');
ok(ref($PVE::Cluster::writer) eq 'CODE', 'registers the real writer callback');

my $filename = '/qemu-server/integrity-control/100.conf';
my $db = {
    config => 'confighash',
    bootloader => {
        mbr => 'mbrhash',
    },
    files => {
        '/dev/sda2' => {
            '/z-file' => 'zhash',
            '/a-file' => 'ahash',
        },
        '/dev/sda1' => {
            '/etc/example' => 'filehash',
        },
    },
};
my $before = dclone($db);

my $raw = $PVE::Cluster::writer->($filename, $db);
my $expected = join("\n",
    'bootloader',
    "\tmbr mbrhash",
    'config confighash',
    'files',
    "\t/dev/sda1:/etc/example filehash",
    "\t/dev/sda2:/a-file ahash",
    "\t/dev/sda2:/z-file zhash",
);

is($raw, $expected, 'serializes the baseline in the existing text format');
is_deeply($db, $before, 'serialization leaves all nested input unchanged');

my $parsed = $PVE::Cluster::parser->($filename, $raw, 1);
is_deeply($parsed, $db, 'parser and writer round trip the complete baseline');

my $empty = {};
is($PVE::Cluster::writer->($filename, $empty), '', 'serializes an empty baseline');
is_deeply($empty, {}, 'empty baseline remains unchanged');

my $bad_top_level = { unexpected => 'hash' };
my $bad_top_level_before = dclone($bad_top_level);
my $bad_top_level_error = eval {
    $PVE::Cluster::writer->($filename, $bad_top_level);
    return '';
};
$bad_top_level_error = $@ if $@;
like($bad_top_level_error, qr/^Wrong db format for vm 100/, 'rejects an unknown top-level key');
is_deeply($bad_top_level, $bad_top_level_before, 'failed validation does not mutate unknown input');

my $bad_hash = { config => [] };
my $bad_hash_before = dclone($bad_hash);
my $bad_hash_error = eval {
    $PVE::Cluster::writer->($filename, $bad_hash);
    return '';
};
$bad_hash_error = $@ if $@;
like($bad_hash_error, qr/^Wrong db format for vm 100/, 'rejects a non-scalar hash value');
is_deeply($bad_hash, $bad_hash_before, 'failed hash validation does not mutate input');

my $bad_filename_error = eval {
    $PVE::Cluster::writer->('/wrong/path.conf', {});
    return '';
};
$bad_filename_error = $@ if $@;
like($bad_filename_error, qr/^Got invalid ic db filepath/, 'rejects an invalid DB filename');

my $bad_raw = "files\n\tinvalid-partition:/file hash";
my $bad_raw_error = eval {
    $PVE::Cluster::parser->($filename, $bad_raw, 1);
    return '';
};
$bad_raw_error = $@ if $@;
like($bad_raw_error, qr/^Wrong db file format for vm 100/, 'parser rejects an invalid partition path');

my $bad_vmid_error = eval {
    PVE::IntegrityControl::DB::load('not-a-vmid');
    return '';
};
$bad_vmid_error = $@ if $@;
like($bad_vmid_error, qr/^Bad argument for vmid/, 'public DB operations reject invalid VM IDs');

done_testing();
