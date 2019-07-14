#!/bin/bash

cat <<EOF > /tmp/start_datadog.sh
#!/bin/bash

set -ex

# Get the cluster name
pip install awscli
INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
ZONE=\$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=\${ZONE%?}
CLUSTER_NAME=\$(aws ec2 describe-tags --filters "Name=resource-id,Values=\$INSTANCE_ID" "Name=key,Values=ClusterName" --region=\$REGION --output=text | cut -f5)


# install the Datadog agent
sudo apt-get install apt-transport-https
#Set up the Datadog deb repo
sudo sh -c "echo 'deb https://apt.datadoghq.com/ stable 6' > /etc/apt/sources.list.d/datadog.list"
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 382E94DE
sudo apt-get update
sudo apt-get install datadog-agent
#Copy the example config into place and plug in your API key
sudo sh -c "sed 's/api_key:.*/api_key: <your-api-key>/' /etc/datadog-agent/datadog.yaml.example > /etc/datadog-agent/datadog.yaml"



if  [  ! -z \$DB_IS_DRIVER ] && [ \$DB_IS_DRIVER = TRUE ] ; then
  echo "On \$CLUSTER_NAME driver. configuring datadog ..."
  
  # WAITING UNTIL MASTER PARAMS ARE LOADED, THEN GRABBING IP AND PORT
  while [ -z \$gotparams ]; do
    if [ -e "/tmp/master-params" ]; then
      DB_DRIVER_PORT=\$(cat /tmp/master-params | cut -d' ' -f2)
      gotparams=TRUE
    fi
    sleep 2
  done

  current=\$(hostname -I | xargs)  
  mkdir -p /etc/datadog-agent/conf.d/
  # WRITING SPARK CONFIG FILE FOR STREAMING SPARK METRICS
  echo "init_config:
instances:
    - resourcemanager_uri: http://\$DB_DRIVER_IP:\$DB_DRIVER_PORT
      spark_cluster_mode: spark_standalone_mode
      cluster_name: \$current" > /etc/datadog-agent/conf.d/spark.yaml
else 
  echo "On \$CLUSTER_NAME executor. configuring datadog ..."
  #add tag to aggregate executor metrics
  sudo sh -c "cat <<EOFF >> /etc/datadog-agent/datadog.yaml
tags:
  - cluster:\$CLUSTER_NAME-\$DB_CLUSTER_ID-executors
EOFF"  
fi

# RESTARTING AGENT
sudo initctl start datadog-agent

EOF


chmod a+x /tmp/start_datadog.sh
/tmp/start_datadog.sh > /tmp/datadog_start.log 2>&1 & disown
