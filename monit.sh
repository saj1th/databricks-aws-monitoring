#!/bin/bash

set -ex

# jar for custom json logging
wget -q -O /mnt/driver-daemon/jars/log4j12-json-layout-1.0.0.jar https://sa-iot.s3.ca-central-1.amazonaws.com/collateral/log4j12-json-layout-1.0.0.jar

# jar for statsd sink
wget -q -O /mnt/driver-daemon/jars/spark-statsd-2.4.3.jar https://sa-iot.s3.ca-central-1.amazonaws.com/collateral/spark-statsd-2.4.3.jar

cd /tmp

# download cloudwatch agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb.sig
KEY=$(curl https://s3.amazonaws.com/amazoncloudwatch-agent/assets/amazon-cloudwatch-agent.gpg 2>/dev/null| gpg --import 2>&1 |  cut -d: -f2 | grep 'key' | sed -r 's/\s*|key//g')
FINGERPRINT=$(echo "9376 16F3 450B 7D80 6CBD 9725 D581 6730 3B78 9C72" | sed 's/\s//g')
# verify signature
if ! gpg --fingerprint $KEY| sed -r 's/\s//g' | grep -q "${FINGERPRINT}"; then
  echo "cloudwatch agent deb gpg key fingerprint is invalid"
  exit 1
fi
if ! gpg --verify ./amazon-cloudwatch-agent.deb.sig ./amazon-cloudwatch-agent.deb; then
  echo "cloudwatch agent signature does not match deb"
  exit 1
fi
sudo apt-get install ./amazon-cloudwatch-agent.deb

# Get the cluster name
pip install awscli
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=${ZONE%?}
CLUSTER_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=ClusterName" --region=$REGION --output=text | cut -f5)

# configure cloudwatch agent for driver & executor
if  [  ! -z $DB_IS_DRIVER ] && [ $DB_IS_DRIVER = TRUE ] ; then
    cat > /tmp/amazon-cloudwatch-agent.json << EOF
{"agent":{"metrics_collection_interval":10,"logfile":"/var/log/amazon-cloudwatch-agent.log","debug":false},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/databricks/driver/logs/log4j-active.log","log_group_name":"/databricks/$CLUSTER_NAME/driver/spark-log","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stderr","log_group_name":"/databricks/$CLUSTER_NAME/driver/stderr","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stdout","log_group_name":"/databricks/$CLUSTER_NAME/driver/stdout","log_stream_name":"databricks-cloudwatch"}]}}},"metrics":{"namespace":"$CLUSTER_NAME","append_dimensions":{"cluster_id":"databricks07"},"aggregation_dimensions":[["cluster_id"]],"metrics_collected":{"statsd":{"metrics_aggregation_interval":10,"metrics_collection_interval":10,"service_address":":8125"},"cpu":{"measurement":["cpu_usage_idle","cpu_usage_iowait","cpu_usage_user","cpu_usage_system"],"metrics_collection_interval":10},"mem":{"measurement":["mem_active","mem_available","mem_available_percent","mem_free","mem_inactive","mem_total","mem_used","mem_used_percent"],"metrics_collection_interval":10},"net":{"measurement":["net_bytes_recv","net_bytes_sent","net_drop_in","net_drop_out","net_err_in","net_err_out","net_packets_sent","net_packets_recv"],"metrics_collection_interval":10}}}}
EOF
	
  sed -i '/^log4j.appender.publicFile.layout/ s/^/#/g' /home/ubuntu/databricks/spark/dbconf/log4j/driver/log4j.properties
	sed -i '/log4j.appender.publicFile=com.databricks.logging.RedactionRollingFileAppender/a log4j.appender.publicFile.layout=com.databricks.labs.log.appenders.JsonLayout' /home/ubuntu/databricks/spark/dbconf/log4j/driver/log4j.properties
else
    cat > /tmp/amazon-cloudwatch-agent.json << EOF
{"agent":{"metrics_collection_interval":10,"logfile":"/var/log/amazon-cloudwatch-agent.log","debug":false},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/databricks/spark/work/*/*/stderr","log_group_name":"/databricks/$CLUSTER_NAME/executor/stderr","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/spark/work/*/*/stdout","log_group_name":"/databricks/$CLUSTER_NAME/executor/stdout","log_stream_name":"databricks-cloudwatch"}]}}},"metrics":{"namespace":"$CLUSTER_NAME","append_dimensions":{"cluster_id":"databricks07"},"aggregation_dimensions":[["cluster_id"]],"metrics_collected":{"statsd":{"metrics_aggregation_interval":10,"metrics_collection_interval":10,"service_address":":8125"},"cpu":{"measurement":["cpu_usage_idle","cpu_usage_iowait","cpu_usage_user","cpu_usage_system"],"metrics_collection_interval":10},"mem":{"measurement":["mem_active","mem_available","mem_available_percent","mem_free","mem_inactive","mem_total","mem_used","mem_used_percent"],"metrics_collection_interval":10},"net":{"measurement":["net_bytes_recv","net_bytes_sent","net_drop_in","net_drop_out","net_err_in","net_err_out","net_packets_sent","net_packets_recv"],"metrics_collection_interval":10}}}}
EOF

  sed -i '/^log4j.appender.console.layout/ s/^/#/g' /home/ubuntu/databricks/spark/dbconf/log4j/executor/log4j.properties
  sed -i '/log4j.appender.console.layout=org.apache.log4j.PatternLayout/a log4j.appender.console.layout=com.databricks.labs.log.appenders.JsonLayout' /home/ubuntu/databricks/spark/dbconf/log4j/executor/log4j.properties
fi


#modify metrics config
sudo sed -i '/^driver.sink.ganglia.class/,+4 s/^/#/g' /databricks/spark/conf/metrics.properties
sudo bash -c "cat <<EOF >> /databricks/spark/conf/metrics.properties
*.sink.statsd.class=org.apache.spark.metrics.sink.StatsdSink
*.sink.statsd.host=localhost
*.sink.statsd.port=8125
*.sink.statsd.prefix=spark
master.source.jvm.class=org.apache.spark.metrics.source.JvmSource
worker.source.jvm.class=org.apache.spark.metrics.source.JvmSource
driver.source.jvm.class=org.apache.spark.metrics.source.JvmSource
executor.source.jvm.class=org.apache.spark.metrics.source.JvmSource
EOF"

#start cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/amazon-cloudwatch-agent.json -s
sudo systemctl enable amazon-cloudwatch-agent

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status -m ec2