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

    package PVE::Storage;
    $INC{'PVE/Storage.pm'} = __FILE__;

    package PVE::QemuServer::Drive;
    $INC{'PVE/QemuServer/Drive.pm'} = __FILE__;

    package PVE::QemuConfig;
    $INC{'PVE/QemuConfig.pm'} = __FILE__;

    package PVE::IntegrityControl::Log;
    sub import {
        my ($class, @names) = @_;
        my $caller = caller();
        no strict 'refs';
        *{"${caller}::$_"} = sub { return } for @names;
    }
    $INC{'PVE/IntegrityControl/Log.pm'} = __FILE__;

    package Sys::Guestfs;
    our $next_id = 0;
    our @events;
    our $umount_error;
    our $shutdown_error;

    sub new {
        return bless { id => ++$next_id }, __PACKAGE__;
    }

    sub umount_all {
        my ($self) = @_;
        push @events, "umount:$self->{id}";
        die $umount_error if defined($umount_error);
        return;
    }

    sub shutdown {
        my ($self) = @_;
        push @events, "shutdown:$self->{id}";
        die $shutdown_error if defined($shutdown_error);
        return;
    }
    $INC{'Sys/Guestfs.pm'} = __FILE__;
}

use lib '.';
require PVE::IntegrityControl::GuestFS;

sub reset_fake_guestfs {
    @Sys::Guestfs::events = ();
    $Sys::Guestfs::umount_error = undef;
    $Sys::Guestfs::shutdown_error = undef;
    $PVE::IntegrityControl::GuestFS::guestfs_handle = undef;
}

sub run_with_fake_disks {
    my ($vmid, @args) = @_;
    my @added;

    no warnings 'once';
    no warnings 'redefine';
    local *PVE::IntegrityControl::GuestFS::add_vm_disks = sub {
        push @added, [ @_ ];
    };

    my $result = PVE::IntegrityControl::GuestFS::with_vm_disks($vmid, @args);
    return ($result, \@added);
}

reset_fake_guestfs();
my $callback_handle;
my ($result, $added) = run_with_fake_disks(100, sub {
    $callback_handle = $PVE::IntegrityControl::GuestFS::guestfs_handle;
    return 'callback-result';
});
is($result, 'callback-result', 'returns the callback result');
is_deeply($added, [[100, 1]], 'adds VM disks read-only by default');
is_deeply(
    \@Sys::Guestfs::events,
    ["umount:$callback_handle->{id}", "shutdown:$callback_handle->{id}"],
    'unmounts and shuts down the owned handle',
);
ok(!defined($PVE::IntegrityControl::GuestFS::guestfs_handle), 'clears handle after success');

reset_fake_guestfs();
my (undef, $writable_added) = run_with_fake_disks(101, readonly => 0, sub { return });
is_deeply($writable_added, [[101, 0]], 'passes an explicit readonly value through');

reset_fake_guestfs();
$Sys::Guestfs::umount_error = "cleanup failed\n";
my $callback_error = eval {
    run_with_fake_disks(102, sub { die "callback failed\n" });
    return '';
};
$callback_error = $@ if $@;
is($callback_error, "callback failed\n", 'callback error takes precedence over cleanup error');
is(scalar(@Sys::Guestfs::events), 2, 'attempts both cleanup operations after callback failure');
ok(!defined($PVE::IntegrityControl::GuestFS::guestfs_handle), 'clears handle after callback failure');

reset_fake_guestfs();
$Sys::Guestfs::shutdown_error = "shutdown failed\n";
my $cleanup_error = eval {
    run_with_fake_disks(103, sub { return });
    return '';
};
$cleanup_error = $@ if $@;
is($cleanup_error, "Internal error occurred\n", 'propagates cleanup failure');
ok(!defined($PVE::IntegrityControl::GuestFS::guestfs_handle), 'clears handle after cleanup failure');

reset_fake_guestfs();
my ($outer_handle, $nested_handle);
my $nested_error;
run_with_fake_disks(104, sub {
    $outer_handle = $PVE::IntegrityControl::GuestFS::guestfs_handle;
    eval {
        run_with_fake_disks(105, sub {
            $nested_handle = $PVE::IntegrityControl::GuestFS::guestfs_handle;
        });
    };
    $nested_error = $@;
    is(
        $PVE::IntegrityControl::GuestFS::guestfs_handle,
        $outer_handle,
        'nested rejection leaves the outer handle intact',
    );
    return;
});
like($nested_error, qr/^GuestFS session is already active/, 'rejects a nested session');
ok(!defined($nested_handle), 'nested session never creates a handle');
ok(!defined($PVE::IntegrityControl::GuestFS::guestfs_handle), 'outer owner clears its handle');

reset_fake_guestfs();
my $existing_handle = Sys::Guestfs->new();
$PVE::IntegrityControl::GuestFS::guestfs_handle = $existing_handle;
my $active_error = eval {
    run_with_fake_disks(106, sub { return });
    return '';
};
$active_error = $@ if $@;
like($active_error, qr/^GuestFS session is already active/, 'rejects an already-active procedural session');
is(
    $PVE::IntegrityControl::GuestFS::guestfs_handle,
    $existing_handle,
    'does not replace or clean up a handle it does not own',
);
$PVE::IntegrityControl::GuestFS::guestfs_handle = undef;

reset_fake_guestfs();
my @handles;
run_with_fake_disks(107, sub {
    push @handles, $PVE::IntegrityControl::GuestFS::guestfs_handle;
    return;
});
run_with_fake_disks(108, sub {
    push @handles, $PVE::IntegrityControl::GuestFS::guestfs_handle;
    return;
});
isnt($handles[0], $handles[1], 'sequential sessions never reuse a stale handle');

done_testing();
