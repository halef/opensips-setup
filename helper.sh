if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    echo "You need to source this script."
    exit 1
fi

###
#   LOGGING
###
# Logging helpers, taken from https://dev.to/thiht/shell-scripts-matter
readonly LOG_FILE="/tmp/$(basename "$0").log"
info()    { echo "[INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

###
#   VALIDATION
###
# Check if group exists
check_group() {
    local groupname=${1}
    getent group ${groupname} > /dev/null
}

# Check if group exists. Abort otherwise.
require_group() {
    local groupname=${1}
    if ! check_group ${groupname}; then
        fatal "The group '${groupname}' does not exist."
    fi
}

# Check if user exists
check_user() {
    local username=${1}
    id -u ${username} > /dev/null 2>&1
}

# Check if user exists. Abort otherwise.
require_user() {
    local username=${1}
    if ! check_user ${username}; then
        fatal "The user '${username}' does not exist."
    fi
}

# Check if command exists
check_command() {
    local readonly cmd=${1}
    type -p ${cmd} > /dev/null
}

# Abort if check_command test not passed
require_command() {
    local readonly cmd=${1}
    if ! check_command ${cmd}; then
        fatal "${cmd} could not be found in PATH"
    fi
}

# Check if the current user is a root user. Abort otherwise.
check_root() {
	[[ $EUID -eq 0 ]] 
}

# Abort if check_root test not passed.
require_root() {
    if ! check_root; then
        fatal "This script must be run as root."
    fi
}

# Check if variable is set and non-empty. 
# Example: check_null_or_unset ${MY_VAR}
check_null_or_unset() {
	local readonly var_val=${1}
    [[ -n ${var_val:+x} ]]
}

# Abort if check_null_or_unset failed.
# Example: require_var ${MY_VAR} "MY_VAR"
require_var() {
    local readonly var_val=${1}
    local readonly var_name=${2}
    if ! check_null_or_unset ${var_val}; then
        fatal "${var_name} is null or unset."
    fi
}

# Check if variable is directory.
# Example: check_dir ${MY_VAR}
check_dir() {
	local readonly path=${1}
    [[ -d ${path} ]]
}

# Abort if check_dir failed. Also runs require_var
# Example: require_dir ${MY_VAR} "MY_VAR"
require_dir() {
    local readonly path=${1}
    local readonly var_name=${2}
    require_var ${path} ${var_name}
    if ! check_dir ${path}; then
        fatal "${var_name} is not a directory."
    fi
}

# Check if variable is file. Abort otherwise.
# Example: check_file ${MY_VAR} "MY_VAR"
check_file() {
    local readonly path=${1}
    [[ -f ${path} ]]
}

# Abort if check_file failed. Also runs require_var
# Example: require_file ${MY_VAR} "MY_VAR"
require_file() {
	local readonly path=${1}
	local readonly var_name=${2}
    require_var ${path} ${var_name}
	if ! check_file ${path}; then
		fatal "${var_name} is not a file."
	fi
}

# Set os and ver to distro name and version respectively. 
set_os_and_ver() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        os=$NAME
        ver=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        os=$(lsb_release -si)
        ver=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        os=$DISTRIB_ID
        ver=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        os=Debian
        ver=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        os=$(uname -s)
        ver=$(uname -r)
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        os=$(uname -s)
        ver=$(uname -r)
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        os=$(uname -s)
        ver=$(uname -r)
    fi
}

###
#   AWS 
###
# Get AWS internal IP
get_aws_internal_ip() {
    require_command curl
    local ip=$(curl --connect-timeout 5 http://169.254.169.254/latest/meta-data/local-ipv4 2> /dev/null)
    if [[ "$?" -ne 0 ]]; then
        warning "It appears that you are not running on AWS but 'get_aws_internal_ip' only works on AWS."
        return 1
    fi
    echo ${ip}
}

# Get AWS external IP
get_aws_external_ip() {
    require_command curl
    local ip=$(curl --connect-timeout 5 -s http://169.254.169.254/latest/meta-data/public-ipv4)
    if [[ "$?" -ne 0 ]]; then
        warning "It appears that you are not running on AWS but 'get_aws_internal_ip' only works on AWS."
        return 1
    fi
    echo ${ip}
}

# Get AWS VPC CIDR block
get_aws_vpc_cidr() {
    require_command curl
    local mac=$(curl --connect-timeout 5 -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -n1 | tr -d '/')
    if [[ "$?" -ne 0 ]]; then
    	warning "It appears that you are not running on AWS but 'get_aws_vpc_cidr' only works on AWS."
	return 1
    fi
    local cidr=$(curl --connect-timeout 5 -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/vpc-ipv4-cidr-block/)
    if [[ "$?" -ne 0 ]]; then
    	warning "It appears that you are not running on AWS but 'get_aws_vpc_cidr' only works on AWS."
	return 1
    fi
    echo ${cidr}
}
