PROG?=		plutil

SRCS=		main.m \
		PLUContext.m \
		PLUMutableArray.m \
		PLUMutableDictionary.m
HDRS=		PLUContext.h \
		PLUMutableArray.h \
		PLUMutableDictionary.h
TARGET?=	${PROG}
OBJS=		main.o \
		PLUContext.o \
		PLUMutableArray.o \
		PLUMutableDictionary.o

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation -framework CoreFoundation -lobjc

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

main.o: main.m PLUContext.h
	${CC} ${COMPILE_FLAGS} -c main.m -o $@

PLUContext.o: PLUContext.m ${HDRS}
	${CC} ${COMPILE_FLAGS} -c PLUContext.m -o $@

PLUMutableArray.o: PLUMutableArray.m PLUMutableArray.h
	${CC} ${COMPILE_FLAGS} -c PLUMutableArray.m -o $@

PLUMutableDictionary.o: PLUMutableDictionary.m PLUMutableDictionary.h
	${CC} ${COMPILE_FLAGS} -c PLUMutableDictionary.m -o $@

clean:
	rm -f ${OBJS} ${TARGET}
