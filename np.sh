test -f ".env" && {
  echo reading config file...
  source ".env"
  # TODO tests
true
} || {
  cat << EOF
[WARNING] missing .env file
EOF
}
read -t 5 || true
config() {
  # config env file
  true
}
update() {
  # download latest script
  # clean install
  true 
}
reset() {
	test ! -d ".reach" || rm -rvf "${_}"
	test ! -f "np.sh" || source "${_}"
  compile
}
connector () {
        local i=$( grep -n ${1} -e _ALGO | head -1 | cut '-d:' '-f1' ) 
        local n=$(( $( grep -n ${1} -e _ETH | head -1 | cut '-d:' '-f1' ) - 1 )) 
        sed -n "${i},${n}p" ${1}
        echo "console.log(JSON.stringify({ALGO:_ALGO, template: '${TEMPLATE_NAME:-lite}'}))"
}
compile () {
        echo "${REACH_VERSION}"
        ./reach compile ${infile:-index}.rsh --install-pkgs
        ./reach compile ${infile:-index}.rsh "${@}"
}
eject () {
        _ () {
                node <(connector "${1}")
        }
        _ build/${infile:-index}.main.mjs
}
plan-verify() {
  cat << EOF
{
  "id": "${plan_id}"
}
EOF
}
plan-hydrogen() {
  cat << EOF
{
  "id": "${plan_id}",
  "params": {
    "tok0": ${param_tok0} 
  }
}
EOF
}
plan-lite() {
  cat << EOF
{
  "id": "${plan_id}",
  "params": {}
}
EOF
}
plan() {
  case "${1}" in
   verify) plan-verify;;
   hydrogen|1) plan-hydrogen;;
   lite|0|*) plan-lite;;
  esac
}
v2-register() {
  curl -X POST "${API_ENDPOINT_TESTNET}/api/v2/register" -H 'Content-Type: application/json' -d @<( eject ) 
}
v2-launch() {
  local plan_id="${1}"
  local param_tok0="${2:-${PARAM_TOK0}}"
  local param_tok1="${2:-${PARAM_TOK1}}"
  curl -X POST "${API_ENDPOINT_TESTNET}/api/v2/launch" -H 'Content-Type: application/json' -d @<( plan "${TEMPLATE_NAME}" ) 
}
v2-apps() {
  local plan_id="${1}"
  curl "${API_ENDPOINT_TESTNET}/api/v2/apps?planId=${plan_id}" -H 'Content-Type: application/json'
}
v2-verify() {
  local plan_id="${1}"
  curl -X POST "${API_ENDPOINT_TESTNET}/api/v2/verify" -H 'Content-Type: application/json' -d @<( plan verify )
}
v1-launch () {
  curl -X POST "${API_ENDPOINT_TESTNET}/api/v1/launch" -H 'Content-Type: application/json' -d @<( eject ) 
}
devnet() {
        local -x REACH_CONNECTOR_MODE=ALGO-devnet
        ./reach devnet
}
run() {
        local -x REACH_CONNECTOR_MODE=ALGO-devnet
        node index.mjs index
}
get-reach() {
  test -f "reach" || {
    curl https://docs.reach.sh/reach -o reach --silent
    chmod +x reach
  }
}
if-template() {
  test ! "${TEMPLATE_NAME}" = "${1}"
}
np () {
        local infile="${1:-index}" 
        test -f "${infile:-index}.rsh" || return
        main () {
          compile && launch
        }
        main
}
_() {
  get-reach
}
_
