package PVE::CLI::ic;

use strict;
use warnings;
use DDP;

use PVE::INotify;
use PVE::QemuServer;
use PVE::JSONSchema;

use PVE::API2::IntegrityControl;

use PVE::CLIHandler;
use base qw(PVE::CLIHandler);

my $nodename = PVE::INotify::nodename();
my %node = (node => $nodename);

sub setup_environment {
    PVE::RPCEnvironment->setup_default_cli_env();
}

our $cmddef = {
    test=> [ 'PVE::API2::IntegrityControl' , 'test', ['vmid'], { %node }, sub {
        my $res = shift;
        print "Got string: \"$res\"\n";
    }
    ],
};

1;
