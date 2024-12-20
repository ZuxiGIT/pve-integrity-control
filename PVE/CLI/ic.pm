package PVE::CLI::ic;

use strict;
use warnings;

use DDP;
use PVE::INotify;
use PVE::Tools qw(extract_param);
use PVE::JSONSchema qw(get_standard_option);
use PVE::RPCEnvironment;

use PVE::API2::IntegrityControl;
use PVE::IntegrityControl::DB;
use PVE::IntegrityControl::Log;

use PVE::CLIHandler;
use base qw(PVE::CLIHandler);

sub setup_environment {
    PVE::RPCEnvironment->setup_default_cli_env();
}

__PACKAGE__->register_method ({
    name => 'less_log',
    path => 'less_log',
    method => 'GET',
    description => 'Less journal',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {}
    },
    returns => {
        type => 'null'
    },
    code => sub {
        system('less /var/log/pve-integrity-control/log.log');
        return
    }
});

__PACKAGE__->register_method ({
    name => 'sync_db',
    path => 'sync_db',
    method => 'POST',
    description => 'Synchronize db with other node',
    protected => 1,
    proxyto => 'node',
    parameters => {
        additionalProperties => 0,
        properties => {
            vmid => get_standard_option('pve-vmid', { completion => \&PVE::QemuServer::complete_vmid }),
            target => get_standard_option('pve-node', {
                description => "Target node.",
                completion =>  \&PVE::Cluster::complete_migration_target,
            }),
        }
    },
    returns => {
        type => 'string'
    },
    code => sub {
        my ($param) = @_;

        my $vmid = extract_param($param, 'vmid');
        my $target = extract_param($param, 'target');
        my $localnode = PVE::INotify::nodename();

        raise_param_exc({ target => "target is local node."}) if $target eq $localnode;

        PVE::Cluster::check_cfs_quorum();

        PVE::Cluster::check_node_exists($target);

        eval {PVE::IntegrityControl::DB::sync($vmid, $target) };
        if ($@) {
            return "failure\n$@";
        }
        return "success";
    }
});

__PACKAGE__->register_method ({
    name => 'get_db',
    path => 'get_db',
    method => 'GET',
    description => 'Get integrity contol db for specified VM',
    protected => 1,
    proxyto => 'node',
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

        my $db = PVE::IntegrityControl::DB::load($vmid);
        return np($db);
    }
});

__PACKAGE__->register_method ({
    name => 'new_journal',
    path => 'new_journal',
    method => 'POST',
    description => 'Archive journal and start new one',
    protected => 1,
    proxyto => 'node',
    parameters => {},
    returns => {
        type => 'null'
    },
    code => sub {
        PVE::IntegrityControl::Log::__get_rotator()->rotate();
        return;
    }
});


our $cmddef = {
    status => ['PVE::API2::IntegrityControl', 'ic_status', ['vmid'], { }, sub {
        my $status = shift;
        print "status: $status\n";
    }],
    enable => ['PVE::API2::IntegrityControl', 'ic_enable', ['vmid'], {}],
    disable => ['PVE::API2::IntegrityControl', 'ic_disable', ['vmid'], {}],
    'set-objects' => ['PVE::API2::IntegrityControl', 'ic_objects_set',  ['vmid'], {}],
    'unset-objects' => ['PVE::API2::IntegrityControl', 'ic_objects_unset',  ['vmid'], {}],
    'get-db' => [ __PACKAGE__, 'get_db',  ['vmid'], {}, sub {
        my $res = shift;
        print "database:\n$res";
    }],
    'open-journal' => [ __PACKAGE__, 'less_log', [], {}],
    'start-new-journal' => [ __PACKAGE__, 'new_journal', [], {}],
    'sync-db' => [ __PACKAGE__, 'sync_db', [ 'target' ], {}, sub {
        my $status = shift;
        print "status: $status\n";
    }],
};

1;
