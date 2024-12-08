package PVE::CLI::ic;

use strict;
use warnings;

use PVE::INotify;
use PVE::Tools qw(extract_param);
use PVE::JSONSchema qw(get_standard_option);
use PVE::RPCEnvironment;

use PVE::API2::IntegrityControl;

use PVE::CLIHandler;
use base qw(PVE::CLIHandler);

my $nodename = PVE::INotify::nodename();
my %node = (node => $nodename);

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
            node => get_standard_option('pve-node'),
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
        my $localnode = extract_param($param, 'node');

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


our $cmddef = {
    status => ['PVE::API2::IntegrityControl', 'ic_status', ['vmid'], { %node }, sub {
        my $status = shift;
        print "status: $status\n";
    }],
    enable => ['PVE::API2::IntegrityControl', 'ic_enable', ['vmid'], { %node }],
    disable => ['PVE::API2::IntegrityControl', 'ic_disable', ['vmid'], { %node }],
    'set-objects' => ['PVE::API2::IntegrityControl', 'ic_files_set',  ['vmid'], { %node}],
    'unset-objects' => ['PVE::API2::IntegrityControl', 'ic_files_unset',  ['vmid'], { %node}],
    'get-db' => ['PVE::API2::IntegrityControl', 'ic_get_db',  ['vmid'], { %node}, sub {
        my $res = shift;
        print "database:\n$res";
    }],
    'open-journal' => [__PACKAGE__, 'less_log', [], {}],
    'sync-db' => [__PACKAGE__, 'sync_db', [ 'target' ], { %node }, sub {
        my $status = shift;
        print "status: $status\n";
    }],
};

1;
