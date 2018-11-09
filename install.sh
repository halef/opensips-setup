#!/usr/bin/env bash
set -e # Abort on error

# Locate this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set paramaters
# TODO(langep): Make parameters configurable
download_location=/usr/local/src
install_location=/opt/opensips
repo_url=https://github.com/OpenSIPS/opensips.git
branch=2.2

# Cleanup trap in case of error
cleanup() {
    if [ $? -ne 0 ]; then
        # TODO(langep): Conditional cleanup based on where error happend
        rm -rf "$install_location"
    fi
}

trap cleanup EXIT

# Load heler.sh functions
source ${SCRIPT_DIR}/helper.sh

# Check for root user
require_root

# Update packages and install dependencies
apt-get update
# TODO(langep): Cleanup dependencies
apt-get install -y --no-install-recommends packaging-dev ubuntu-dev-tools \
    subversion git-core autoconf automake gcc g++ make build-essential \
    linux-headers-$(uname -r) git libncurses5-dev flex bison libmysqlclient-dev \
    libssl-dev libcurl4-openssl-dev libxml2-dev libpcre3-dev libperl-dev \
    python-dev libmicrohttpd-dev mysql-client-core-5.7 python-mysqldb \
    python-pip

# Make download and install directories
mkdir -p "$download_location" "$install_location"

# Clone the repo
cd ${src_dir}
if check_dir opensips_${branch}; then
    info "Skipping download. Found '${src_dir}/opensips_${branch}' already present."
else 
    git clone ${repo_url} opensips_${branch}
fi
cd opensips_${branch}
git pull
git checkout ${branch}


# Compile and install
make prefix=${install_location}
make prefix=${install_location} install

# Create group and user for opensips if they don't exist
if ! check_group opensips; then
    groupadd opensips
fi

if ! check_user opensips; then
    useradd -r -s /bin/false -g opensips opensips
fi

cp ${SCRIPT_DIR}/init.d/opensips.init-debian /etc/init.d/opensips
chmod +x /etc/init.d/opensips

sed -i -e "s|%%OPENSIPS_HOME%%|${install_location}|g" /etc/init.d/opensips
sed -i -e "s|%%S_MEMORY%%|0|g" /etc/init.d/opensips
sed -i -e "s|%%P_MEMORY%%|0|g" /etc/init.d/opensips

update-rc.d opensips defaults

chown -R opensips ${install_location}

echo "export OPENSIPS_HOME=${install_location}" >> /etc/bash.bashrc

info "Installation complete."
info "Run 'source /etc/bash.bashrc'"
info "Then run '${SCRIPT_DIR}/update-conf.sh [--aws]' next."

