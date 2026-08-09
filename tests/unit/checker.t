use strict;
use warnings;

use Test::More;

BEGIN {
    package DDP;
    sub import {
        no strict 'refs';
        *{caller() . '::np'} = sub { return '' };
    }
    $INC{'DDP.pm'} = __FILE__;

    package PVE::Cluster;
    $INC{'PVE/Cluster.pm'} = __FILE__;

    package PVE::QemuConfig;
    sub load_current_config { return {} }
    $INC{'PVE/QemuConfig.pm'} = __FILE__;

    package PVE::QemuServer;
    sub write_vm_config { return 'config-raw' }
    $INC{'PVE/QemuServer.pm'} = __FILE__;

    package PVE::IntegrityControl::Log;
    sub import {
        my ($class, @names) = @_;
        my $caller = caller();
        no strict 'refs';
        *{"${caller}::$_"} = sub { return } for @names;
    }
    $INC{'PVE/IntegrityControl/Log.pm'} = __FILE__;

    package PVE::IntegrityControl::Digest;
    our $initialized = 1;
    our $init_count = 0;
    our @hash_inputs;
    sub is_initialized { return $initialized }
    sub init_openssl_gost_engine { $init_count++; $initialized = 1; return }
    sub get_hash { push @hash_inputs, $_[0]; return 'hash:' . $_[0] }
    $INC{'PVE/IntegrityControl/Digest.pm'} = __FILE__;

    package PVE::IntegrityControl::DB;
    our $db;
    our $load_count = 0;
    our @writes;
    sub load { $load_count++; return $db }
    sub write { push @writes, [ @_ ]; return }
    $INC{'PVE/IntegrityControl/DB.pm'} = __FILE__;

    package PVE::IntegrityControl::GuestFS;
    our @sessions;
    our @events;
    our %reads;
    sub with_vm_disks {
        my ($vmid, @args) = @_;
        my $callback = pop @args;
        my %opts = @args;
        push @sessions, [ $vmid, { %opts } ];
        return $callback->();
    }
    sub list_devices { return ('/dev/sda') }
    sub part_get_parttype { return 'msdos' }
    sub pread_device { return $_[1] == 512 && $_[2] == 0 ? 'mbr-raw' : 'vbr-raw' }
    sub find_bootable_partition { return { part_start => 2048 } }
    sub mount_partition { push @events, "mount:$_[0]"; return }
    sub umount_partition { push @events, 'umount'; return }
    sub read { push @events, "read:$_[0]"; return $reads{$_[0]} }
    $INC{'PVE/IntegrityControl/GuestFS.pm'} = __FILE__;
}

use lib '.';
require PVE::IntegrityControl::Checker;

sub reset_fakes {
    $PVE::IntegrityControl::DB::db = undef;
    $PVE::IntegrityControl::DB::load_count = 0;
    @PVE::IntegrityControl::DB::writes = ();
    @PVE::IntegrityControl::GuestFS::sessions = ();
    @PVE::IntegrityControl::GuestFS::events = ();
    %PVE::IntegrityControl::GuestFS::reads = ();
    $PVE::IntegrityControl::Digest::initialized = 1;
    $PVE::IntegrityControl::Digest::init_count = 0;
    @PVE::IntegrityControl::Digest::hash_inputs = ();
}

sub assert_one_readonly_session {
    my ($vmid, $name) = @_;
    is_deeply(
        \@PVE::IntegrityControl::GuestFS::sessions,
        [[ $vmid, { readonly => 1 } ]],
        $name,
    );
}

reset_fakes();
$PVE::IntegrityControl::DB::db = { config => 'hash:config-raw' };
PVE::IntegrityControl::Checker::check(100);
is($PVE::IntegrityControl::DB::load_count, 1, 'config-only check loads DB once');
is(scalar(@PVE::IntegrityControl::GuestFS::sessions), 0, 'config-only check avoids GuestFS');

reset_fakes();
$PVE::IntegrityControl::DB::db = { bootloader => { mbr => 'hash:mbr-raw' } };
PVE::IntegrityControl::Checker::check(101);
is($PVE::IntegrityControl::DB::load_count, 1, 'bootloader check loads DB once');
assert_one_readonly_session(101, 'bootloader check opens one read-only session');

