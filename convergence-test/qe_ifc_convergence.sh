#!/usr/bin/env bash
set -euo pipefail

# ========================= User settings =========================
# You can edit these defaults directly, or override them temporarily:
#   NPROC=24 NPOOL=4 bash qe_ifc_convergence.sh ecut all
PW_DEFAULT="/home/dxm1/data/downloads/qe-7.3.1-copy/bin/pw.x"
NPROC_DEFAULT=48
NPOOL_DEFAULT=4

ECUT_LIST="40 50 60 70 80 90 100"
KPOINT_ECUT=80
PRIMITIVE_KPOINT_LIST="4 6 8 10 12"
SUPERCELL_KPOINT_LIST="2 3 4 5 6"
# ================================================================

PW="${PW:-${PW_DEFAULT}}"
NPROC="${NPROC:-${NPROC_DEFAULT}}"
NPOOL="${NPOOL:-${NPOOL_DEFAULT}}"
MODE="${1:-ecut}"
CELL="${2:-all}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="${ROOT}/convergence"

usage() {
  cat <<'EOF'
Usage:
  bash qe_ifc_convergence.sh ecut [primitive|supercell|all]
  bash qe_ifc_convergence.sh kpoint [primitive|supercell|all]

Optional environment variables:
  PW=/path/to/pw.x NPROC=48 NPOOL=4
EOF
}

case "${MODE}" in
  ecut|kpoint) ;;
  *) usage; exit 2 ;;
esac

case "${CELL}" in
  primitive|supercell|all) ;;
  *) usage; exit 2 ;;
esac

run_pw() {
  local label="$1"
  local template="$2"
  local ecut="$3"
  local kmesh="$4"
  local work="${RESULTS}/${MODE}/${label}"
  local input="${work}/${label}.pw.in"
  local output="${work}/${label}.pw.out"
  local rho=$((ecut * 8))

  mkdir -p "${work}/tmp"

  awk \
    -v prefix="'${label}'" \
    -v outdir="'${work}/tmp'" \
    -v ecut="${ecut}" \
    -v rho="${rho}" \
    -v kline="  ${kmesh} ${kmesh} ${kmesh} 0 0 0" '
      BEGIN { after_kpoints = 0; wrote_rho = 0 }
      /^[[:space:]]*prefix[[:space:]]*=/ {
        sub(/=.*/, "= " prefix)
      }
      /^[[:space:]]*outdir[[:space:]]*=/ {
        sub(/=.*/, "= " outdir)
      }
      /^[[:space:]]*ecutwfc[[:space:]]*=/ {
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)
        print indent "ecutwfc = " ecut
        print indent "ecutrho = " rho
        wrote_rho = 1
        next
      }
      /^[[:space:]]*ecutrho[[:space:]]*=/ {
        if (!wrote_rho) print "  ecutrho = " rho
        next
      }
      /^[[:space:]]*K_POINTS[[:space:]]+automatic/ {
        print
        after_kpoints = 1
        next
      }
      after_kpoints {
        print kline
        after_kpoints = 0
        next
      }
      { print }
    ' "${template}" > "${input}"

  if [[ -s "${output}" ]] && grep -q "JOB DONE" "${output}"; then
    printf 'skip %-34s completed\n' "${label}"
    return
  fi

  printf 'run  %-34s ecut=%s Ry ecutrho=%s Ry k=%sx%sx%s\n' \
    "${label}" "${ecut}" "${rho}" "${kmesh}" "${kmesh}" "${kmesh}"
  mpirun -np "${NPROC}" "${PW}" -npool "${NPOOL}" -inp "${input}" > "${output}" 2>&1
}

run_ecut() {
  local name="$1"
  local template="$2"
  local kmesh="$3"
  local ecut
  for ecut in ${ECUT_LIST}; do
    run_pw "${name}_ecut${ecut}" "${template}" "${ecut}" "${kmesh}"
  done
}

run_kpoint() {
  local name="$1"
  local template="$2"
  local meshes="$3"
  local kmesh
  for kmesh in ${meshes}; do
    run_pw "${name}_k${kmesh}" "${template}" "${KPOINT_ECUT}" "${kmesh}"
  done
}

summarize() {
  local csv="${RESULTS}/${MODE}/summary.csv"
  mkdir -p "$(dirname "${csv}")"
  printf 'case,job_done,total_energy_Ry,total_force_Ry_Bohr,wall_time\n' > "${csv}"

  while IFS= read -r output; do
    local label done energy force wall
    label="$(basename "${output}" .pw.out)"
    done="no"
    grep -q "JOB DONE" "${output}" && done="yes"
    energy="$(awk '/^![[:space:]]+total energy/ { value=$5 } END { print value }' "${output}")"
    force="$(awk '/Total force/ { value=$4 } END { print value }' "${output}")"
    wall="$(awk '
      /PWSCF[[:space:]]+:/ {
        value = ""
        for (i = 1; i <= NF; i++) {
          if ($i == "CPU") {
            for (j = i + 1; j < NF; j++) value = value (value ? " " : "") $j
            value = value " " $NF
            break
          }
        }
      }
      END { print value }
    ' "${output}")"
    printf '%s,%s,%s,%s,%s\n' "${label}" "${done}" "${energy}" "${force}" "${wall}" >> "${csv}"
  done < <(find "${RESULTS}/${MODE}" -name '*.pw.out' -type f | sort)

  printf '\nSummary: %s\n' "${csv}"
  column -s, -t "${csv}" 2>/dev/null || cat "${csv}"

  if command -v python3 >/dev/null; then
    if ! python3 "${ROOT}/qe_plot_convergence.py" "${csv}"; then
      printf '\nPlot failed. The QE summary CSV is still valid: %s\n' "${csv}"
    fi
  else
    printf '\nPlot skipped: python3 is required.\n'
  fi

  if [[ "${MODE}" == "ecut" ]] && command -v python3 >/dev/null; then
    if ! python3 "${ROOT}/qe_force_convergence.py" "${RESULTS}/ecut"; then
      printf '\nForce-difference plot skipped: completed supercell force outputs are required.\n'
    fi
  fi
}

mkdir -p "${RESULTS}/${MODE}"

if [[ "${MODE}" == "ecut" ]]; then
  [[ "${CELL}" == "all" || "${CELL}" == "primitive" ]] &&
    run_ecut "primitive" "${ROOT}/primitive.pw.in" 8
  [[ "${CELL}" == "all" || "${CELL}" == "supercell" ]] &&
    run_ecut "supercell" "${ROOT}/si222_scf.pw.in" 4
else
  [[ "${CELL}" == "all" || "${CELL}" == "primitive" ]] &&
    run_kpoint "primitive" "${ROOT}/primitive.pw.in" "${PRIMITIVE_KPOINT_LIST}"
  [[ "${CELL}" == "all" || "${CELL}" == "supercell" ]] &&
    run_kpoint "supercell" "${ROOT}/si222_scf.pw.in" "${SUPERCELL_KPOINT_LIST}"
fi

summarize
