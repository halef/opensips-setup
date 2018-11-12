#!/usr/bin/env bash
set -e # Abort on error

# Locate this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load heler.sh functions
source ${SCRIPT_DIR}/helper.sh

# Set paramaters
# TODO(langep): Make parameters configurable or read from environment
OPENSIPS_HOME=/opt/opensips


if [ "$1" == "--aws" ]; then
    internal_ip=$(get_aws_internal_ip)
    if [ $? -gt 0 ]; then
        fatal "Specified --aws but it seems like we are not running on AWS."
    fi
else
    internal_ip=$1
fi

env_identifier=$2
db_name=opensips_${env_identifier}
db_passwd_user_rw=$3

db_host=database.internal.org
db_user_rw=opensips
db_port=3306
internal_domain_name=$(hostname -f)

db_connection_uri=mysql://${db_user_rw}:${db_passwd_user_rw}@${db_host}:${db_port}/${db_name}

if [[ -z "$4" ]]; then
    CONFIG_DIR=${SCRIPT_DIR}/conf
else
    CONFIG_DIR=$4
fi


# Replace configuration
rm -rf ${OPENSIPS_HOME}/etc/opensips/*
cp -r ${CONFIG_DIR}/* ${OPENSIPS_HOME}/etc/opensips/.

# opensips.cfg
sed -i -e "s|%%INTERNAL_IP%%|${internal_ip}|g" ${OPENSIPS_HOME}/etc/opensips/opensips.conf
sed -i -e "s|%%OPENSIPS_HOME%%|${OPENSIPS_HOME}|g" ${OPENSIPS_HOME}/etc/opensips/opensips.conf
sed -i -e "s|%%DB_CONNECTION_URI%%|${db_connection_uri}|g" ${OPENSIPS_HOME}/etc/opensips/opensips.conf

# opensipsctlrc
sed -i -e "s|%%OPENSIPS_HOME%%|${OPENSIPS_HOME}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%INTERNAL_DOMAIN_NAME%%|${internal_domain_name}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_NAME%%|${db_name}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_HOST%%|${db_host}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_PASSWD_USER_RW%%|${db_passwd_user_rw}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_USER_RW%%|${db_user_rw}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_PORT%%|${db_port}|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc
sed -i -e "s|%%DB_USER_ROOT%%|root|g" ${OPENSIPS_HOME}/etc/opensips/opensipsctlrc

chown -R opensips ${OPENSIPS_HOME}