reset_fakes();
$PVE::IntegrityControl::DB::db = { files => { '/dev/sda1' => { '/file' => 'hash:file-raw' } } };
$PVE::IntegrityControl::GuestFS::reads{'/file'} = 'file-raw';
PVE::IntegrityControl::Checker::check(102);
is($PVE::IntegrityControl::DB::load_count, 1, 'file check loads DB once');
assert_one_readonly_session(102, 'file check opens one read-only session');
is_deeply(
    \@PVE::IntegrityControl::GuestFS::events,
    ['mount:/dev/sda1', 'read:/file', 'umount'],
    'file check mounts, reads, and unmounts the selected partition',
);

reset_fakes();
$PVE::IntegrityControl::DB::db = { bootloader => {}, files => {} };
PVE::IntegrityControl::Checker::check(103);
is($PVE::IntegrityControl::DB::load_count, 1, 'empty disk sections load DB once');
is(scalar(@PVE::IntegrityControl::GuestFS::sessions), 0, 'empty disk sections avoid GuestFS');

reset_fakes();
$PVE::IntegrityControl::DB::db = {
    bootloader => { mbr => 'hash:mbr-raw' },
    files => { '/dev/sda1' => { '/file' => 'hash:file-raw' } },
};
PVE::IntegrityControl::Checker::fill_db(104);
is($PVE::IntegrityControl::DB::load_count, 1, 'fully populated fill loads DB once');
is(scalar(@PVE::IntegrityControl::GuestFS::sessions), 0, 'fully populated disk objects avoid GuestFS');
is(scalar(@PVE::IntegrityControl::DB::writes), 1, 'fully populated fill preserves DB write behavior');

reset_fakes();
$PVE::IntegrityControl::DB::db = { bootloader => { mbr => 'UNDEFINED' } };
PVE::IntegrityControl::Checker::fill_db(105);
is($PVE::IntegrityControl::DB::load_count, 1, 'undefined bootloader fill loads DB once');
assert_one_readonly_session(105, 'undefined bootloader fill opens one read-only session');
is($PVE::IntegrityControl::DB::db->{bootloader}->{mbr}, 'hash:mbr-raw', 'fills undefined bootloader hash');
is($PVE::IntegrityControl::DB::writes[0]->[1], $PVE::IntegrityControl::DB::db, 'writes the loaded DB snapshot');

reset_fakes();
$PVE::IntegrityControl::DB::db = { files => { '/dev/sda1' => { '/file' => 'UNDEFINED' } } };
$PVE::IntegrityControl::GuestFS::reads{'/file'} = 'file-raw';
PVE::IntegrityControl::Checker::fill_db(106);
is($PVE::IntegrityControl::DB::load_count, 1, 'undefined file fill loads DB once');
assert_one_readonly_session(106, 'undefined file fill opens one read-only session');
is($PVE::IntegrityControl::DB::db->{files}->{'/dev/sda1'}->{'/file'}, 'hash:file-raw', 'fills undefined file hash');

reset_fakes();
$PVE::IntegrityControl::DB::db = { config => 'UNDEFINED' };
PVE::IntegrityControl::Checker::fill_db(107);
is($PVE::IntegrityControl::DB::load_count, 1, 'config-only fill loads DB once');
is(scalar(@PVE::IntegrityControl::GuestFS::sessions), 0, 'config-only fill avoids GuestFS');
is($PVE::IntegrityControl::DB::db->{config}, 'hash:config-raw', 'fills undefined config without GuestFS');

reset_fakes();
$PVE::IntegrityControl::DB::db = { config => 'hash:config-raw' };
$PVE::IntegrityControl::Digest::initialized = 0;
PVE::IntegrityControl::Checker::check(108);
PVE::IntegrityControl::Checker::check(108);
is($PVE::IntegrityControl::Digest::init_count, 1, 'Checker initializes Digest only once');
is_deeply(
    \@PVE::IntegrityControl::Digest::hash_inputs,
    ['config-raw', 'config-raw'],
    'Checker forwards original data to Digest for each hash',
);

reset_fakes();
is(
    PVE::IntegrityControl::Checker::__get_hash('wrapper-data'),
    'hash:wrapper-data',
    'hash compatibility wrapper returns the Digest result',
);
is_deeply(
    \@PVE::IntegrityControl::Digest::hash_inputs,
    ['wrapper-data'],
    'hash compatibility wrapper forwards its input unchanged',
);
PVE::IntegrityControl::Checker::__init_openssl_gost_engine();
is($PVE::IntegrityControl::Digest::init_count, 1, 'initialization compatibility wrapper delegates to Digest');

done_testing();
