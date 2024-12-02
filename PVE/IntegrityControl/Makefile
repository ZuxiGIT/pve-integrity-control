PERLSOURCES = 	\
	DB.pm		\
	Checker.pm	\
	GuestFS.pm	\

.PHONY: install
install: ${PERLSOURCES}
	for i in ${PERLSOURCES}; do install -D -m 0644 $$i ${DESTDIR}${PERLDIR}/PVE/IntegrityControl/$$i; done
