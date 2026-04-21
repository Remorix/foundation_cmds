SUBDIRS=	pl plutil

.PHONY: all check clean show-config

all check clean show-config:
	@for subdir in ${SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done
