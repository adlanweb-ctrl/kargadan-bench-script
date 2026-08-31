#!/usr/bin/env bash

# YABS TUI Edition
# Author: MahdiAfra
# Based on Yet-Another-Bench-Script by Mason Rowe
# License: WTFPL

set -o pipefail

TUI_VERSION="v1.0.0"
AUTHOR="MahdiAfra"
CORE_URL_DEFAULT="https://raw.githubusercontent.com/adlanweb-ctrl/kargadan-bench-script/master/yabs.sh"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)"
RUN_DIR="$(pwd -P)"

NO_COLOR_MODE=0
NON_INTERACTIVE=0
DEMO_MODE=0
RENDER_JSON=""
PRESET=""
CORE_ARGS=()
TEMP_DIR=""
CORE_PID=""
CURSOR_HIDDEN=0

cleanup() {
	if [[ -n "$CORE_PID" ]] && kill -0 "$CORE_PID" 2>/dev/null; then
		kill "$CORE_PID" 2>/dev/null || true
		wait "$CORE_PID" 2>/dev/null || true
	fi
	[[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf -- "$TEMP_DIR"
	if ((CURSOR_HIDDEN)); then
		printf '\033[?25h' 2>/dev/null || true
		CURSOR_HIDDEN=0
	fi
}
abort() {
	trap - INT TERM
	cleanup
	exit 130
}
trap cleanup EXIT
trap abort INT TERM

usage() {
	cat <<'EOF'
YABS TUI Edition by MahdiAfra

Usage:
  ./yabs-tui.sh                         Open the interactive launcher
  ./yabs-tui.sh --preset network        Run the full network benchmark
  ./yabs-tui.sh --preset quick          Run a reduced network benchmark
  ./yabs-tui.sh --preset full           Run all YABS benchmarks
  ./yabs-tui.sh -- [YABS flags]         Pass flags directly to YABS

TUI options:
  --demo                  Render a sample dashboard without running tests
  --render-json <file>    Render an existing YABS JSON result
  --no-color              Disable ANSI colors
  --non-interactive       Never show the launcher menu
  --preset <name>         quick, network, full, disk, or cpu
  -h, --help              Show this help

Examples:
  ./yabs-tui.sh --preset network
  ./yabs-tui.sh -- -fg
  ./yabs-tui.sh --render-json bin/example.json
EOF
}

while (($#)); do
	case "$1" in
		--demo) DEMO_MODE=1 ;;
		--render-json)
			shift
			[[ $# -gt 0 ]] || { echo "Missing file after --render-json" >&2; exit 2; }
			RENDER_JSON="$1"
			;;
		--preset)
			shift
			[[ $# -gt 0 ]] || { echo "Missing name after --preset" >&2; exit 2; }
			PRESET="$1"
			;;
		--no-color) NO_COLOR_MODE=1 ;;
		--non-interactive) NON_INTERACTIVE=1 ;;
		-h|--help) usage; exit 0 ;;
		--)
			shift
			while (($#)); do CORE_ARGS+=("$1"); shift; done
			break
			;;
		*) CORE_ARGS+=("$1") ;;
	esac
	shift
done

if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
	NO_COLOR_MODE=1
fi

if ((NO_COLOR_MODE == 0)); then
	RESET=$'\033[0m'
	BOLD=$'\033[1m'
	DIM=$'\033[2m'
	CYAN=$'\033[38;5;45m'
	BLUE=$'\033[38;5;39m'
	GREEN=$'\033[38;5;83m'
	YELLOW=$'\033[38;5;220m'
	RED=$'\033[38;5;203m'
	PURPLE=$'\033[38;5;141m'
	MUTED=$'\033[38;5;245m'
	PANEL=$'\033[38;5;250m'
else
	RESET="" BOLD="" DIM="" CYAN="" BLUE="" GREEN="" YELLOW="" RED="" PURPLE="" MUTED="" PANEL=""
fi

if [[ "${LC_ALL:-${LANG:-}}" == *UTF-8* || "${LC_ALL:-${LANG:-}}" == *utf8* ]]; then
	TL="╭" TR="╮" BL="╰" BR="╯" H="─" V="│"
	BAR_FULL="█" BAR_EMPTY="░" BULLET="◆" CHECK="●" ARROW="›"
	SPINNERS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
else
	TL="+" TR="+" BL="+" BR="+" H="-" V="|"
	BAR_FULL="#" BAR_EMPTY="." BULLET="*" CHECK="o" ARROW=">"
	SPINNERS=("|" "/" "-" "\\")
fi

TERM_COLS=90
if command -v tput >/dev/null 2>&1; then
	DETECTED_COLS=$(tput cols 2>/dev/null || true)
	[[ "$DETECTED_COLS" =~ ^[0-9]+$ ]] && TERM_COLS=$DETECTED_COLS
fi
((TERM_COLS < 72)) && TERM_COLS=72
((TERM_COLS > 110)) && TERM_COLS=110
INNER_WIDTH=$((TERM_COLS - 2))

repeat() {
	local char="$1" count="$2" out=""
	while ((count-- > 0)); do out+="$char"; done
	printf '%s' "$out"
}

plain() {
	printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'
}

fit() {
	local value="$1" width="$2" raw len
	raw=$(plain "$value")
	len=${#raw}
	if ((len > width)); then
		printf '%s…' "${raw:0:$((width - 1))}"
	else
		printf '%s%*s' "$value" "$((width - len))" ""
	fi
}

clear_screen() {
	[[ -t 1 ]] && printf '\033[2J\033[H'
}

box_top() {
	printf '%s%s%s%s%s\n' "$CYAN" "$TL" "$(repeat "$H" "$INNER_WIDTH")" "$TR" "$RESET"
}

box_bottom() {
	printf '%s%s%s%s%s\n' "$CYAN" "$BL" "$(repeat "$H" "$INNER_WIDTH")" "$BR" "$RESET"
}

box_line() {
	local content="$1"
	printf '%s%s%s %s %s%s%s\n' "$CYAN" "$V" "$RESET" "$(fit "$content" "$((INNER_WIDTH - 2))")" "$CYAN" "$V" "$RESET"
}

box_rule() {
	printf '%s%s%s%s%s\n' "$CYAN" "$V" "$(repeat "$H" "$INNER_WIDTH")" "$V" "$RESET"
}

center_text() {
	local text="$1" width="$2" raw pad
	raw=$(plain "$text")
	pad=$(((width - ${#raw}) / 2))
	((pad < 0)) && pad=0
	printf '%*s%s' "$pad" "" "$text"
}

render_header() {
	box_top
	box_line "$(center_text "${BOLD}${CYAN}YABS${RESET} ${BOLD}TUI EDITION${RESET}" "$((INNER_WIDTH - 2))")"
	box_line "$(center_text "Server benchmarking, beautifully presented" "$((INNER_WIDTH - 2))")"
	box_line "$(center_text "${DIM}Designed by ${AUTHOR}  ${BULLET}  ${TUI_VERSION}${RESET}" "$((INNER_WIDTH - 2))")"
	box_bottom
}

render_menu() {
	local selected="$1" i marker label hint
	clear_screen
	render_header
	printf '\n%sChoose a benchmark profile%s  %s(↑/↓ + Enter, or 1-5)%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
	local labels=("Quick network scan" "Full network benchmark" "Complete server benchmark" "Disk benchmark" "CPU benchmark")
	local hints=("3 locations • lowest bandwidth" "All iperf3 locations" "Network + disk + Geekbench" "fio storage tests only" "Geekbench only")
	for i in "${!labels[@]}"; do
		if ((i == selected)); then marker="${CYAN}${ARROW}${RESET}"; label="${BOLD}${CYAN}${labels[$i]}${RESET}"; else marker=" "; label="${labels[$i]}"; fi
		printf '  %s %s  %-30b %s%s%s\n' "$marker" "$((i + 1))" "$label" "$MUTED" "${hints[$i]}" "$RESET"
	done
	printf '\n  %sPress q to cancel%s\n' "$DIM" "$RESET"
}

interactive_launcher() {
	local selected=0 key rest
	while true; do
		render_menu "$selected"
		IFS= read -rsn1 key </dev/tty || return 1
		case "$key" in
			$'\033')
				IFS= read -rsn2 -t 0.1 rest </dev/tty || true
				case "$rest" in '[A') ((selected--));; '[B') ((selected++));; esac
				((selected < 0)) && selected=4
				((selected > 4)) && selected=0
				;;
			'') break ;;
			[1-5]) selected=$((key - 1)); break ;;
			q|Q) clear_screen; exit 0 ;;
		esac
	done
	case "$selected" in
		0) PRESET="quick" ;;
		1) PRESET="network" ;;
		2) PRESET="full" ;;
		3) PRESET="disk" ;;
		4) PRESET="cpu" ;;
	esac
}

