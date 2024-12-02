PERLSOURCES = 	\
	DB.pm		\
	Log.pm		\
	Checker.pm	\
	GuestFS.pm	\

.PHONY: install
install: ${PERLSOURCES}
	for i in ${PERLSOURCES}; do install -D -m 0644 $$i ${DESTDIR}${PERLDIR}/PVE/IntegrityControl/$$i; done
	install -D -m 0644 log.conf /var/log/pve-integrity-control/log.conf
