PROG?=		defaults

TARGET?=	${PROG}
OBJS=		defaults.o

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation -framework CoreFoundation -lobjc
CODESIGN?=	codesign
CODESIGN_FLAGS?=	--force --sign - --entitlements defaults.entitlements --timestamp=none
LDID?=		ldid
LDID_FLAGS?=	-Sdefaults.entitlements

.PHONY: all check clean show-config

all: ${TARGET}

check: ${TARGET}
	OURS='${TARGET}' sh ./tests/regression.sh

show-config:
	@printf 'PROG=%s\n' '${PROG}'
	@printf 'CC=%s\n' '${CC}'
	@printf 'CPPFLAGS=%s\n' '${CPPFLAGS}'
	@printf 'CFLAGS=%s\n' '${CFLAGS}'
	@printf 'LDFLAGS=%s\n' '${LDFLAGS}'
	@printf 'TARGET=%s\n' '${TARGET}'
	@printf 'CODESIGN=%s\n' '${CODESIGN}'
	@printf 'CODESIGN_FLAGS=%s\n' '${CODESIGN_FLAGS}'
	@printf 'LDID=%s\n' '${LDID}'
	@printf 'LDID_FLAGS=%s\n' '${LDID_FLAGS}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}
	@if command -v '${CODESIGN}' >/dev/null 2>&1; then \
		'${CODESIGN}' ${CODESIGN_FLAGS} $@; \
	elif command -v '${LDID}' >/dev/null 2>&1; then \
		'${LDID}' ${LDID_FLAGS} $@; \
	else \
		printf 'missing signing tool: %s or %s\n' '${CODESIGN}' '${LDID}' >&2; \
		exit 1; \
	fi

defaults.o: defaults.m
	${CC} ${COMPILE_FLAGS} -c defaults.m -o $@

clean:
	rm -f ${OBJS} ${TARGET}
