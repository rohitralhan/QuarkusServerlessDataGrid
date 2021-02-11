#!/bin/sh
echo
echo "############# Provisioning Started #############"
echo 
SERVERLESS_PROJECT_NAME="serverless-apps-1"
SERVERLESS_PROJECT_DISPLAY_NAME="ServerlessApps"

DATAGRID_PROJECT_NAME="datagrid-ws-1"
DATAGRID_PROJECT_DISPLAY_NAME="DataGridCluster"

# Create the namespaces for the serverless apps and DataGrid
echo "Creating projects: $SERVERLESS_PROJECT_NAME and $DATAGRID_PROJECT_NAME"
oc new-project $SERVERLESS_PROJECT_NAME --display-name=$SERVERLESS_PROJECT_DISPLAY_NAME --description=$SERVERLESS_PROJECT_DISPLAY_NAME
oc new-project $DATAGRID_PROJECT_NAME --display-name=$DATAGRID_PROJECT_DISPLAY_NAME --description=$DATAGRID_PROJECT_DISPLAY_NAME

# Delete limits on RHPDS, until we figure out how to properly configure the defaults.
# oc delete limits/$PROJECT_NAME-core-resource-limits -n $PROJECT_NAME
echo "Installing $DATAGRID_PROJECT_DISPLAY_NAME Workspaces Operator."
cat operator-datagrid_grp_sub.yaml | sed -e "s/namespace-placeholder/$DATAGRID_PROJECT_NAME/g" | oc apply -n $DATAGRID_PROJECT_NAME -f -
sleep 30
oc wait --for=condition=Ready -n $DATAGRID_PROJECT_NAME --timeout=3000s `oc get pods -o name` 
cat operator-datagrid_create_cluster.yaml | sed -e "s/namespace-placeholder/$DATAGRID_PROJECT_NAME/g" | oc apply -n $DATAGRID_PROJECT_NAME -f -

# This seems to be needed to allow the API of Che resources/CRDs to be available in the cluster.
echo "Wait for the Operator to be installed."
sleep 30

# Generate Certificate
echo "Generating SSL Certs & Installing Client Secret."
oc get secrets/signing-key -n openshift-service-ca -o template='{{index .data "tls.crt"}}' | openssl base64 -d -A > ./server.crt
keytool -importcert -keystore ./server.jks -storepass password -file ./server.crt -trustcacerts -noprompt
# oc project $SERVERLESS_PROJECT_NAME
oc create secret generic clientcerts -n $SERVERLESS_PROJECT_NAME --from-file=clientcerts=./server.jks
rm -rf server.jks server.crt


# Install the serverless server app
echo "Installing $SERVERLESS_PROJECT_NAME Applications."
LB=`oc describe service example-infinispan-external -n $DATAGRID_PROJECT_NAME | grep 'LoadBalancer Ingress' | awk -F ':' '{ gsub(/^[ \t]+/, "", $2); print $2 }'`
UP=`oc get secret/example-infinispan-generated-secret -n $DATAGRID_PROJECT_NAME -o template='{{index .data "identities.yaml"}}' | openssl base64 -d -A | grep -A 1 "username: developer" | grep "password" | awk -F ": " '{ print $2 }'`
cat knative-quarkus-serverless.yaml | sed -e "s/namespace-placeholder/$SERVERLESS_PROJECT_NAME/g" | sed -e "s/-datagrid-host/$LB/g" | sed -e "s/-user-password/$UP/g" | oc apply -n $SERVERLESS_PROJECT_NAME -f -

echo "Wait for the Application to be installed."
sleep 40
RH=`kn service list -n $SERVERLESS_PROJECT_NAME | grep quarkus-serverless-server | awk -F '://' '{ print $2 }' | awk -F ' ' '{ print $1 }'`
cat knative-quarkus-serverless-client.yaml | sed -e "s/namespace-placeholder/$SERVERLESS_PROJECT_NAME/g" | sed -e "s/-remote-host/$RH/g" | oc apply -n $SERVERLESS_PROJECT_NAME -f -

#oc wait --for=condition=Ready -n $SERVERLESS_PROJECT_NAME --timeout=3000s `oc get pods -o name -n $SERVERLESS_PROJECT_NAME`
#echo "Inserting Data..."
#curl -H "Content-Type: application/json" -X POST -d '[ { "empId": "1A", "empName": "John Doe", "empProject": "Quarkus" }, { "empId": "2A", "empName": "Jane Doe", "empProject": "Quarkus" }, { "empId": "3A", "empName": "Jo Doe", "empProject": "Quarkus" } ]' $RH/employees

echo
echo "############# Provisioning Completed #############"
echo
#oc delete project $SERVERLESS_PROJECT_NAME
#oc delete project $DATAGRID_PROJECT_NAME