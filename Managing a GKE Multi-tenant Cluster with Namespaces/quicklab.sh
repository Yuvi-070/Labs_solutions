#!/bin/bash

gcloud auth list

# Fetch zone and region
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")

  
PROJECT_ID=$(gcloud config get-value project)

gsutil -m cp -r gs://spls/gsp766/gke-qwiklab ~

cd ~/gke-qwiklab

gcloud config set compute/zone ${ZONE} && gcloud container clusters get-credentials multi-tenant-cluster

kubectl get namespace

kubectl api-resources --namespaced=true

kubectl get services --namespace=kube-system

kubectl create namespace team-a && \
kubectl create namespace team-b

kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity && \
kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-b -- sleep infinity

kubectl get pods -A

kubectl config set-context --current --namespace=team-a

gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
--member=serviceAccount:team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com  \
--role=roles/container.clusterViewer

kubectl create role pod-reader \
--resource=pods --verb=watch --verb=get --verb=list

kubectl create -f developer-role.yaml

kubectl create rolebinding team-a-developers \
--role=developer --user=team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com

gcloud iam service-accounts keys create /tmp/key.json --iam-account team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com

gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${GOOGLE_CLOUD_PROJECT}

# gcloud auth activate-service-account  --key-file=/tmp/key.json

# export ZONE=us-east4-c
# gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${GOOGLE_CLOUD_PROJECT}

# export ZONE=us-east4-c
# gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${GOOGLE_CLOUD_PROJECT}


kubectl create quota test-quota \
--hard=count/pods=2,count/services.loadbalancers=1 --namespace=team-a

kubectl run app-server-2 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity

kubectl run app-server-3 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity

export KUBE_EDITOR="nano"
kubectl edit quota test-quota --namespace=team-a

kubectl create -f cpu-mem-quota.yaml

kubectl create -f cpu-mem-demo-pod.yaml --namespace=team-a


kubectl patch quota test-quota \
  -n team-a \
  --type=merge \
  -p '{"spec":{"hard":{"count/pods":"6"}}}'


kubectl create -f cpu-mem-quota.yaml

kubectl create -f cpu-mem-demo-pod.yaml --namespace=team-a


gcloud container clusters \
  update multi-tenant-cluster --zone ${ZONE} \
  --resource-usage-bigquery-dataset cluster_dataset


export GCP_BILLING_EXPORT_TABLE_FULL_PATH=${GOOGLE_CLOUD_PROJECT}.billing_dataset.gcp_billing_export_v1_xxxx
export USAGE_METERING_DATASET_ID=cluster_dataset
export COST_BREAKDOWN_TABLE_ID=usage_metering_cost_breakdown


export USAGE_METERING_QUERY_TEMPLATE=~/gke-qwiklab/usage_metering_query_template.sql
export USAGE_METERING_QUERY=cost_breakdown_query.sql
export USAGE_METERING_START_DATE=2020-10-26


sed \
-e "s/\${fullGCPBillingExportTableID}/$GCP_BILLING_EXPORT_TABLE_FULL_PATH/" \
-e "s/\${projectID}/$GOOGLE_CLOUD_PROJECT/" \
-e "s/\${datasetID}/$USAGE_METERING_DATASET_ID/" \
-e "s/\${startDate}/$USAGE_METERING_START_DATE/" \
"$USAGE_METERING_QUERY_TEMPLATE" \
> "$USAGE_METERING_QUERY"

bq query \
--project_id=$GOOGLE_CLOUD_PROJECT \
--use_legacy_sql=false \
--destination_table=$USAGE_METERING_DATASET_ID.$COST_BREAKDOWN_TABLE_ID \
--schedule='every 24 hours' \
--display_name="GKE Usage Metering Cost Breakdown Scheduled Query" \
--replace=true \
"$(cat $USAGE_METERING_QUERY)"

