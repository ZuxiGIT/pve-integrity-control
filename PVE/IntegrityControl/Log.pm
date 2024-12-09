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

my $LOGFILE_LIMIT = 1024 * 1024 * 1024; # 1 Gb

my $rotator;

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

sub info {
    my ($comp, $what) = @_;
    __possibly_rotate();
    get_logger($comp)->info($what);
}

sub debug {
    my ($comp, $what) = @_;
    __possibly_rotate();
    get_logger($comp)->debug($what);
}

sub warn {
    my ($comp, $what) = @_;
    __possibly_rotate();
    get_logger($comp)->warn($what);
}

sub error {
    my ($comp, $what) = @_;
    __possibly_rotate();
    get_logger($comp)->error($what);
}

1;
