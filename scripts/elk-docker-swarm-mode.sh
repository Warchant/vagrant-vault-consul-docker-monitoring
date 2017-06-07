#!/usr/bin/env bash

# Allows to easily spin up an ELK stack running in Docker Swarm Mode (1.12+)
# Larry Smith Jr.
# @mrlesmithjr
# http://everythingshouldbevirtual.com

# Turn on verbose execution
set -x

# Define variables
PRI_DOMAIN_NAME="etsbv.internal"
BACKEND_NET="elasticsearch-backend"
ELASTICSEARCH_IMAGE="elasticsearch:2.4"
ELK_ES_SERVER="escluster"
ELK_ES_SERVER_PORT="9200"
ELK_REDIS_SERVER="redis"
FRONTEND_NET="elasticsearch-frontend"
KIBANA_IMAGE="kibana:4.6.3"
#DOCKER_NETWORKS="$(docker network ls | awk 'FNR >1' | awk '{print $2}')"

# Check/create Backend Network if missing
docker network ls | grep $BACKEND_NET
RC=$?
if [ $RC != 0 ]; then
  docker network create -d overlay $BACKEND_NET
fi

# Check/create Frontend Network if missing
docker network ls | grep $FRONTEND_NET
RC=$?
if [ $RC != 0 ]; then
  docker network create -d overlay $FRONTEND_NET
fi

# Spin up official Elasticsearch Docker image
docker service ls | grep $ELK_ES_SERVER
RC=$?
if [ $RC != 0 ]; then
  docker service create \
    --endpoint-mode dnsrr \
    --mode global \
    --name $ELK_ES_SERVER \
    --network $BACKEND_NET \
    --update-delay 60s \
    --update-parallelism 1 \
    $ELASTICSEARCH_IMAGE \
    elasticsearch \
    -Des.discovery.zen.ping.multicast.enabled=false \
    -Des.discovery.zen.ping.unicast.hosts=$ELK_ES_SERVER \
    -Des.gateway.expected_nodes=3 \
    -Des.discovery.zen.minimum_master_nodes=2 \
    -Des.gateway.recover_after_nodes=2 \
    -Des.network.bind=_eth0:ipv4_
fi

# Spin up offical Kibana Docker image
docker service ls | grep kibana
RC=$?
if [ $RC != 0 ]; then
  docker service create \
    --mode global \
    --name kibana \
    --network $BACKEND_NET \
    --publish 5601:5601 \
    -e ELASTICSEARCH_URL=http://$ELK_ES_SERVER:$ELK_ES_SERVER_PORT \
    $KIBANA_IMAGE
fi

# Spin up official Redis Docker images
docker service ls | grep $ELK_REDIS_SERVER
RC=$?
if [ $RC != 0 ]; then
  docker service create \
    --endpoint-mode dnsrr \
    --mode global \
    --name $ELK_REDIS_SERVER \
    --network $BACKEND_NET \
    redis
fi

# Spin up custom Logstash Docker image w/configs already configured
docker service ls | grep logstash-pre-processor
RC=$?
if [ $RC != 0 ]; then
  docker service create \
    --mode global \
    --name logstash-pre-processor \
    --network $BACKEND_NET \
    --publish 10514:10514 \
    --publish 5044:5044 \
    -e REDIS_SERVER=$ELK_REDIS_SERVER \
    mrlesmithjr/logstash-pre-processor
fi

# Spin up custom Logstash Docker image w/configs already configured
docker service ls | grep logstash-processor
RC=$?
if [ $RC != 0 ]; then
  docker service create \
    --mode global \
    --name logstash-processor \
    --network $BACKEND_NET \
    -e ES_SERVER=$ELK_ES_SERVER:$ELK_ES_SERVER_PORT \
    -e REDIS_SERVER=$ELK_REDIS_SERVER \
    mrlesmithjr/logstash-processor
fi
