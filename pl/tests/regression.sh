#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

OURS=${OURS:-${REPO_ROOT}/pl}
SOURCE=${SOURCE:-}
REFERENCE_DIR=${REFERENCE_DIR:-${SCRIPT_DIR}/reference}
GENERATE_REFERENCE=${GENERATE_REFERENCE:-0}
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pl-compare.XXXXXX")
FIX="${ROOT}/fixtures"
FAILED_CASES="${ROOT}/failed_cases.txt"
PASS=0
FAIL=0

case "${OURS}" in
/*) ;;
*) OURS=${REPO_ROOT}/${OURS} ;;
esac

case "${SOURCE}" in
/*) ;;
*) SOURCE=${REPO_ROOT}/${SOURCE} ;;
esac

cleanup() {
	if [ "${KEEP_TMP:-0}" != "1" ]; then
		rm -rf "${ROOT}"
	fi
}

trap cleanup EXIT INT TERM

if [ "${GENERATE_REFERENCE}" = "1" ]; then
	if [ -z "${SOURCE}" ]; then
		printf 'missing reference source pl\n' >&2
		exit 1
	fi
	if [ ! -x "${SOURCE}" ]; then
		printf 'missing reference source pl: %s\n' "${SOURCE}" >&2
		exit 1
	fi
	mkdir -p "${REFERENCE_DIR}"
else
	if [ ! -x "${OURS}" ]; then
		printf 'missing built pl: %s\n' "${OURS}" >&2
		exit 1
	fi
	if [ ! -d "${REFERENCE_DIR}" ]; then
		printf 'missing reference set: %s\n' "${REFERENCE_DIR}" >&2
		exit 1
	fi
fi

mkdir -p "${FIX}"
: > "${FAILED_CASES}"

cat > "${FIX}/sample.ascii" <<'EOF_SAMPLE'
{ greeting = hello; count = 42; }
EOF_SAMPLE

cat > "${FIX}/invalid.ascii" <<'EOF_INVALID'
{ greeting = ; }
EOF_INVALID

: > "${FIX}/empty.ascii"

printf '\377\376' > "${FIX}/sample-utf16le.bin"
printf '{ greeting = hello; count = 42; }\n' | iconv -f UTF-8 -t UTF-16LE >> "${FIX}/sample-utf16le.bin"

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
	REF_CASE_DIR="${REFERENCE_DIR}/${CASE_NAME}"
	RUN_DIR="${CASE_DIR}/run"
	CASE_FAILURES=
	rm -rf "${CASE_DIR}"
	mkdir -p "${RUN_DIR}"
	cp "${FIX}"/* "${RUN_DIR}/"

	if [ "${GENERATE_REFERENCE}" = "1" ]; then
		rm -rf "${REF_CASE_DIR}"
		mkdir -p "${REF_CASE_DIR}"
	fi
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
	sed 's/^.*] //' "${prefix}.stderr" > "${prefix}.stderr.normalized"
}

compare_streams() {
	if [ ! -f "${REF_CASE_DIR}/run.exit" ] || [ ! -f "${REF_CASE_DIR}/run.stdout" ] || [ ! -f "${REF_CASE_DIR}/run.stderr.normalized" ]; then
		append_case_failure "reference streams missing"
		return
	fi

	if ! cmp -s "${REF_CASE_DIR}/run.exit" "${RUN_DIR}/run.exit"; then
		append_case_failure "exit status differs"
	fi

	if ! cmp -s "${REF_CASE_DIR}/run.stdout" "${RUN_DIR}/run.stdout"; then
		append_case_failure "stdout differs"
	fi

	if ! cmp -s "${REF_CASE_DIR}/run.stderr.normalized" "${RUN_DIR}/run.stderr.normalized"; then
		append_case_failure "stderr differs"
	fi
}

compare_file_exact() {
	rel=$1

	if [ ! -e "${REF_CASE_DIR}/${rel}" ] || [ ! -e "${RUN_DIR}/${rel}" ]; then
		append_case_failure "expected file missing: ${rel}"
		return
	fi

	if ! cmp -s "${REF_CASE_DIR}/${rel}" "${RUN_DIR}/${rel}"; then
		append_case_failure "file differs: ${rel}"
	fi
}

finish_case() {
	case_name=$1

	if [ "${GENERATE_REFERENCE}" = "1" ]; then
		record_pass
		return
	fi

	if [ -n "${CASE_FAILURES}" ]; then
		record_fail "${case_name}" "${CASE_FAILURES}"
	else
		record_pass
	fi
}

write_reference_streams() {
	cp "${RUN_DIR}/run.stdout" "${REF_CASE_DIR}/run.stdout"
	cp "${RUN_DIR}/run.exit" "${REF_CASE_DIR}/run.exit"
	cp "${RUN_DIR}/run.stderr.normalized" "${REF_CASE_DIR}/run.stderr.normalized"
}

write_reference_file() {
	rel=$1
	cp "${RUN_DIR}/${rel}" "${REF_CASE_DIR}/${rel}"
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

	if [ "${GENERATE_REFERENCE}" = "1" ]; then
		run_one "${SOURCE}" "${RUN_DIR}" "${RUN_DIR}/run" "${stdin_abs}" "$@"
		write_reference_streams
	else
		run_one "${OURS}" "${RUN_DIR}" "${RUN_DIR}/run" "${stdin_abs}" "$@"
		compare_streams
	fi

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

	if [ "${GENERATE_REFERENCE}" = "1" ]; then
		run_one "${SOURCE}" "${RUN_DIR}" "${RUN_DIR}/run" "${stdin_abs}" "$@"
		write_reference_streams
		for rel in ${filespec}; do
			write_reference_file "${rel}"
		done
	else
		run_one "${OURS}" "${RUN_DIR}" "${RUN_DIR}/run" "${stdin_abs}" "$@"
		compare_streams
		for rel in ${filespec}; do
			compare_file_exact "${rel}"
		done
	fi

	finish_case "${case_name}"
}

case_stream stdin-empty empty.ascii
case_stream stdin-valid sample.ascii
case_stream bad-option '' -bogus
case_stream missing-input-arg '' -input
case_stream missing-output-arg '' -output
case_stream input-valid '' -input sample.ascii
case_stream_and_exact_files output-only sample.ascii 'out.txt' -output out.txt
case_stream_and_exact_files input-output '' 'out.txt' -input sample.ascii -output out.txt
case_stream missing-file '' -input nope.ascii
case_stream zero-length '' -input empty.ascii
case_stream invalid-ascii '' -input invalid.ascii
case_stream utf16-input '' -input sample-utf16le.bin
case_stream write-fail '' -input sample.ascii -output no_such_dir/out.txt

printf 'SUMMARY pass=%s fail=%s root=%s\n' "${PASS}" "${FAIL}" "${ROOT}"
if [ "${FAIL}" -ne 0 ]; then
	sed -n '1,200p' "${FAILED_CASES}"
	exit 1
fi
