# include /usr/share/dpkg/default.mk

PACKAGE=integrity-control
BUILDDIR ?= $(PACKAGE)-$(DEB_VERSION_UPSTREAM)

DESTDIR=
PREFIX=/usr
SBINDIR=$(PREFIX)/sbin
LIBDIR=$(PREFIX)/lib/$(PACKAGE)
MANDIR=$(PREFIX)/share/man
DOCDIR=$(PREFIX)/share/doc
MAN1DIR=$(MANDIR)/man1/
MAN5DIR=$(MANDIR)/man5/
BASHCOMPLDIR=$(PREFIX)/share/bash-completion/completions/
ZSHCOMPLDIR=$(PREFIX)/share/zsh/vendor-completions/
export PERLDIR=$(PREFIX)/share/perl5
PERLINCDIR=$(PERLDIR)/asm-x86_64

GITVERSION:=$(shell git rev-parse HEAD)

# DEB=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION)_$(DEB_BUILD_ARCH).deb
# DBG_DEB=$(PACKAGE)-dbgsym_$(DEB_VERSION_UPSTREAM_REVISION)_$(DEB_BUILD_ARCH).deb
# DSC=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION).dsc
#
# DEBS=$(DEB) $(DBG_DEB)

# include /usr/share/pve-doc-generator/pve-doc-generator.mk

all:

# .PHONY: dinstall
# dinstall: deb
# 	dpkg -i $(DEB)

ic.bash-completion:
# T.B.D.
# 	PVE_GENERATING_DOCS=1 perl -I. -T -e "use PVE::CLI::qm; PVE::CLI::qm->generate_bash_completions();" >$@.tmp
# 	mv $@.tmp $@

PKGSOURCES=ic #ic.conf.5 ic.bash-completion

.PHONY: install_hookscript
install_hookscript:
	perl scripts/install_hookscript.pl


.PHONY: install
install: $(PKGSOURCES) install_hookscript
	install -d $(DESTDIR)/$(SBINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)/$(MAN1DIR)
	install -d $(DESTDIR)/$(MAN5DIR)
	install -d $(DESTDIR)/usr/share/$(PACKAGE)
	# install -m 0644 -D ic.bash-completion $(DESTDIR)/$(BASHCOMPLDIR)/ic
	$(MAKE) -C PVE install
	install -m 0755 ic $(DESTDIR)$(SBINDIR)
	# install -m 0755 qm $(DESTDIR)$(SBINDIR)
	# install -m 0755 qmrestore $(DESTDIR)$(SBINDIR)
	# install -D -m 0644 modules-load.conf $(DESTDIR)/etc/modules-load.d/qemu-server.conf
	# install -m 0755 qmextract $(DESTDIR)$(LIBDIR)
	# install -m 0644 qm.1 $(DESTDIR)/$(MAN1DIR)
	# install -m 0644 qmrestore.1 $(DESTDIR)/$(MAN1DIR)
	# install -m 0644 cpu-models.conf.5 $(DESTDIR)/$(MAN5DIR)
	# install -m 0644 qm.conf.5 $(DESTDIR)/$(MAN5DIR)
	# cd $(DESTDIR)/$(MAN5DIR); ln -s -f qm.conf.5.gz vm.conf.5.gz

$(BUILDDIR):
	rm -rf $(BUILDDIR) $(BUILDDIR).tmp
	rsync -a * $(BUILDDIR).tmp
	echo "git clone git://git.proxmox.com/git/qemu-server.git\\ngit checkout $(GITVERSION)" > $(BUILDDIR).tmp/debian/SOURCE
	mv $(BUILDDIR).tmp $(BUILDDIR)

.PHONY: deb
deb: $(DEBS)
$(DBG_DEB): $(DEB)
$(DEB): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -us -uc
	lintian $(DEBS)

.PHONY: dsc
dsc: $(DSC)
$(DSC): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -S -us -uc -d
	lintian $(DSC)

sbuild: $(DSC)
	sbuild $(DSC)

.PHONY: test
test:
	PVE_GENERATING_DOCS=1 perl -I. ./ic verifyapi
	$(MAKE) -C test

.PHONY: upload
upload: UPLOAD_DIST ?= $(DEB_DISTRIBUTION)
upload: $(DEB)
	tar cf - $(DEBS) | ssh -X repoman@repo.proxmox.com upload --product pve --dist $(UPLOAD_DIST)

.PHONY: clean
clean:
	$(MAKE) -C test $@
	rm -rf $(PACKAGE)-*/ *.deb *.build *.buildinfo *.changes *.dsc $(PACKAGE)_*.tar.?z
	rm -f *.xml.tmp *.1 *.5 *.8 *{synopsis,opts}.adoc docinfo.xml


.PHONY: distclean
distclean: clean
