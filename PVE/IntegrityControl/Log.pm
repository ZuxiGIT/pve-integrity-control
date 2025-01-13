package PVE::IntegrityControl::Log;

use Logfile::Rotate;
use File::stat;
use Log::Log4perl qw(get_logger);
use base 'Exporter';

our @EXPORT_OK = qw(
info
debug
warn
error
trace
);

Log::Log4perl->init_and_watch("/var/log/pve-integrity-control/log.conf", 60);

our $LOGFILE_LIMIT = 1024 * 1024 * 1024; # 1 Gb

sub get_logfile_path {
    return Log::Log4perl::appenders()->{'LogFile'}->filename();
}

sub __get_rotator {
    return new Logfile::Rotate(
        File => get_logfile_path(),
        Count => 7,
        Gzip => 'lib',
        Post => sub {
            my ($new, $commpressed) = @_;
            info(__PACKAGE__, "logfile was rotated [new journal: $new, old journal: $commpressed.gz]");
        },
    );
}

sub __possibly_rotate {
    my $size = stat(get_logfile_path)->size;

    if ($size > $LOGFILE_LIMIT) {
        __get_rotator()->rotate();
    }
}

sub __verify {
    my $comp = shift;

    die "It is not a PVE::IntegrityControl component: '$comp'\n"
    if not $comp =~ m|^PVE::(API2::)?IntegrityControl|;
}

sub info {
    my ($comp, $what) = @_;
    __verify($comp);
    get_logger($comp)->info($what);
    __possibly_rotate();
}

sub debug {
    my ($comp, $what) = @_;
    __verify($comp);
    get_logger($comp)->debug($what);
    __possibly_rotate();
}

sub warn {
    my ($comp, $what) = @_;
    __verify($comp);
    get_logger($comp)->warn($what);
    __possibly_rotate();
}

sub error {
    my ($comp, $what) = @_;
    __verify($comp);
    get_logger($comp)->error($what);
    __possibly_rotate();
}

sub trace {
    my ($comp, $what) = @_;
    __verify($comp);
    get_logger($comp)->trace($what);
    __possibly_rotate();
}

1;
