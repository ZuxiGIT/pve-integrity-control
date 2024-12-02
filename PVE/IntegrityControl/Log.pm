package PVE::IntegrityControl::Log;

use Log::Log4perl qw(get_logger);

Log::Log4perl->init_and_watch("/var/log/pve-integrity-control/log.conf", 60);


sub info {
    my ($comp, $what) = @_;

    get_logger($comp)->info($what);
}

sub debug{
    my ($comp, $what) = @_;
    get_logger($comp)->debug($what);
}

sub warn{
    my ($comp, $what) = @_;
    get_logger($comp)->warn($what);
}

1;
