use strict;
use warnings;

use bytes;

use Text::Lorem;
use PVE::IntegrityControl::Log qw(info);


$PVE::IntegrityControl::Log::LOGFILE_LIMIT = 200;
print "--> Set journal memory limit to 200 bytes\n";
print "--> Start writting to journal 300 bytes of text\n";

my $text = Text::Lorem->new();

my $words .= $text->words(5);
while (bytes::length($words) < 300) {
    $words .= $text->words(5);
}

print "--> text to write: [$words]\n";

info("PVE::IntegrityControl::TEST_LOGGER", $words);

print "--> wrote ", bytes::length($words), " bytes of text\n";
