PROG?=		pl

SRCS=		pl.m
TARGET?=	${PROG}
OBJS=		pl.o

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation -lobjc

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

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}

pl.o: pl.m
	${CC} ${COMPILE_FLAGS} -c pl.m -o $@

clean:
	rm -f ${OBJS} ${TARGET}
