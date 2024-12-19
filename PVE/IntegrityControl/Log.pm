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
);

Log::Log4perl->init_and_watch("/var/log/pve-integrity-control/log.conf", 60);

our $LOGFILE_LIMIT = 1024 * 1024 * 1024; # 1 Gb

sub __get_logfile_path {
    return Log::Log4perl::appenders()->{'LogFile'}->filename();
}

sub __get_rotator {
    return new Logfile::Rotate(
        File => __get_logfile_path(),
        Count => 7,
        Gzip => 'lib',
        Post => sub {
            my ($old, $new) = @_;
            info(__PACKAGE__, "logfile was rotated: oldfile:$old, newfile:$new");
        },
    );
}

sub __possibly_rotate {
    my $size = stat(__get_logfile_path)->size;

    if ($size > $LOGFILE_LIMIT) {
        __get_rotator()->rotate();
    }
}

sub __verify {
    my $comp = shift;

    die "It is not a PVE::IntegrityControl component: '$comp'\n"
    if not $comp =~ m|^PVE::IntegrityControl| and not $comp =~ m|^PVE::API2::IntegrityControl|;
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

1;
