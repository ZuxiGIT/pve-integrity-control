use PVE::IntegrityControl::Log qw(info warn debug error);

print "--> test logger message is meaningless, so let's test component name\n";

print "--> component name: test info\n";
eval { info ("test info", "test"); };
print $@;

print "--> component name: test warn\n";
eval { warn ("test warn", "test"); };
print $@;

print "--> component name: test error\n";
eval { error ("test error", "test"); };
print $@;

print "--> component name: test debug\n";
eval { debug ("test debug", "test"); };
print $@;
