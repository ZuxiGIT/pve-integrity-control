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
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Checker;
use PVE::IntegrityControl::Log qw(info debug);

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

        debug(__PACKAGE__, "\"status\" was called with params vmid:$vmid, node:$node");

        my $conf = PVE::QemuConfig->load_current_config($vmid);

        my $ic = $conf->{integrity_control};
        debug(__PACKAGE__, "\"status\" integrity_control: $ic") if defined $ic;
        if ($ic) {
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

        my $vmid = $param->{vmid};

        debug(__PACKAGE__, "\"enable\" was called with params vmid:$vmid");

        my $vm_cfg = PVE::QemuConfig->load_current_config($vmid, 1);
        die "ERROR: Vm $vmid already has hookscript: $vm_cfg->{hookscript}\n" if $vm_cfg->{hookscript};

        # CHECK vdisk_list subroutine in Storage.pm for different sub usage
        my $hookscriptname = "ic-hookscript.pl";
        my $scfg = PVE::Storage::config();
        my $volume = '';
        foreach my $id (sort keys %{$scfg->{ids}}) {
            my $volume_cfg = $scfg->{ids}->{$id};
            next if !$volume_cfg->{content}->{snippets};
            $volume = $id;
            last;
        }

        die "ERROR: Failed to find 'snippets' dir\n" if $volume eq '';

        return PVE::API2::Qemu->update_vm({%$param,
            integrity_control => 1,
            hookscript => "$volume:snippets/$hookscriptname"
        });
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
        my $vmid = $param->{vmid};

        debug(__PACKAGE__, "\"disable\" was called with params vmid:$vmid");

        return PVE::API2::Qemu->update_vm({%$param,
            integrity_control => 0,
            delete => 'hookscript'
        });
    }
});

PVE::JSONSchema::register_format('pve-ic-file', sub {
    my ($ic_file, $noerr) = @_;

    if ($ic_file =~ m|^/dev/\w+:/.*$|i) {
        return $ic_file;
    }
    return undef if $noerr;
    die "ERROR: Unable to parse file path for integrity control system '$ic_file'\n";
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
            files => PVE::JSONSchema::get_standard_option('pve-ic-files', {
                optional => 1}),
            config => {
                type => 'boolean',
                optional => 1,
            }
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');
        my $files = extract_param($param, 'files');
        my $config = extract_param($param, 'config');

        debug(__PACKAGE__, "\"set-objects\" was called with params vmid:$vmid");
        debug(__PACKAGE__, "\"set-objects\" files: $files") if $files;
        debug(__PACKAGE__, "\"set-objects\" config: $config") if $config;

        my $check = PVE::QemuServer::check_running($vmid);
        die "ERROR: Vm $vmid is running\n" if $check;

        my %ic_files_hash;

        if ($files) {
            my @ic_files_list = PVE::Tools::split_list($files);

            foreach my $file_location (sort @ic_files_list) {
                my ($partition, $path) = split(':', $file_location);
                push(@{$ic_files_hash{$partition}}, $path);
            }
        }

        __set_ic_objects($vmid, \%ic_files_hash, $config);
        return;
    }
});

sub __set_ic_objects {
    my ($vmid, $ic_files, $config) = @_;

    debug(__PACKAGE__, "\"__set_ic_obects\" was called");

    my $db = PVE::IntegrityControl::DB::load_or_create($vmid);

    foreach my $partition (sort keys %$ic_files) {
        foreach my $path (sort @{$ic_files->{$partition}}) {
            die "ERROR: Integrity control object redefinition [partition: $partition path: $path]\n"
            if exists $db->{files}->{$partition}->{$path};
            $db->{files}->{$partition}->{$path} = 'UNDEFINED';
        }
    }

    if ($config) {
        die "ERROR: Integrity control object redefinition [config]\n" if exists $db->{config};
        $db->{config} = 'UNDEFINED';
    }

    PVE::IntegrityControl::DB::write($vmid, $db);
    PVE::IntegrityControl::Checker::fill_db($vmid);
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
            files => PVE::JSONSchema::get_standard_option('pve-ic-files', {
                optional => 1}),
            config => {
                type => 'boolean',
                optional => 1,
            }
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $node = extract_param($param, 'node');
        my $vmid = extract_param($param, 'vmid');
        my $files = extract_param($param, 'files');
        my $config = extract_param($param, 'config');

        my $check = PVE::QemuServer::check_running($vmid);
        die "ERROR: Vm $vmid is running\n" if $check;

        my %ic_files_hash;
        if ($files) {
            my @ic_files_list = PVE::Tools::split_list($files);

            foreach my $file_location (sort @ic_files_list) {
                my ($disk, $file_path) = split(':', $file_location);
                push(@{$ic_files_hash{$disk}}, $file_path);
            }
        }

        __unset_ic_objects($vmid, \%ic_files_hash, $config);
        return;
    }
});

sub __unset_ic_objects {
    my ($vmid, $ic_files, $config) = @_;

    my $db = PVE::IntegrityControl::DB::load($vmid);

    if ($config) {
        die "ERROR: Integrity control object was not set earlier: [config]\n"
        if !exists $db->{config};
        delete $db->{config};
    }

    foreach my $disk (sort keys %$ic_files) {
        foreach my $file_path (sort @{$ic_files->{$disk}}) {
            die "ERROR: Integrity control object was not set earlier: [disk: $disk file path: $file_path]\n"
            if !exists $db->{$disk}->{$file_path};
            delete $db->{$disk}->{$file_path};
        }
    }

    PVE::IntegrityControl::DB::write($vmid, $db);
}

__PACKAGE__->register_method ({
    name => 'ic_get_db',
    path => '{vmid}/db',
    method => 'GET',
    description => 'Get integrity contol db for specified VM',
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

        my $db = PVE::IntegrityControl::DB::load($vmid);
        return np($db);
    }
});

1;
