package PVE::API2::IntegrityControl;

use strict;
use warnings;

use DDP;
use PVE::JSONSchema qw(parse_property_string);
use PVE::QemuConfig;
use PVE::QemuServer;
use PVE::Storage;
use PVE::Tools qw(extract_param);
use Sys::Guestfs;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::GuestFS;
use PVE::IntegrityControl::Checker;
use PVE::IntegrityControl::Log qw(info debug trace);

use PVE::API2::Qemu;

use PVE::RESTHandler;
use base qw(PVE::RESTHandler);

my $nodename = PVE::INotify::nodename();
my %node = (node => $nodename);

__PACKAGE__->register_method ({
    name => 'ic_status',
    path => '{vmid}/status/current',
    method => 'GET',
    description => 'Check whether integrity control is enabled for VM',
    parameters => {
        additionalProperties => 0,
        properties => {
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'string'
    },
    code => sub {
        my ($param) = @_;

        my $vmid = extract_param($param, 'vmid');

        trace(__PACKAGE__, "\"status\" was called with params vmid:$vmid");

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
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $vmid = extract_param($param, 'vmid');

        trace(__PACKAGE__, "\"enable\" was called with params vmid:$vmid");

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

        info(__PACKAGE__, "Integrity control for vm $vmid was enabled");

        return PVE::API2::Qemu->update_vm({(node => $nodename, vmid => $vmid),
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
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;
        my $vmid = extract_param($param, 'vmid');

        trace(__PACKAGE__, "\"disable\" was called with params vmid:$vmid");

        info(__PACKAGE__, "Integrity control for vm $vmid was disabled");

        return PVE::API2::Qemu->update_vm({( node => $nodename, vmid => $vmid),
            delete => 'hookscript,integrity_control'
        });
    }
});

PVE::JSONSchema::register_format('pve-ic-file', sub {
    my ($ic_file, $noerr) = @_;

    if ($ic_file =~ m|^/dev/\w+:/.*$|i) {
        return $ic_file;
    }
    return undef if $noerr;
    die "ERROR: Unable to parse file path for integrity control object: '$ic_file'\n";
});

PVE::JSONSchema::register_standard_option('pve-ic-files', {
    description => "Vm files for integrity control",
    type => 'string',
    format => 'pve-ic-file-list',
    format_description => 'file[;file...]',
});

my $ic_bootloader_fmt = {
    mbr => {
        type => 'boolean',
        descritption => "Option to set MBR section as integrity control object",
        default_key => 1,
    },
    vbr => {
        type => 'boolean',
        typetext => 'vbr',
        descritption => "Option to set VBR section as integrity control object",
        optional => 1,
        default => 0,
    },
};
PVE::JSONSchema::register_format('pve-ic-bootloader', $ic_bootloader_fmt);

my $ic_bootloader_desc = {
    type => 'string',
    format => 'pve-ic-bootloader',
    description => "Bootloader options for integrity control"
};
PVE::JSONSchema::register_standard_option('pve-ic-bootloader', $ic_bootloader_desc);

__PACKAGE__->register_method ({
    name => 'ic_objects_set',
    path => '{vmid}/objects',
    method => 'PUT',
    description => 'Specify VM files for integrity contol',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
            files => PVE::JSONSchema::get_standard_option('pve-ic-files', {
                optional => 1}),
            config => {
                type => 'boolean',
                optional => 1,
            },
            bootloader => PVE::JSONSchema::get_standard_option('pve-ic-bootloader', {
                optional => 1}),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $vmid = extract_param($param, 'vmid');
        my $files_raw = extract_param($param, 'files');
        my $config = extract_param($param, 'config');
        my $bootloader_raw = extract_param($param, 'bootloader');

        my $check = PVE::QemuServer::check_running($vmid);
        die "ERROR: Vm $vmid is running\n" if $check;

        my @files = PVE::Tools::split_list($files_raw) if $files_raw;
        my $bootloader = parse_property_string('pve-ic-bootloader', $bootloader_raw) if $bootloader_raw;

        trace(__PACKAGE__, "\"set-objects\" was called with params vmid:$vmid");
        trace(__PACKAGE__, "files: " . np(@files)) if @files;
        trace(__PACKAGE__, "config: $config") if $config;
        trace(__PACKAGE__, "bootloader: " . np($bootloader)) if $bootloader;

        my $files = {};

        if (@files) {
            foreach my $file_location (sort @files) {
                my ($partition, $path) = split(':', $file_location);
                push(@{$files->{$partition}}, $path);
            }
        }

        __set_ic_objects($vmid, $files, $config, $bootloader);
        return;
    }
});

sub __set_ic_objects {
    my ($vmid, $files, $config, $bootloader) = @_;

    trace(__PACKAGE__, "\"__set_ic_obects\" was called");

    my $db = PVE::IntegrityControl::DB::load_or_create($vmid);

    foreach my $partition (sort keys %$files) {
        foreach my $path (sort @{$files->{$partition}}) {
            die "ERROR: Integrity control object redefinition [partition: $partition, path: $path]\n"
            if exists $db->{files}->{$partition}->{$path};
            $db->{files}->{$partition}->{$path} = 'UNDEFINED';
        }
    }

    if ($config) {
        die "ERROR: Integrity control object redefinition [config]\n" if exists $db->{config};
        $db->{config} = 'UNDEFINED';
    }

    if ($bootloader) {
        die "ERROR: Integrity control object redefinition [bootloader]\n" if exists $db->{bootloader};
        $db->{bootloader}->{mbr} = 'UNDEFINED' if $bootloader->{mbr};
        $db->{bootloader}->{vbr} = 'UNDEFINED' if $bootloader->{vbr};
    }

    PVE::IntegrityControl::DB::write($vmid, $db);

    eval { PVE::IntegrityControl::Checker::fill_db($vmid); };
    if (my $err = $@) {
        info(__PACKAGE__, "Error occured while adding new objects: $err");
        __unset_ic_objects($vmid, $files, $config, $bootloader);
        die $err;
    }
}

__PACKAGE__->register_method ({
    name => 'ic_objects_unset',
    path => '{vmid}/objects',
    method => 'DELETE',
    description => 'Unspecify VM files for integrity contol',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            vmid => PVE::JSONSchema::get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
            files => PVE::JSONSchema::get_standard_option('pve-ic-files', {
                optional => 1}),
            config => {
                type => 'boolean',
                optional => 1,
            },
            bootloader => PVE::JSONSchema::get_standard_option('pve-ic-bootloader', {
                optional => 1}),
        },
    },
    returns => {
        type => 'null'
    },
    code => sub {
        my ($param) = @_;

        my $vmid = extract_param($param, 'vmid');
        my $files = extract_param($param, 'files');
        my $config = extract_param($param, 'config');
        my $bootloader = extract_param($param, 'bootloader');

        trace(__PACKAGE__, "\"unset-objects\" was called with params vmid:$vmid");
        trace(__PACKAGE__, "files: $files") if $files;
        trace(__PACKAGE__, "config: $config") if $config;
        trace(__PACKAGE__, "bootloader $bootloader") if $bootloader;

        my %ic_files_hash;
        if ($files) {
            my @ic_files_list = PVE::Tools::split_list($files);

            foreach my $file_location (sort @ic_files_list) {
                $file_location =~ m|^(/dev/\w+):((?:\/[a-z_\-\s0-9\.]+)+)$|;
                my ($partition, $path) = ($1, $2);
                push(@{$ic_files_hash{$partition}}, $path);
            }
        }

        __unset_ic_objects($vmid, \%ic_files_hash, $config, $bootloader);
        return;
    }
});

