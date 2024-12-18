use PVE::IntegrityControl::Log qw(info warn debug error);

print "--> test info:\n";
eval { info ("test info", "test"); };
print $@;

print "--> test warn:\n";
eval { warn ("test warn", "test"); };
print $@;

print "--> test error:\n";
eval { error ("test error", "test"); };
print $@;

print "--> test debug:\n";
eval { debug ("test debug", "test"); };
print $@;
