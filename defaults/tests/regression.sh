#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

OURS=${OURS:-${REPO_ROOT}/defaults}
SOURCE=${SOURCE:-/usr/bin/defaults}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/defaults-compare.XXXXXX")
FIX="${ROOT}/fixtures"
PASS=0
FAIL=0
FAILED_CASES="${ROOT}/failed_cases.txt"

case "${OURS}" in
/*) ;;
*) OURS=${REPO_ROOT}/${OURS} ;;
esac

case "${SOURCE}" in
/*) ;;
*) SOURCE=${REPO_ROOT}/${SOURCE} ;;
esac

LIVE_DOMAIN=
LIVE_HOST_DOMAIN=
LIVE_TOKEN=
LIVE_HOST_TOKEN=
MISSING_TOKEN=

cleanup() {
	if [ -n "${LIVE_DOMAIN}" ]; then
		"${SOURCE}" delete "${LIVE_DOMAIN}" >/dev/null 2>&1 || true
	fi
	if [ -n "${LIVE_HOST_DOMAIN}" ]; then
		"${SOURCE}" -currentHost delete "${LIVE_HOST_DOMAIN}" >/dev/null 2>&1 || true
	fi
	if [ "${KEEP_TMP:-0}" != "1" ]; then
		rm -rf "${ROOT}"
	fi
}

trap cleanup EXIT INT TERM

if [ ! -x "${OURS}" ]; then
	printf 'missing built defaults: %s\n' "${OURS}" >&2
	exit 1
fi

if [ ! -x "${SOURCE}" ]; then
	printf 'missing oracle defaults: %s\n' "${SOURCE}" >&2
	exit 1
fi

mkdir -p "${FIX}"
: > "${FAILED_CASES}"

cat > "${FIX}/empty.plist" <<'EOF_EMPTY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF_EMPTY

cat > "${FIX}/dict.plist" <<'EOF_DICT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>old</key>
	<string>x</string>
	<key>stay</key>
	<string>y</string>
</dict>
</plist>
EOF_DICT

cat > "${FIX}/array.plist" <<'EOF_ARRAY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>items</key>
	<array>
		<string>a</string>
	</array>
</dict>
</plist>
EOF_ARRAY

cat > "${FIX}/map.plist" <<'EOF_MAP'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>map</key>
	<dict>
		<key>a</key>
		<string>1</string>
	</dict>
</dict>
</plist>
EOF_MAP

cat > "${FIX}/export-source.plist" <<'EOF_EXPORT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>x</key>
	<string>y</string>
</dict>
</plist>
EOF_EXPORT

cat > "${FIX}/import-input.plist" <<'EOF_IMPORT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>z</key>
	<integer>9</integer>
</dict>
</plist>
EOF_IMPORT

cat > "${FIX}/path with spaces.plist" <<'EOF_PATH'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>a</key>
	<integer>3</integer>
	<key>u</key>
	<string>Torrekie的MacBook Pro</string>
</dict>
</plist>
EOF_PATH

LIVE_DOMAIN="com.codex.defaults.regression.$$"
LIVE_HOST_DOMAIN="com.codex.defaults.regression.currenthost.$$"
LIVE_TOKEN="__codex_defaults_unique_$$__"
LIVE_HOST_TOKEN="__codex_defaults_host_$$__"
MISSING_TOKEN="__codex_defaults_missing_$$__"

cat > "${FIX}/live-domain.plist" <<EOF_LIVE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>token</key>
	<string>${LIVE_TOKEN}</string>
	<key>count</key>
	<integer>42</integer>
	<key>unicode</key>
	<string>Torrekie的MacBook Pro</string>
	<key>nested</key>
	<dict>
		<key>token</key>
		<string>${LIVE_TOKEN}</string>
	</dict>
</dict>
</plist>
EOF_LIVE

cat > "${FIX}/current-host.plist" <<EOF_HOST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>hostToken</key>
	<string>${LIVE_HOST_TOKEN}</string>
	<key>count</key>
	<integer>7</integer>
</dict>
</plist>
EOF_HOST

"${SOURCE}" delete "${LIVE_DOMAIN}" >/dev/null 2>&1 || true
"${SOURCE}" import "${LIVE_DOMAIN}" "${FIX}/live-domain.plist" >/dev/null 2>&1
"${SOURCE}" -currentHost delete "${LIVE_HOST_DOMAIN}" >/dev/null 2>&1 || true
"${SOURCE}" -currentHost import "${LIVE_HOST_DOMAIN}" "${FIX}/current-host.plist" >/dev/null 2>&1

normalize_stderr() {
	src=$1
	dst=$2
	sed -E 's/^[0-9-]+ [0-9:.]+ [^[]+\[[0-9]+:[0-9]+\] //' "${src}" > "${dst}"
}

canonical_plist() {
	path=$1
	if [ -e "${path}" ]; then
		plutil -convert xml1 -o - "${path}"
	else
		printf '__MISSING__\n'
	fi
}

record_pass() {
	PASS=$((PASS + 1))
}

record_fail() {
	FAIL=$((FAIL + 1))
	printf '%s\n' "$1" >> "${FAILED_CASES}"
}

run_command() {
	bin=$1
	out=$2
	err=$3
	shift 3
	set +e
	"${bin}" "$@" > "${out}" 2> "${err}"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${out}.exit"
	normalize_stderr "${err}" "${err}.normalized"
}

compare_case_files() {
	name=$1
	ours_prefix=$2
	sys_prefix=$3
	extra_a=${4:-}
	extra_b=${5:-}
	if cmp -s "${ours_prefix}.out.exit" "${sys_prefix}.out.exit" \
		&& cmp -s "${ours_prefix}.out" "${sys_prefix}.out" \
		&& cmp -s "${ours_prefix}.err.normalized" "${sys_prefix}.err.normalized" \
		&& { [ -z "${extra_a}" ] || cmp -s "${extra_a}" "${extra_b}"; }; then
		record_pass
	else
		record_fail "${name}"
	fi
}

case_command() {
	name=$1
	shift
	dir="${ROOT}/cases/${name}"
	mkdir -p "${dir}"
	run_command "${OURS}" "${dir}/ours.out" "${dir}/ours.err" "$@"
	run_command "${SOURCE}" "${dir}/sys.out" "${dir}/sys.err" "$@"
	compare_case_files "${name}" "${dir}/ours" "${dir}/sys"
}

case_mutation() {
	name=$1
	template=$2
	command=$3
	dir="${ROOT}/cases/${name}"
	domain="${dir}/domain.plist"
	mkdir -p "${dir}"
	cp "${template}" "${domain}"
	set +e
	DOM="${domain}" BIN="${SOURCE}" sh -c "${command}" > "${dir}/sys.out" 2> "${dir}/sys.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/sys.out.exit"
	normalize_stderr "${dir}/sys.err" "${dir}/sys.err.normalized"
	canonical_plist "${domain}" > "${dir}/sys.xml"
	cp "${template}" "${domain}"
	set +e
	DOM="${domain}" BIN="${OURS}" sh -c "${command}" > "${dir}/ours.out" 2> "${dir}/ours.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/ours.out.exit"
	normalize_stderr "${dir}/ours.err" "${dir}/ours.err.normalized"
	canonical_plist "${domain}" > "${dir}/ours.xml"
	compare_case_files "${name}" "${dir}/ours" "${dir}/sys" "${dir}/ours.xml" "${dir}/sys.xml"
}

case_import_file() {
	name=$1
	template=$2
	input=$3
	dir="${ROOT}/cases/${name}"
	domain="${dir}/domain.plist"
	import_file="${dir}/input.plist"
	mkdir -p "${dir}"
	cp "${template}" "${domain}"
	cp "${input}" "${import_file}"
	set +e
	DOM="${domain}" INPUT="${import_file}" BIN="${SOURCE}" sh -c '$BIN import "$DOM" "$INPUT"' > "${dir}/sys.out" 2> "${dir}/sys.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/sys.out.exit"
	normalize_stderr "${dir}/sys.err" "${dir}/sys.err.normalized"
	canonical_plist "${domain}" > "${dir}/sys.xml"
	cp "${template}" "${domain}"
	set +e
	DOM="${domain}" INPUT="${import_file}" BIN="${OURS}" sh -c '$BIN import "$DOM" "$INPUT"' > "${dir}/ours.out" 2> "${dir}/ours.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/ours.out.exit"
	normalize_stderr "${dir}/ours.err" "${dir}/ours.err.normalized"
	canonical_plist "${domain}" > "${dir}/ours.xml"
	compare_case_files "${name}" "${dir}/ours" "${dir}/sys" "${dir}/ours.xml" "${dir}/sys.xml"
}

case_import_stdin() {
	name=$1
	template=$2
	input=$3
	dir="${ROOT}/cases/${name}"
	domain="${dir}/domain.plist"
	mkdir -p "${dir}"
	cp "${template}" "${domain}"
	set +e
	cat "${input}" | "${SOURCE}" import "${domain}" - > "${dir}/sys.out" 2> "${dir}/sys.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/sys.out.exit"
	normalize_stderr "${dir}/sys.err" "${dir}/sys.err.normalized"
	canonical_plist "${domain}" > "${dir}/sys.xml"
	cp "${template}" "${domain}"
	set +e
	cat "${input}" | "${OURS}" import "${domain}" - > "${dir}/ours.out" 2> "${dir}/ours.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/ours.out.exit"
	normalize_stderr "${dir}/ours.err" "${dir}/ours.err.normalized"
	canonical_plist "${domain}" > "${dir}/ours.xml"
	compare_case_files "${name}" "${dir}/ours" "${dir}/sys" "${dir}/ours.xml" "${dir}/sys.xml"
}

case_export_file() {
	name=$1
	template=$2
	dir="${ROOT}/cases/${name}"
	domain="${dir}/domain.plist"
	output="${dir}/export.plist"
	mkdir -p "${dir}"
	cp "${template}" "${domain}"
	rm -f "${output}"
	set +e
	DOM="${domain}" OUTPUT="${output}" BIN="${SOURCE}" sh -c '$BIN export "$DOM" "$OUTPUT"' > "${dir}/sys.out" 2> "${dir}/sys.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/sys.out.exit"
	normalize_stderr "${dir}/sys.err" "${dir}/sys.err.normalized"
	canonical_plist "${output}" > "${dir}/sys.xml"
	cp "${template}" "${domain}"
	rm -f "${output}"
	set +e
	DOM="${domain}" OUTPUT="${output}" BIN="${OURS}" sh -c '$BIN export "$DOM" "$OUTPUT"' > "${dir}/ours.out" 2> "${dir}/ours.err"
	status=$?
	set -e
	printf '%s\n' "${status}" > "${dir}/ours.out.exit"
	normalize_stderr "${dir}/ours.err" "${dir}/ours.err.normalized"
	canonical_plist "${output}" > "${dir}/ours.xml"
	compare_case_files "${name}" "${dir}/ours" "${dir}/sys" "${dir}/ours.xml" "${dir}/sys.xml"
}

PATH_SPACE_FILE="${FIX}/path with spaces.plist"

case_command noArgs
case_command help help
case_command printHostIdentifier printHostIdentifier
case_command badCommand bogus
case_command domains domains
case_command readGlobalAlias read -globalDomain AppleLanguages
case_command currentHostRead -currentHost read "${LIVE_HOST_DOMAIN}"
case_command currentHostReadKey -currentHost read "${LIVE_HOST_DOMAIN}" hostToken
case_command currentHostReadType -currentHost read-type "${LIVE_HOST_DOMAIN}" count
case_command liveReadDomain read "${LIVE_DOMAIN}"
case_command liveReadKey read "${LIVE_DOMAIN}" token
case_command liveReadType read-type "${LIVE_DOMAIN}" count
case_command liveUnicodeRead read "${LIVE_DOMAIN}" unicode
case_command liveMissingKey read "${LIVE_DOMAIN}" "${MISSING_TOKEN}"
case_command findToken find "${LIVE_TOKEN}"
case_command findMiss find "${MISSING_TOKEN}"
case_command pathRead read "${PATH_SPACE_FILE}"
case_command pathReadKey read "${PATH_SPACE_FILE}" a
case_command pathReadUnicode read "${PATH_SPACE_FILE}" u
case_command pathReadType read-type "${PATH_SPACE_FILE}" a
case_command pathMissingKey read "${PATH_SPACE_FILE}" "${MISSING_TOKEN}"

case_mutation writeString "${FIX}/empty.plist" '$BIN write "$DOM" name -string hello'
case_mutation writeInt "${FIX}/empty.plist" '$BIN write "$DOM" count -int 42'
case_mutation writeFloat "${FIX}/empty.plist" '$BIN write "$DOM" ratio -float 1.25'
case_mutation writeBool "${FIX}/empty.plist" '$BIN write "$DOM" enabled -bool true'
case_mutation writeDate "${FIX}/empty.plist" '$BIN write "$DOM" when -date "2024-01-02 03:04:05 +0000"'
case_mutation writeDataUpper "${FIX}/empty.plist" '$BIN write "$DOM" blob -data 1234ABCD'
case_mutation writeDataLower "${FIX}/empty.plist" '$BIN write "$DOM" blob -data abcd'
case_mutation writeDataOddUpper "${FIX}/empty.plist" '$BIN write "$DOM" blob -data A'
case_mutation writeDataInvalid "${FIX}/empty.plist" '$BIN write "$DOM" blob -data 12ZG'
case_mutation writeArrayLiteral "${FIX}/empty.plist" '$BIN write "$DOM" arr "(one,two,three)"'
case_mutation writeDictLiteral "${FIX}/empty.plist" '$BIN write "$DOM" obj "{ one = 1; two = 2; }"'
case_mutation writeArrayExplicit "${FIX}/empty.plist" '$BIN write "$DOM" arr -array one two three'
case_mutation writeDictExplicit "${FIX}/empty.plist" '$BIN write "$DOM" obj -dict one 1 two 2'
case_mutation writeDomainRep "${FIX}/empty.plist" '$BIN write "$DOM" "{ root = 1; }"'
case_mutation arrayAdd "${FIX}/array.plist" '$BIN write "$DOM" items -array-add b'
case_mutation dictAdd "${FIX}/map.plist" '$BIN write "$DOM" map -dict-add b 2'
case_mutation renameKey "${FIX}/dict.plist" '$BIN rename "$DOM" old new'
case_mutation renameMissing "${FIX}/dict.plist" '$BIN rename "$DOM" __missing__ new'
case_mutation deleteKey "${FIX}/dict.plist" '$BIN delete "$DOM" old'
case_mutation removeKey "${FIX}/dict.plist" '$BIN remove "$DOM" old'
case_mutation deleteMissing "${FIX}/dict.plist" '$BIN delete "$DOM" __missing__'
case_mutation deleteDomain "${FIX}/dict.plist" '$BIN delete "$DOM"'
case_mutation badDictArity "${FIX}/empty.plist" '$BIN write "$DOM" obj -dict one 1 two'
case_mutation badArrayAddTarget "${FIX}/empty.plist" '$BIN write "$DOM" obj -array-add a'
case_mutation badDictAddTarget "${FIX}/empty.plist" '$BIN write "$DOM" obj -dict-add a 1'

case_import_file importFile "${FIX}/empty.plist" "${FIX}/import-input.plist"
case_import_stdin importStdin "${FIX}/empty.plist" "${FIX}/import-input.plist"
case_export_file exportFile "${FIX}/export-source.plist"
case_command exportStdout export "${FIX}/export-source.plist" -
case_command importMissing import "${FIX}/export-source.plist" "${ROOT}/__no_such_input__.plist"

printf 'SUMMARY pass=%s fail=%s\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" -ne 0 ]; then
	printf 'FAILURES:'
	tr '\n' ' ' < "${FAILED_CASES}"
	printf '\n'
	exit 1
fi
