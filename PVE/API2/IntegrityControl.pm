package PVE::API2::IntegrityControl;

use strict;
use warnings;

use DDP;
use PVE::JSONSchema;
use PVE::QemuConfig;
use PVE::QemuServer;
use PVE::Storage;
use PVE::Tools qw(extract_param);
use Sys::Guestfs;
use PVE::IntegrityControlDB;
use PVE::IntegrityControlGuestFS;

use PVE::API2::Qemu;

use PVE::RESTHandler;
use base qw(PVE::RESTHandler);

__PACKAGE__->register_method ({
    name => 'ic_status',
    path => '{vmid}/status/current',
    method => 'GET',
    description => 'Check whether integrity control is enabled for VM',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'string'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');

        my $conf = PVE::QemuConfig->load_current_config($vmid, 1);

        if ($conf->{integrity_control}) {
            return "enabled";
        } else {
            return "disabled";
        }
    }
});

__PACKAGE__->register_method ({
    name => 'ic_enable',
    path => '{vmid}/status/enable',
    method => 'PUT',
    protected => 1,
    proxyto => 'node',
    description => 'Enable integrity control for VM',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        return PVE::API2::Qemu->update_vm({%$param, integrity_control => 1});
    }
});

__PACKAGE__->register_method ({
    name => 'ic_disable',
    path => '{vmid}/status/disable',
    method => 'PUT',
    protected => 1,
    proxyto => 'node',
    description => 'Enable integrity control for VM',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;
        return PVE::API2::Qemu->update_vm({%$param, integrity_control => 0});
    }
});

PVE::JSONSchema::register_format('pve-ic-file', sub {
    my ($ic_file, $noerr) = @_;

    if ($ic_file =~ m|^/dev/\w+:/.*$|i) {
        return $ic_file;
    }
    return undef if $noerr;
    die "unable to parse file path for integrity control system '$ic_file'\n";
});

PVE::JSONSchema::register_standard_option('pve-ic-files', {
    description => "VM files for integrity control",
    type => 'string',
    format => 'pve-ic-file-list',
    format_description => 'file[;file...]',
});

__PACKAGE__->register_method ({
    name => 'ic_files_set',
    path => '{vmid}/objects',
    method => 'PUT',
    description => 'Specify VM files for integrity contol',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
            files => PVE::JSONSchema::get_standard_option('pve-ic-files'),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');

        my $check = PVE::QemuServer::check_running($vmid);
        die "VM $vmid is running\n" if $check;

        my @ic_files_list = PVE::Tools::split_list($param->{files});
        my %ic_files_hash;

        foreach my $file_location (sort @ic_files_list) {
            my ($disk, $file_path) = split(':', $file_location);
            push(@{$ic_files_hash{$disk}}, $file_path);
        }

        __set_ic_objects($vmid, \%ic_files_hash);
        return;
    }
});

sub __set_ic_objects {
    my ($vmid, $ic_files) = @_;

    my $db = PVE::IntegrityControlDB::load($vmid);

    foreach my $disk (sort keys %$ic_files) {
        foreach my $file_path (sort @{$ic_files->{$disk}}) {
            die "Integrity control object redefinition\ndisk: $disk\nfile path: $file_path\n"
            if exists $db->{$disk}->{$file_path};
            $db->{$disk}->{$file_path} = '';
        }
    }

    __fill_absent_hashes($vmid, $db);

    PVE::IntegrityControlDB::write($vmid, $db);
}

sub __fill_absent_hashes {
    my ($vmid, $db) = @_;

    PVE::IntegrityControlGuestFS::mount_vm_disks($vmid);

    foreach my $disk (keys %$db) {
        foreach my $file (keys %{$db->{$disk}}) {
            $db->{$disk}->{$file} = PVE::IntegrityControlGuestFS::get_file_hash("$disk:$file");
        }
    }

    PVE::IntegrityControlGuestFS::umount_vm_disks();
}

__PACKAGE__->register_method ({
    name => 'ic_files_unset',
    path => '{vmid}/objects',
    method => 'DELETE',
    description => 'Unspecify VM files for integrity contol',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
            files => PVE::JSONSchema::get_standard_option('pve-ic-files'),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');

        my $check = PVE::QemuServer::check_running($vmid);
        die "VM $vmid is running\n" if $check;

        my @ic_files_list = PVE::Tools::split_list($param->{files});
        my %ic_files_hash;

        foreach my $file_location (sort @ic_files_list) {
            my ($disk, $file_path) = split(':', $file_location);
            push(@{$ic_files_hash{$disk}}, $file_path);
        }

        __unset_ic_objects($vmid, \%ic_files_hash);
        return;
    }
});

sub __unset_ic_objects {
    my ($vmid, $ic_files) = @_;

    my $db = PVE::IntegrityControlDB::load($vmid);

    foreach my $disk (sort keys %$ic_files) {
        foreach my $file_path (sort @{$ic_files->{$disk}}) {
            die "Integrity control object was not set earlier\ndisk: $disk\nfile path: $file_path\n"
            if !exists $db->{$disk}->{$file_path};
            delete $db->{$disk}->{$file_path};
        }
    }

    PVE::IntegrityControlDB::write($vmid, $db);
}

__PACKAGE__->register_method ({
    name => 'ic_files_get',
    path => '{vmid}/objects',
    method => 'GET',
    description => 'Get VM files for integrity contol',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            node => PVE::JSONSchema::get_standard_option('pve-node'),
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'string'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');

        my $db = PVE::IntegrityControlDB::load($vmid);
        my $raw = '';

        foreach my $disk (sort keys %$db) {
            foreach my $path (sort keys %{$db->{$disk}}) {
                $raw .= "$disk:$path\n";
            }
        }
        # removing last whitespace
        $raw =~ s/\s+$//g;
        return $raw;
    }
});

1;
