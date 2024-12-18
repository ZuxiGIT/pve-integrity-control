#!/usr/bin/perl

use strict;
use warnings;

use DDP;
use Benchmark;
use Benchmark ':hireswallclock';
use Time::HiRes;

use PVE::IntegrityControl::Checker;
use PVE::IntegrityControl::GuestFS;

# First argument is the vmid
my $vmid = shift;

# Second argument is the testfile
my $file = shift;

# Third argument is the number of iterations
my $iters = shift;

print "number of iterations: $iters\n";
print "file to read: $file\n";
print "Vmid: $vmid\n";

# flush STDOUT
select()->autoflush();


my $res;
PVE::IntegrityControl::GuestFS::mount_vm_disks($vmid);
PVE::IntegrityControl::Checker::__init_openssl_gost_engine();
my %file_stat = PVE::IntegrityControl::GuestFS::__test_stat_file($file);
my $file_size = sprintf("%.3f", $file_stat{st_size} / 1024 / 1024);
print "file size: $file_size Mb\n";


print "--------> benchmarks <--------\n";
my $start = Time::HiRes::time();

print "reading file without dropping cache after reading: ";
$res = timeit($iters, sub {
        PVE::IntegrityControl::GuestFS::__test_read_file($file);
});
print "ellapsed time ", $res->real, "sec\n";
my $r_wo_d = $res->real;

print "reading file with dropping cache after reading: ";
$res = timeit($iters, sub {
        PVE::IntegrityControl::GuestFS::__test_read_file($file);
        PVE::IntegrityControl::GuestFS::__test_drop_caches(1);
});
print "ellapsed time ", $res->real, "sec\n";
my $r_w_d = $res->real;

my $file_content = PVE::IntegrityControl::GuestFS::__test_read_file($file);
print "calculating file hash: ";
$res = timeit($iters, sub { PVE::IntegrityControl::Checker::__get_hash($file_content);});
print "ellapsed time ", $res->real, "sec\n";
my $h = $res->real;

my $end = Time::HiRes::time();
my $total = $end - $start;

print "--------> results <--------\n";
print "reading w/ drop cache / hashing: ", $r_w_d / $h, "\n";
print "reading w/o drop cache / hashing: ", $r_wo_d / $h, "\n";
print "total benchmarks time: $total s\n";

PVE::IntegrityControl::GuestFS::umount_vm_disks($vmid);