apply_preset() {
	case "$PRESET" in
		quick) CORE_ARGS=(-f -g -r) ;;
		network) CORE_ARGS=(-f -g) ;;
		full|"") CORE_ARGS=() ;;
		disk) CORE_ARGS=(-i -g) ;;
		cpu) CORE_ARGS=(-f -i) ;;
		*) echo "Unknown preset: $PRESET" >&2; exit 2 ;;
	esac
}

bar() {
	local value="$1" max="$2" width="${3:-16}" filled empty
	filled=$(awk -v v="$value" -v m="$max" -v w="$width" 'BEGIN { if (m <= 0) print 0; else { n=int((v/m)*w+.5); if(n<0)n=0; if(n>w)n=w; print n } }')
	empty=$((width - filled))
	printf '%s%s%s%s%s' "$GREEN" "$(repeat "$BAR_FULL" "$filled")" "$MUTED" "$(repeat "$BAR_EMPTY" "$empty")" "$RESET"
}

json_string() {
	local data="$1" key="$2"
	printf '%s' "$data" | grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*"(.*)"$/\1/'
}

json_number() {
	local data="$1" key="$2"
	printf '%s' "$data" | grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*[0-9.]+' | head -n1 | sed -E 's/.*:[[:space:]]*//'
}

json_bool() {
	local data="$1" key="$2"
	printf '%s' "$data" | grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*(true|false)' | head -n1 | sed -E 's/.*:[[:space:]]*//'
}

