PACKAGE=integrity-control
BUILDDIR ?= $(PACKAGE)-$(DEB_VERSION_UPSTREAM)

DESTDIR=
PREFIX=/usr
SBINDIR=$(PREFIX)/sbin
LIBDIR=$(PREFIX)/lib/$(PACKAGE)
export PERLDIR=$(PREFIX)/share/perl5
PERLINCDIR=$(PERLDIR)/asm-x86_64


all:

PKGSOURCES=ic

.PHONY: install_hookscript
install_hookscript:
	perl scripts/install_hookscript.pl

.PHONY: install
install: $(PKGSOURCES) install_hookscript
	install -d $(DESTDIR)/$(SBINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)/usr/share/$(PACKAGE)
	$(MAKE) -C PVE install
	install -m 0755 ic $(DESTDIR)$(SBINDIR)

.PHONY: test
test:
	PVE_GENERATING_DOCS=1 perl -I. ./ic verifyapi
	# $(MAKE) -C test

.PHONY: deps-install
deps-install:
	apt install -y libdata-printer-perl
	apt install -y libguestfs-perl
	apt install -y liblog-log4perl-perl
	apt install -y libengine-gost-openssl

.PHONY: full-install
full-install: deps-install install
