function info() {
  local message="$1"
  echo -e "\e[32m[INFO]\e[0m $(date +'%Y-%m-%d %H:%M:%S') - $message" >&2
}

function warn() {
  local message="$1"
  echo -e "\e[33m[WARN]\e[0m $(date +'%Y-%m-%d %H:%M:%S') - $message" >&2
}

function error() {
  local message="$1"
  echo -e "\e[31m[ERROR]\e[0m $(date +'%Y-%m-%d %H:%M:%S') - $message" >&2
}
