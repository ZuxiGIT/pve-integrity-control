.PHONY: install
install:
	install -d ${DESTDIR}${PERLDIR}/PVE
	$(MAKE) -C API2 install
	$(MAKE) -C CLI install
	$(MAKE) -C IntegrityControl install
