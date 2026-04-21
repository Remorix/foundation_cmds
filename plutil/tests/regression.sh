#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

OURS=${OURS:-${REPO_ROOT}/build/host/plutil}
SYS=${SYS:-/usr/bin/plutil}
HOST_CC=${HOST_CC:-cc}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/plutil-matrix.XXXXXX")
FIX="${ROOT}/fixtures"
FAILED_CASES="${ROOT}/failed_cases.txt"
PASS=0
FAIL=0

case "${OURS}" in
/*) ;;
*) OURS=${REPO_ROOT}/${OURS} ;;
esac

case "${SYS}" in
/*) ;;
*) SYS=${REPO_ROOT}/${SYS} ;;
esac

cleanup() {
	if [ "${KEEP_TMP:-0}" != "1" ]; then
		rm -rf "${ROOT}"
	fi
}

trap cleanup EXIT INT TERM

if [ ! -x "${SYS}" ]; then
	printf 'missing system plutil: %s\n' "${SYS}" >&2
	exit 1
fi

if [ ! -x "${OURS}" ]; then
	printf 'missing built plutil: %s\n' "${OURS}" >&2
	exit 1
fi

if ! command -v "${HOST_CC}" >/dev/null 2>&1; then
	printf 'missing host compiler: %s\n' "${HOST_CC}" >&2
	exit 1
fi

mkdir -p "${FIX}"
: > "${FAILED_CASES}"

cat > "${FIX}/jsonsafe.plist" <<'EOF_JSONSAFE'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>name</key>
    <string>Alice "Q" \\ slash</string>
    <key>count</key>
    <integer>42</integer>
    <key>flag</key>
    <true/>
    <key>ratio</key>
    <real>3.25</real>
    <key>nested</key>
    <dict>
        <key>k</key>
        <string>v</string>
        <key>a.b</key>
        <string>dot</string>
        <key>list</key>
        <array>
            <string>x</string>
            <integer>7</integer>
            <false/>
        </array>
    </dict>
    <key>items</key>
    <array>
        <string>head</string>
        <dict>
            <key>sub</key>
            <string>value</string>
        </dict>
        <integer>5</integer>
    </array>
</dict>
</plist>
EOF_JSONSAFE

cat > "${FIX}/complex.plist" <<'EOF_COMPLEX'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>name</key>
    <string>Alice "Q" \\ slash</string>
    <key>count</key>
    <integer>42</integer>
    <key>flag</key>
    <true/>
    <key>ratio</key>
    <real>3.25</real>
    <key>when</key>
    <date>2024-01-02T03:04:05Z</date>
    <key>blob</key>
    <data>AQIDBA==</data>
    <key>nested</key>
    <dict>
        <key>k</key>
        <string>v</string>
        <key>a.b</key>
        <string>dot</string>
        <key>list</key>
        <array>
            <string>x</string>
            <integer>7</integer>
            <false/>
        </array>
    </dict>
    <key>items</key>
    <array>
        <string>head</string>
        <dict>
            <key>sub</key>
            <string>value</string>
        </dict>
        <integer>5</integer>
    </array>
</dict>
</plist>
EOF_COMPLEX

cat > "${FIX}/array-root.plist" <<'EOF_ARRAY_ROOT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>sub</key>
        <string>value</string>
    </dict>
    <string>tail</string>
    <integer>7</integer>
</array>
</plist>
EOF_ARRAY_ROOT

cat > "${FIX}/scalar-string.plist" <<'EOF_SCALAR_STRING'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<string>Line1
Line2 "quote" \\ slash</string>
</plist>
EOF_SCALAR_STRING

cat > "${FIX}/valid.json" <<'EOF_VALID_JSON'
{"name":"Alice \"Q\" \\\\ slash","count":42,"flag":true,"ratio":3.25,"nested":{"k":"v","a.b":"dot","list":["x",7,false]},"items":["head",{"sub":"value"},5]}
EOF_VALID_JSON

cat > "${FIX}/invalid.plist" <<'EOF_INVALID_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>oops</key><string>broken</dict></plist>
EOF_INVALID_PLIST

cat > "${FIX}/invalid.json" <<'EOF_INVALID_JSON'
{"broken":
EOF_INVALID_JSON

cp "${FIX}/jsonsafe.plist" "${FIX}/-leading.plist"
cp "${FIX}/jsonsafe.plist" "${FIX}/second.plist"

cat > "${FIX}/macho-main.c" <<'EOF_MACHO_MAIN'
int main(void) { return 0; }
EOF_MACHO_MAIN

cat > "${FIX}/macho-dylib.c" <<'EOF_MACHO_DYLIB'
int exported(void) { return 42; }
EOF_MACHO_DYLIB

cat > "${FIX}/embedded-exec.plist" <<'EOF_EMBEDDED_EXEC'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.test.exec</string>
    <key>CFBundleName</key>
    <string>ExecProbe</string>
</dict>
</plist>
EOF_EMBEDDED_EXEC

cat > "${FIX}/embedded-dylib.plist" <<'EOF_EMBEDDED_DYLIB'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.test.dylib</string>
    <key>CFBundleName</key>
    <string>DylibProbe</string>
</dict>
</plist>
EOF_EMBEDDED_DYLIB

"${HOST_CC}" "${FIX}/macho-main.c" -o "${FIX}/plain-exec"
"${HOST_CC}" "${FIX}/macho-main.c" "-Wl,-sectcreate,__TEXT,__info_plist,${FIX}/embedded-exec.plist" -o "${FIX}/embedded-exec"
"${HOST_CC}" -dynamiclib "${FIX}/macho-dylib.c" -o "${FIX}/plain.dylib"
"${HOST_CC}" -dynamiclib "${FIX}/macho-dylib.c" "-Wl,-sectcreate,__TEXT,__info_plist,${FIX}/embedded-dylib.plist" -o "${FIX}/embedded.dylib"

record_pass() {
	PASS=$((PASS + 1))
}

record_fail() {
	FAIL=$((FAIL + 1))
	printf '%s :: %s\n' "$1" "$2" >> "${FAILED_CASES}"
}

append_case_failure() {
	if [ -z "${CASE_FAILURES}" ]; then
		CASE_FAILURES=$1
	else
		CASE_FAILURES="${CASE_FAILURES}; $1"
	fi
}

new_case() {
	CASE_NAME=$1
	CASE_DIR="${ROOT}/cases/${CASE_NAME}"
	CASE_FAILURES=
	mkdir -p "${CASE_DIR}/sys" "${CASE_DIR}/ours"
	cp "${FIX}"/* "${CASE_DIR}/sys/"
	cp "${FIX}"/* "${CASE_DIR}/ours/"
}

run_one() {
	bin=$1
	dir=$2
	prefix=$3
	stdin_file=$4
	shift 4

	if [ -n "${stdin_file}" ]; then
		if (cd "${dir}" && "${bin}" "$@") < "${stdin_file}" > "${prefix}.stdout" 2> "${prefix}.stderr"; then
			status=0
		else
			status=$?
		fi
	else
		if (cd "${dir}" && "${bin}" "$@") > "${prefix}.stdout" 2> "${prefix}.stderr"; then
			status=0
		else
			status=$?
		fi
	fi

	printf '%s\n' "${status}" > "${prefix}.exit"
}

compare_streams() {
	case_name=$1

	if ! cmp -s "${CASE_DIR}/sys/run.exit" "${CASE_DIR}/ours/run.exit"; then
		append_case_failure "exit status differs"
	fi

	if ! cmp -s "${CASE_DIR}/sys/run.stdout" "${CASE_DIR}/ours/run.stdout"; then
		append_case_failure "stdout differs"
	fi

	if ! cmp -s "${CASE_DIR}/sys/run.stderr" "${CASE_DIR}/ours/run.stderr"; then
		append_case_failure "stderr differs"
	fi

	:
}

compare_file_exact() {
	case_name=$1
	rel=$2

	if [ ! -e "${CASE_DIR}/sys/${rel}" ] || [ ! -e "${CASE_DIR}/ours/${rel}" ]; then
		append_case_failure "expected file missing: ${rel}"
		return
	fi

	if ! cmp -s "${CASE_DIR}/sys/${rel}" "${CASE_DIR}/ours/${rel}"; then
		append_case_failure "file differs: ${rel}"
	fi

	:
}

compare_file_xmlnorm() {
	case_name=$1
	rel=$2

	if [ ! -e "${CASE_DIR}/sys/${rel}" ] || [ ! -e "${CASE_DIR}/ours/${rel}" ]; then
		append_case_failure "expected file missing: ${rel}"
		return
	fi

	if ! "${SYS}" -convert xml1 -o "${CASE_DIR}/sys/normalized.xml" "${CASE_DIR}/sys/${rel}" >/dev/null 2>&1; then
		append_case_failure "system output not normalizable: ${rel}"
		return
	fi

	if ! "${SYS}" -convert xml1 -o "${CASE_DIR}/ours/normalized.xml" "${CASE_DIR}/ours/${rel}" >/dev/null 2>&1; then
		append_case_failure "our output not normalizable: ${rel}"
		return
	fi

	if ! cmp -s "${CASE_DIR}/sys/normalized.xml" "${CASE_DIR}/ours/normalized.xml"; then
		append_case_failure "normalized file differs: ${rel}"
	fi

	:
}

finish_case() {
	case_name=$1

	if [ -n "${CASE_FAILURES}" ]; then
		record_fail "${case_name}" "${CASE_FAILURES}"
	else
		record_pass
	fi
}

case_stream() {
	case_name=$1
	stdin_rel=$2
	shift 2

	new_case "${case_name}"
	stdin_abs=
	if [ -n "${stdin_rel}" ]; then
		stdin_abs="${FIX}/${stdin_rel}"
	fi

	run_one "${SYS}" "${CASE_DIR}/sys" "${CASE_DIR}/sys/run" "${stdin_abs}" "$@"
	run_one "${OURS}" "${CASE_DIR}/ours" "${CASE_DIR}/ours/run" "${stdin_abs}" "$@"
	compare_streams "${case_name}"
	finish_case "${case_name}"
}

case_stream_and_exact_files() {
	case_name=$1
	stdin_rel=$2
	filespec=$3
	shift 3

	new_case "${case_name}"
	stdin_abs=
	if [ -n "${stdin_rel}" ]; then
		stdin_abs="${FIX}/${stdin_rel}"
	fi

	run_one "${SYS}" "${CASE_DIR}/sys" "${CASE_DIR}/sys/run" "${stdin_abs}" "$@"
	run_one "${OURS}" "${CASE_DIR}/ours" "${CASE_DIR}/ours/run" "${stdin_abs}" "$@"
	compare_streams "${case_name}"

	for rel in ${filespec}; do
		compare_file_exact "${case_name}" "${rel}"
	done

	finish_case "${case_name}"
}

case_stream_and_xml_files() {
	case_name=$1
	stdin_rel=$2
	filespec=$3
	shift 3

	new_case "${case_name}"
	stdin_abs=
	if [ -n "${stdin_rel}" ]; then
		stdin_abs="${FIX}/${stdin_rel}"
	fi

	run_one "${SYS}" "${CASE_DIR}/sys" "${CASE_DIR}/sys/run" "${stdin_abs}" "$@"
	run_one "${OURS}" "${CASE_DIR}/ours" "${CASE_DIR}/ours/run" "${stdin_abs}" "$@"
	compare_streams "${case_name}"

	for rel in ${filespec}; do
		compare_file_xmlnorm "${case_name}" "${rel}"
	done

	finish_case "${case_name}"
}

case_stream help '' -help
case_stream no-args ''
case_stream convert-missing-format '' -convert
case_stream convert-unknown-format '' -convert nope jsonsafe.plist
case_stream convert-missing-o-arg '' -convert json -o jsonsafe.plist
case_stream convert-missing-e-arg '' -convert json -e jsonsafe.plist
case_stream convert-bad-option '' -convert json -z jsonsafe.plist
case_stream lint-valid '' -lint jsonsafe.plist
case_stream lint-silent '' -lint -s jsonsafe.plist
case_stream lint-stdin jsonsafe.plist -lint -
case_stream lint-invalid '' -lint invalid.plist
case_stream lint-multi-mixed '' -lint jsonsafe.plist invalid.plist
case_stream lint-bad-option '' -lint -o out jsonsafe.plist
case_stream print-valid '' -p jsonsafe.plist
case_stream print-stdin jsonsafe.plist -p -
case_stream print-with-s '' -p -s jsonsafe.plist
case_stream print-invalid '' -p invalid.plist
case_stream print-bad-option '' -p -o out jsonsafe.plist
case_stream print-dashfile '' -p -- -leading.plist
case_stream print-executable-no-info '' -p plain-exec
case_stream print-executable-with-info '' -p embedded-exec
case_stream print-dylib-no-info '' -p plain.dylib
case_stream print-dylib-with-info '' -p embedded.dylib
case_stream convert-xml1-stdout '' -convert xml1 -o - valid.json
case_stream_and_xml_files convert-binary1-inplace '' 'jsonsafe.plist' -convert binary1 jsonsafe.plist
case_stream convert-json-stdout '' -convert json -o - jsonsafe.plist
case_stream convert-json-pretty '' -convert json -r -o - jsonsafe.plist
case_stream convert-swift-stdout '' -convert swift -o - complex.plist
case_stream convert-objc-stdout '' -convert objc -o - complex.plist
case_stream_and_exact_files convert-objc-header-dict '' 'Model.m Model.h' -convert objc -header -o Model.m jsonsafe.plist
case_stream_and_exact_files convert-objc-header-array '' 'ArrayModel.m ArrayModel.h' -convert objc -header -o ArrayModel.m array-root.plist
case_stream convert-swift-scalar '' -convert swift -o - scalar-string.plist
case_stream convert-objc-scalar '' -convert objc -o - scalar-string.plist
case_stream_and_xml_files convert-e-one '' 'jsonsafe.out' -convert json -e out jsonsafe.plist
case_stream_and_xml_files convert-e-multi '' 'jsonsafe.out second.out' -convert json -e out jsonsafe.plist second.plist
case_stream convert-stdin-json valid.json -convert json -o - -
case_stream convert-dashfile '' -convert json -o - -- -leading.plist
case_stream convert-invalid-input '' -convert xml1 invalid.json
case_stream convert-jsoninput-xml '' -convert xml1 -o - valid.json
case_stream convert-jsoninput-swift '' -convert swift -o - valid.json
case_stream create-xml1 '' -create xml1 -
case_stream create-json '' -create json -
case_stream create-swift '' -create swift -
case_stream create-objc '' -create objc -
case_stream_and_xml_files create-binary1-file '' 'created.plist' -create binary1 created.plist
case_stream type-name '' -type name jsonsafe.plist
case_stream type-name-no-newline '' -type name -n jsonsafe.plist
case_stream type-expect-bool '' -type flag -expect bool jsonsafe.plist
case_stream type-expect-int '' -type count -expect integer jsonsafe.plist
case_stream type-expect-float '' -type ratio -expect float jsonsafe.plist
case_stream type-expect-string '' -type name -expect string jsonsafe.plist
case_stream type-expect-date '' -type when -expect date complex.plist
case_stream type-expect-data '' -type blob -expect data complex.plist
case_stream type-expect-dict '' -type nested -expect dictionary jsonsafe.plist
case_stream type-expect-array '' -type items -expect array jsonsafe.plist
case_stream type-expect-mismatch '' -type count -expect string jsonsafe.plist
case_stream type-invalid-expect '' -type count -expect nope jsonsafe.plist
case_stream type-missing-key '' -type missing jsonsafe.plist
case_stream extract-name-raw '' -extract name raw jsonsafe.plist
case_stream extract-count-raw-n '' -extract count raw -n jsonsafe.plist
case_stream extract-flag-raw '' -extract flag raw jsonsafe.plist
case_stream extract-ratio-raw '' -extract ratio raw jsonsafe.plist
case_stream extract-date-raw '' -extract when raw complex.plist
case_stream extract-data-raw '' -extract blob raw complex.plist
case_stream extract-dict-raw '' -extract nested raw jsonsafe.plist
case_stream extract-array-raw '' -extract items raw jsonsafe.plist
case_stream extract-nested-json '' -extract nested json -o - jsonsafe.plist
case_stream extract-nested-xml '' -extract nested xml1 -o - jsonsafe.plist
case_stream_and_xml_files extract-nested-binary '' 'jsonsafe.plist' -extract nested binary1 jsonsafe.plist
case_stream extract-expect-dict '' -extract nested json -expect dictionary -o - jsonsafe.plist
case_stream extract-expect-array '' -extract items json -expect array -o - jsonsafe.plist
case_stream extract-expect-mismatch '' -extract nested json -expect array -o - jsonsafe.plist
case_stream extract-invalid-expect '' -extract nested json -expect nope jsonsafe.plist
case_stream extract-missing-key '' -extract missing raw jsonsafe.plist
case_stream extract-string-json-invalid '' -extract name json -o - jsonsafe.plist
case_stream_and_xml_files insert-string '' 'jsonsafe.plist' -insert nested.new -string value jsonsafe.plist
case_stream_and_xml_files replace-string '' 'jsonsafe.plist' -replace nested.k -string replaced jsonsafe.plist
case_stream_and_xml_files remove-key '' 'jsonsafe.plist' -remove nested.k jsonsafe.plist
case_stream_and_xml_files insert-append-items '' 'jsonsafe.plist' -insert items -string tail -append jsonsafe.plist
case_stream_and_xml_files insert-index-items '' 'jsonsafe.plist' -insert items.1 -string middle jsonsafe.plist
case_stream_and_xml_files insert-bool '' 'jsonsafe.plist' -insert nested.truth -bool YES jsonsafe.plist
case_stream_and_xml_files insert-int '' 'jsonsafe.plist' -insert nested.answer -integer 123 jsonsafe.plist
case_stream_and_xml_files insert-float '' 'jsonsafe.plist' -insert nested.pi -float 3.5 jsonsafe.plist
case_stream_and_xml_files insert-date '' 'complex.plist' -insert nested.when2 -date 2024-01-02T03:04:05Z complex.plist
case_stream_and_xml_files insert-data '' 'jsonsafe.plist' -insert nested.blob2 -data AQID jsonsafe.plist
case_stream_and_xml_files insert-xml '' 'jsonsafe.plist' -insert nested.compound -xml '<plist version="1.0"><array><string>x</string></array></plist>' jsonsafe.plist
case_stream_and_xml_files insert-json '' 'jsonsafe.plist' -insert nested.compound -json '{"a":1,"b":[true]}' jsonsafe.plist
case_stream_and_xml_files insert-dictionary '' 'jsonsafe.plist' -insert nested.emptyDict -dictionary jsonsafe.plist
case_stream_and_xml_files insert-array '' 'jsonsafe.plist' -insert nested.emptyArray -array jsonsafe.plist
case_stream_and_xml_files replace-escaped-dot '' 'jsonsafe.plist' -replace nested.a\\.b -string changed jsonsafe.plist
case_stream insert-existing-fails '' -insert nested.k -string nope jsonsafe.plist
case_stream_and_xml_files replace-missing '' 'jsonsafe.plist' -replace nested.missing -string created jsonsafe.plist
case_stream remove-missing '' -remove nested.missing jsonsafe.plist
case_stream insert-invalid-data '' -insert nested.bad -data '!!!' jsonsafe.plist
case_stream insert-invalid-date '' -insert nested.bad -date nope jsonsafe.plist
case_stream_and_xml_files insert-jsoninput-preserve '' 'valid.json' -insert nested.new -string value valid.json
case_stream_and_xml_files replace-jsoninput-preserve '' 'valid.json' -replace nested.k -string value valid.json
case_stream_and_xml_files remove-jsoninput-preserve '' 'valid.json' -remove nested.k valid.json
case_stream_and_xml_files append-existing-array-keypath '' 'jsonsafe.plist' -insert nested.list -string tail -append jsonsafe.plist
case_stream insert-nonarray-index '' -insert nested.k.0 -string nope jsonsafe.plist

printf 'SUMMARY pass=%s fail=%s root=%s\n' "${PASS}" "${FAIL}" "${ROOT}"
if [ "${FAIL}" -ne 0 ]; then
	sed -n '1,200p' "${FAILED_CASES}"
	exit 1
fi