json_array() {
	local data="$1" name="$2" next="$3"
	printf '%s' "$data" | sed -E 's/.*"'"$name"'"[[:space:]]*:[[:space:]]*\[(.*)\][[:space:]]*,[[:space:]]*"'"$next"'".*/\1/' | sed -E 's/}[[:space:]]*,[[:space:]]*\{/}\n{/g'
}

human_kib() {
	awk -v n="${1:-0}" 'BEGIN { if(n>=1073741824)printf "%.1f TiB",n/1073741824; else if(n>=1048576)printf "%.1f GiB",n/1048576; else if(n>=1024)printf "%.1f MiB",n/1024; else printf "%.0f KiB",n }'
}

human_kbps() {
	awk -v n="${1:-0}" 'BEGIN { if(n>=1000000)printf "%.2f GB/s",n/1000000; else if(n>=1000)printf "%.2f MB/s",n/1000; else printf "%.0f KB/s",n }'
}

speed_mbps() {
	local value="$1"
	awk -v s="$value" 'BEGIN { split(s,a," "); if(s~/Gbits/)printf "%.2f",a[1]*1000; else if(s~/Mbits/)printf "%.2f",a[1]; else if(s~/Kbits/)printf "%.2f",a[1]/1000; else print 0 }'
}

render_dashboard() {
	local json="$1" distro kernel arch vm cpu cores freq ram swap disk ipv4 ipv6
	json=$(printf '%s' "$json" | tr -d '\n\r\t')
	[[ "$json" == *'"version"'* ]] || { echo "Invalid or unsupported YABS JSON result." >&2; return 1; }

	distro=$(json_string "$json" distro); kernel=$(json_string "$json" kernel)
	arch=$(json_string "$json" arch); vm=$(json_string "$json" vm)
	cpu=$(json_string "$json" model); cores=$(json_number "$json" cores); freq=$(json_string "$json" freq)
	ram=$(human_kib "$(json_number "$json" ram)"); swap=$(human_kib "$(json_number "$json" swap)")
	disk=$(human_kib "$(json_number "$json" disk)")
	ipv4=$(json_bool "$json" ipv4); ipv6=$(json_bool "$json" ipv6)

	clear_screen
	render_header
	printf '\n%s%s SYSTEM OVERVIEW%s\n' "$CYAN" "$BULLET" "$RESET"
	box_top
	box_line "${BOLD}OS${RESET}       ${distro:-Unknown}  ${DIM}(${arch:-?})${RESET}"
	box_line "${BOLD}Kernel${RESET}   ${kernel:-Unknown}     ${BOLD}VM${RESET}  ${vm:-Unknown}"
	box_line "${BOLD}CPU${RESET}      ${cpu:-Unknown}"
	box_line "${BOLD}Compute${RESET}  ${cores:-?} cores @ ${freq:-Unknown}"
	box_line "${BOLD}Memory${RESET}   RAM ${GREEN}${ram}${RESET}   Swap ${swap}   Disk ${BLUE}${disk}${RESET}"
	box_line "${BOLD}Network${RESET}  IPv4 $([[ "$ipv4" == true ]] && printf '%s%s online%s' "$GREEN" "$CHECK" "$RESET" || printf '%soffline%s' "$RED" "$RESET")   IPv6 $([[ "$ipv6" == true ]] && printf '%s%s online%s' "$GREEN" "$CHECK" "$RESET" || printf '%soffline%s' "$YELLOW" "$RESET")"
	box_bottom

	local fio_data fio_rows=() obj bs total iops max_fio=0 val
	fio_data=$(json_array "$json" fio iperf)
	if [[ "$fio_data" != "$json" && -n "$fio_data" ]]; then
		while IFS= read -r obj; do
			[[ "$obj" == *'"bs"'* ]] || continue
			bs=$(json_string "$obj" bs); total=$(json_number "$obj" speed_rw); iops=$(json_number "$obj" iops_rw)
			fio_rows+=("$bs|$total|$iops")
			val=${total%.*}; ((val > max_fio)) && max_fio=$val
		done <<< "$fio_data"
	fi
	if ((${#fio_rows[@]})); then
		printf '\n%s%s DISK PERFORMANCE%s\n' "$PURPLE" "$BULLET" "$RESET"
		box_top
		box_line "${BOLD}Block size     Throughput          IOPS         Relative performance${RESET}"
		box_rule
		local row
		for row in "${fio_rows[@]}"; do
			IFS='|' read -r bs total iops <<< "$row"
			box_line "$(printf '%-14s %-19s %-12s ' "$bs" "$(human_kbps "$total")" "$iops")$(bar "$total" "$max_fio" 18)"
		done
		box_bottom
	fi

	local iperf_data net_rows=() mode provider loc send recv latency send_m recv_m max_net=0
	iperf_data=$(json_array "$json" iperf geekbench)
	if [[ "$iperf_data" != "$json" && -n "$iperf_data" ]]; then
		while IFS= read -r obj; do
			[[ "$obj" == *'"provider"'* ]] || continue
			mode=$(json_string "$obj" mode); provider=$(json_string "$obj" provider); loc=$(json_string "$obj" loc)
			send=$(json_string "$obj" send); recv=$(json_string "$obj" recv); latency=$(json_string "$obj" latency)
			send_m=$(speed_mbps "$send"); recv_m=$(speed_mbps "$recv")
			net_rows+=("$mode|$provider|$loc|$send|$recv|$latency|$recv_m")
			val=${recv_m%.*}; ((val > max_net)) && max_net=$val
		done <<< "$iperf_data"
	fi
	if ((${#net_rows[@]})); then
		printf '\n%s%s NETWORK SPEED%s\n' "$BLUE" "$BULLET" "$RESET"
		box_top
		box_line "${BOLD}Route                   Upload        Download      Ping     Rx graph${RESET}"
		box_rule
		local route
		for row in "${net_rows[@]}"; do
			IFS='|' read -r mode provider loc send recv latency recv_m <<< "$row"
			route="${mode} ${provider} / ${loc}"
			box_line "$(printf '%-20.20s %-12.12s %-12.12s %-7.7s ' "$route" "$send" "$recv" "$latency")$(bar "$recv_m" "$max_net" 10)"
		done
		box_bottom
	fi

	local geek_data gb_rows=() version single multi url max_gb=0
	geek_data=$(printf '%s' "$json" | sed -E 's/.*"geekbench"[[:space:]]*:[[:space:]]*\[(.*)\][[:space:]]*,[[:space:]]*"runtime".*/\1/' | sed -E 's/}[[:space:]]*,[[:space:]]*\{/}\n{/g')
	if [[ "$geek_data" != "$json" && -n "$geek_data" ]]; then
		while IFS= read -r obj; do
			[[ "$obj" == *'"version"'* ]] || continue
			version=$(json_number "$obj" version); single=$(json_number "$obj" single); multi=$(json_number "$obj" multi); url=$(json_string "$obj" url)
			gb_rows+=("$version|$single|$multi|$url")
			val=${multi%.*}; ((val > max_gb)) && max_gb=$val
		done <<< "$geek_data"
	fi
	if ((${#gb_rows[@]})); then
		printf '\n%s%s CPU BENCHMARK%s\n' "$YELLOW" "$BULLET" "$RESET"
		box_top
		box_line "${BOLD}Version        Single core     Multi core      Multi-core score${RESET}"
		box_rule
		for row in "${gb_rows[@]}"; do
			IFS='|' read -r version single multi url <<< "$row"
			box_line "$(printf 'Geekbench %-5s %-15s %-15s ' "$version" "$single" "$multi")$(bar "$multi" "$max_gb" 20)"
		done
		box_bottom
	fi

	local elapsed start end
	elapsed=$(json_number "$json" elapsed)
	if [[ -z "$elapsed" ]]; then
		start=$(json_number "$json" start); end=$(json_number "$json" end)
		[[ -n "$start" && -n "$end" ]] && elapsed=$((end - start))
	fi
	printf '\n%s%s Benchmark complete%s' "$GREEN" "$CHECK" "$RESET"
	[[ -n "$elapsed" ]] && printf ' in %dm %02ds' "$((elapsed / 60))" "$((elapsed % 60))"
	printf '  %s%s by %s%s\n' "$DIM" "$BULLET" "$AUTHOR" "$RESET"
}

sample_json() {
	cat <<'EOF'
{"version":"v2026-07-24","time":"20260831-221500","os":{"arch":"x64","distro":"Ubuntu 24.04.2 LTS","kernel":"6.8.0-79-generic","uptime":918274,"vm":"KVM"},"net":{"ipv4":true,"ipv6":true},"cpu":{"model":"AMD EPYC 9654 96-Core Processor","cores":8,"freq":"2396.400 MHz","aes":true,"virt":true},"mem":{"ram":16384000,"ram_units":"KiB","swap":2097152,"swap_units":"KiB","disk":209715200,"disk_units":"KB"},"ip_info":{"protocol":"IPv4","isp":"Example Networks","asn":"AS64500 Example","org":"Example Cloud","city":"Frankfurt","region":"Hesse","region_code":"HE","country":"Germany"},"fio":[{"bs":"4k","speed_r":418200,"iops_r":104550,"speed_w":421300,"iops_w":105325,"speed_rw":839500,"iops_rw":209875,"speed_units":"KBps"},{"bs":"64k","speed_r":1220000,"iops_r":19062,"speed_w":1180000,"iops_w":18437,"speed_rw":2400000,"iops_rw":37499,"speed_units":"KBps"},{"bs":"512k","speed_r":1910000,"iops_r":3730,"speed_w":1840000,"iops_w":3593,"speed_rw":3750000,"iops_rw":7323,"speed_units":"KBps"},{"bs":"1m","speed_r":2130000,"iops_r":2080,"speed_w":2070000,"iops_w":2021,"speed_rw":4200000,"iops_rw":4101,"speed_units":"KBps"}],"iperf":[{"mode":"IPv4","provider":"Clouvider","loc":"London, UK (10G)","send":"6.82 Gbits/sec","recv":"7.34 Gbits/sec","latency":"18.2 ms"},{"mode":"IPv4","provider":"Scaleway","loc":"Paris, FR (10G)","send":"8.16 Gbits/sec","recv":"8.91 Gbits/sec","latency":"9.64 ms"},{"mode":"IPv4","provider":"Clouvider","loc":"NYC, US (10G)","send":"2.41 Gbits/sec","recv":"3.08 Gbits/sec","latency":"91.3 ms"}],"geekbench":[{"version":6,"single":2147,"multi":9184,"url":"https://browser.geekbench.com/v6/cpu/example"}],"runtime":{"start":1788214500,"end":1788214918,"elapsed":418}}
EOF
}

ensure_core() {
	if [[ -f "$SCRIPT_DIR/yabs.sh" ]]; then
		CORE_SCRIPT="$SCRIPT_DIR/yabs.sh"
		return
	fi
	TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yabs-tui.XXXXXX") || exit 1
	CORE_SCRIPT="$TEMP_DIR/yabs.sh"
	local url="${YABS_CORE_URL:-$CORE_URL_DEFAULT}"
	printf '%sDownloading benchmark engine...%s\n' "$CYAN" "$RESET"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$CORE_SCRIPT"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$CORE_SCRIPT" "$url"
	else
		echo "curl or wget is required to download yabs.sh" >&2
		exit 1
	fi
}

detect_stage() {
	local log="$1"
	if grep -q 'YABS completed' "$log"; then printf 'Finalizing report|98'
	elif grep -q 'Geekbench.*Benchmark Test' "$log"; then printf 'Running CPU benchmark|88'
	elif grep -q 'iperf3 Network Speed Tests' "$log"; then printf 'Testing global network routes|65'
	elif grep -q 'fio Disk Speed Tests' "$log"; then printf 'Measuring disk performance|38'
	elif grep -q 'Network Information' "$log"; then printf 'Detecting network and ISP|20'
	elif grep -q 'Basic System Information' "$log"; then printf 'Inspecting server hardware|10'
	else printf 'Preparing benchmark engine|4'
	fi
}

render_progress() {
	local log="$1" frame="$2" stage_info stage pct latest
	stage_info=$(detect_stage "$log"); stage=${stage_info%|*}; pct=${stage_info##*|}
	latest=$(grep -E '^(Generating|Running|iperf3 Network|fio Disk|Geekbench|Basic System|IPv[46] Network)' "$log" | tail -n1)
	[[ -z "$latest" ]] && latest="Initializing secure test environment"
	clear_screen
	render_header
	printf '\n'
	box_top
	box_line "$(center_text "${SPINNERS[$((frame % ${#SPINNERS[@]}))]}  ${BOLD}${stage}${RESET}" "$((INNER_WIDTH - 2))")"
	box_line "$(center_text "$(bar "$pct" 100 42)  ${pct}%" "$((INNER_WIDTH - 2))")"
	box_line "$(center_text "${DIM}${latest}${RESET}" "$((INNER_WIDTH - 2))")"
	box_bottom
	printf '\n%sThe benchmark can take several minutes. Press Ctrl+C to stop safely.%s\n' "$DIM" "$RESET"
}

run_benchmark() {
	ensure_core
	[[ -n "$TEMP_DIR" ]] || TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yabs-tui.XXXXXX") || exit 1
	local log="$TEMP_DIR/yabs.log" json_file="$TEMP_DIR/result.json" frame=0 status work_dir="$RUN_DIR"
	[[ -d "$work_dir" && -w "$work_dir" ]] || work_dir="$TEMP_DIR"

	(
		cd "$work_dir" || exit 1
		bash "$CORE_SCRIPT" "${CORE_ARGS[@]}" -j
	) >"$log" 2>&1 &
	CORE_PID=$!

	if [[ -t 1 && $NON_INTERACTIVE -eq 0 ]]; then
		printf '\033[?25l'
		CURSOR_HIDDEN=1
		while kill -0 "$CORE_PID" 2>/dev/null; do
			render_progress "$log" "$frame"
			((frame++))
			sleep 0.35
		done
	fi
	wait "$CORE_PID"; status=$?; CORE_PID=""
	grep '^{"version":' "$log" | tail -n1 > "$json_file" || true

	if ((status != 0)) || [[ ! -s "$json_file" ]]; then
		clear_screen
		render_header
		printf '\n%sBenchmark failed (exit code %s). Last output:%s\n\n' "$RED" "$status" "$RESET" >&2
		tail -n 18 "$log" >&2
		return "${status:-1}"
	fi
	render_dashboard "$(<"$json_file")"
}

if ((DEMO_MODE)); then
	render_dashboard "$(sample_json)"
	exit
fi

if [[ -n "$RENDER_JSON" ]]; then
	[[ -r "$RENDER_JSON" ]] || { echo "Cannot read JSON file: $RENDER_JSON" >&2; exit 1; }
	render_dashboard "$(<"$RENDER_JSON")"
	exit
fi

if [[ -z "$PRESET" && ${#CORE_ARGS[@]} -eq 0 && $NON_INTERACTIVE -eq 0 && -t 1 && -r /dev/tty ]]; then
	interactive_launcher
fi

if [[ -n "$PRESET" ]]; then
	apply_preset
fi

run_benchmark
