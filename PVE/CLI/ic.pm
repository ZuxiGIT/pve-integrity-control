package PVE::CLI::ic;

use strict;
use warnings;

use PVE::INotify;
use PVE::RPCEnvironment;

use PVE::API2::IntegrityControl;

use PVE::CLIHandler;
use base qw(PVE::CLIHandler);

my $nodename = PVE::INotify::nodename();
my %node = (node => $nodename);

sub setup_environment {
    PVE::RPCEnvironment->setup_default_cli_env();
}

our $cmddef = {
    status => ['PVE::API2::IntegrityControl', 'ic_status', ['vmid'], { %node }, sub {
        my $status = shift;
        print "status: $status\n";
    }],
    enable => ['PVE::API2::IntegrityControl', 'ic_enable', ['vmid'], { %node }],
    disable => ['PVE::API2::IntegrityControl', 'ic_disable', ['vmid'], { %node }],
};

1;
