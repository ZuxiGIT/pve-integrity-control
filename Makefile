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

.PHONY:
test-%:
	$(MAKE) -C tests $*

.PHONY:
bench-%:
	$(MAKE) -C bench $*

.PHONY:
generate-testfiles:
	apt install -y libtext-lorem-perl
	perl scripts/generate_testfiles.pl $(vmid)

.PHONY: check-pve-version
check-pve-version:
	pveversion | awk -F '/' '{print $$2}'

.PHONY: deps-install
deps-install:
	scripts/install_deps.sh

.PHONY: patches-install
patches-install:
	scripts/install_patches.sh

.PHONY: full-install
full-install: deps-install patches-install install