sub __unset_ic_objects {
    my ($vmid, $ic_files, $config, $bootloader) = @_;

    trace(__PACKAGE__, "\"__unset_ic_obects\" was called");

    my $db = PVE::IntegrityControl::DB::load($vmid);

    if ($config) {
        die "ERROR: Integrity control object was not set earlier: [config]\n"
        if !exists $db->{config};
        delete $db->{config};
    }

    if ($bootloader) {
        die "ERROR: Integrity control object was not set earlier: [bootloader]\n"
        if !exists $db->{bootloader};
        delete $db->{bootloader}->{mbr} if exists $db->{bootloader}->{mbr};
        delete $db->{bootloader}->{vbr} if exists $db->{bootloader}->{vbr};

        delete $db->{bootloader} unless keys %{$db->{bootloader}};
    }

    if ($ic_files) {
        foreach my $partition (sort keys %$ic_files) {
            foreach my $path (sort @{$ic_files->{$partition}}) {
                die "ERROR: Integrity control object was not set earlier: [partition: $partition file path: $path]\n"
                if !exists $db->{files}->{$partition}->{$path};
                delete $db->{files}->{$partition}->{$path};
                delete $db->{files}->{$partition} if keys %{$db->{files}->{$partition}} == 0;
            }
        }

        delete $db->{files} unless keys %{$db->{files}};
    }

    PVE::IntegrityControl::DB::write($vmid, $db);
}

1;
