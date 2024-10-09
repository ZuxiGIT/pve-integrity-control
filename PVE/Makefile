# PERLSOURCE =

.PHONY: install
install:
	install -d ${DESTDIR}${PERLDIR}/PVE
	# install -m 0644 ${PERLSOURCE} ${DESTDIR}${PERLDIR}/PVE/
	$(MAKE) -C API2 install
	$(MAKE) -C CLI install
