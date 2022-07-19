#!/bin/bash
#
set -eu

### Target, vars

TARGET=${1:-prod}
OLD_NS="a4b31c-prod"
NEW_NS="a4b31c-tools"


### Backup from old PROD db

# Vars
LEADER=$(oc get cm/fom-db-ha-prod-leader -o json | jq -j '.metadata.annotations.leader')
OLD_DB=$(oc exec -n ${OLD_NS} $LEADER -- printenv | grep APP_DATABASE | sed 's/.*=//g')

# Dump and copy down
oc exec -n ${OLD_NS} $LEADER -- mkdir -p /tmp/dump
oc exec -n ${OLD_NS} $LEADER -- pg_dump -U postgres -d $OLD_DB -Fc -f /tmp/dump/dump_old --no-privileges --no-tablespaces --no-owner
oc cp -n ${OLD_NS} $LEADER:/tmp/dump .


### Restore to new prod db

# Vars
NEW_USER=$(oc exec -n ${NEW_NS} dc/fom-$TARGET-db -- printenv | grep -i POSTGRES_USER | sed 's/.*=//g')
NEW_DB=$(oc exec -n ${NEW_NS} dc/fom-$TARGET-db -- printenv | grep -i POSTGRES_DB | sed 's/.*=//g')
POD=$(oc exec -n ${NEW_NS} dc/fom-$TARGET-db -- hostname)

# Copy up and restore
oc cp dump_old -n ${NEW_NS} $POD:/tmp/
oc exec -n ${NEW_NS} $POD -- pg_restore -d $NEW_DB /tmp/dump_old -U $NEW_USER -c --no-owner || true


### Compare

# Tables
echo "--- old ---"
oc exec -n ${OLD_NS} $LEADER -- psql -U postgres -d $OLD_DB -c "select count (*) from pg_tables;"
echo "--- new ---"
oc exec -n ${NEW_NS} $POD -- psql -U $NEW_USER -d $NEW_DB -c "select count (*) from pg_tables;"

# Create new db_dump and compare to old one
oc exec -n ${NEW_NS} $POD -- pg_dump -d $NEW_DB -U $NEW_USER -Fc -f /tmp/dump_new --no-privileges --no-tablespaces --no-owner
oc exec -n ${NEW_NS} $POD -- ls -l /tmp/

### Cleanup

oc exec -n ${OLD_NS} $LEADER -- rm -rf /tmp/dump
oc exec -n ${NEW_NS} $POD -- rm /tmp/dump_new /tmp/dump_old
rm dump_old
