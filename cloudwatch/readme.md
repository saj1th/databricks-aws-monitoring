# Monitoring Databricks with AWS cloudwatch

This repository contains init script for monitoring databricks with AWS cloudwatch


```
dbutils.fs.put("dbfs:/databricks/cloudwatch-init.sh","""#!/bin/bash

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
CLUSTER_NAME=$CLUSTER_NAME-$DB_CLUSTER_ID

# configure cloudwatch agent for driver & executor
if  [  ! -z $DB_IS_DRIVER ] && [ $DB_IS_DRIVER = TRUE ] ; then
    cat > /tmp/amazon-cloudwatch-agent.json << EOF
{"agent":{"metrics_collection_interval":10,"logfile":"/var/log/amazon-cloudwatch-agent.log","debug":false},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/databricks/driver/logs/log4j-active.log","log_group_name":"/databricks/\$CLUSTER_NAME/driver/spark-log","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stderr","log_group_name":"/databricks/\$CLUSTER_NAME/driver/stderr","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stdout","log_group_name":"/databricks/\$CLUSTER_NAME/driver/stdout","log_stream_name":"databricks-cloudwatch"}]}}},"metrics":{"namespace":"\$CLUSTER_NAME","metrics_collected":{"statsd":{"service_address":":8125"},"cpu":{"resources":["*"],"measurement":[{"name":"cpu_usage_idle","rename":"DRIVER_CPU_USAGE_IDLE","unit":"Percent"},{"name":"cpu_usage_iowait","rename":"DRIVER_CPU_USAGE_IOWAIT","unit":"Percent"},{"name":"cpu_time_idle","rename":"DRIVER_CPU_TIME_IDLE","unit":"Percent"},{"name":"cpu_time_iowait","rename":"DRIVER_CPU_TIME_IOWAIT","unit":"Percent"}],"totalcpu":true},"disk":{"resources":["/"],"measurement":[{"name":"disk_free","rename":"DRIVER_DISK_FREE","unit":"Gigabytes"},{"name":"disk_inodes_free","rename":"DRIVER_DISK_INODES_FREE","unit":"Count"},{"name":"disk_inodes_total","rename":"DRIVER_DISK_INODES_TOTAL","unit":"Count"},{"name":"disk_inodes_used","rename":"DRIVER_DISK_INODES_USED","unit":"Count"}]},"diskio":{"resources":["*"],"measurement":[{"name":"diskio_iops_in_progress","rename":"DRIVER_DISKIO_IOPS_IN_PROGRESS","unit":"Megabytes"},{"name":"diskio_read_time","rename":"DRIVER_DISKIO_READ_TIME","unit":"Megabytes"},{"name":"diskio_write_time","rename":"DRIVER_DISKIO_WRITE_TIME","unit":"Megabytes"}]},"mem":{"measurement":[{"name":"mem_available","rename":"DRIVER_MEM_AVAILABLE","unit":"Megabytes"},{"name":"mem_total","rename":"DRIVER_MEM_TOTAL","unit":"Megabytes"},{"name":"mem_used","rename":"DRIVER_MEM_USED","unit":"Megabytes"},{"name":"mem_used_percent","rename":"DRIVER_MEM_USED_PERCENT","unit":"Megabytes"},{"name":"mem_available_percent","rename":"DRIVER_MEM_AVAILABLE_PERCENT","unit":"Megabytes"}]},"net":{"resources":["eth0"],"measurement":[{"name":"net_bytes_recv","rename":"DRIVER_NET_BYTES_RECV","unit":"Bytes"},{"name":"net_bytes_sent","rename":"DRIVER_NET_BYTES_SENT","unit":"Bytes"}]}},"append_dimensions":{"InstanceId":"\${aws:InstanceId}"}}}
EOF
	
  sed -i '/^log4j.appender.publicFile.layout/ s/^/#/g' /home/ubuntu/databricks/spark/dbconf/log4j/driver/log4j.properties
	sed -i '/log4j.appender.publicFile=com.databricks.logging.RedactionRollingFileAppender/a log4j.appender.publicFile.layout=com.databricks.labs.log.appenders.JsonLayout' /home/ubuntu/databricks/spark/dbconf/log4j/driver/log4j.properties
else
  cat > /tmp/amazon-cloudwatch-agent.json << EOF
{"agent":{"metrics_collection_interval":10,"logfile":"/var/log/amazon-cloudwatch-agent.log","debug":true},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/databricks/driver/logs/log4j-active.log","log_group_name":"/databricks/\$CLUSTER_NAME/driver/spark-log","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stderr","log_group_name":"/databricks/\$CLUSTER_NAME/driver/stderr","log_stream_name":"databricks-cloudwatch"},{"file_path":"/databricks/driver/logs/stdout","log_group_name":"/databricks/\$CLUSTER_NAME/driver/stdout","log_stream_name":"databricks-cloudwatch"}]}}},"metrics":{"namespace":"\$CLUSTER_NAME","metrics_collected":{"statsd":{"service_address":":8125"},"cpu":{"resources":["*"],"measurement":[{"name":"cpu_usage_idle","rename":"EXEC_CPU_USAGE_IDLE","unit":"Percent"},{"name":"cpu_usage_iowait","rename":"EXEC_CPU_USAGE_IOWAIT","unit":"Percent"},{"name":"cpu_time_idle","rename":"EXEC_CPU_TIME_IDLE","unit":"Percent"},{"name":"cpu_time_iowait","rename":"EXEC_CPU_TIME_IOWAIT","unit":"Percent"}],"totalcpu":true},"disk":{"resources":["/"],"measurement":[{"name":"disk_free","rename":"EXEC_DISK_FREE","unit":"Gigabytes"},{"name":"disk_inodes_free","rename":"EXEC_DISK_INODES_FREE","unit":"Count"},{"name":"disk_inodes_total","rename":"EXEC_DISK_INODES_TOTAL","unit":"Count"},{"name":"disk_inodes_used","rename":"EXEC_DISK_INODES_USED","unit":"Count"}]},"diskio":{"resources":["*"],"measurement":[{"name":"diskio_iops_in_progress","rename":"EXEC_DISKIO_IOPS_IN_PROGRESS","unit":"Megabytes"},{"name":"diskio_read_time","rename":"EXEC_DISKIO_READ_TIME","unit":"Megabytes"},{"name":"diskio_write_time","rename":"EXEC_DISKIO_WRITE_TIME","unit":"Megabytes"}]},"mem":{"measurement":[{"name":"mem_available","rename":"EXEC_MEM_AVAILABLE","unit":"Megabytes"},{"name":"mem_total","rename":"EXEC_MEM_TOTAL","unit":"Megabytes"},{"name":"mem_used","rename":"EXEC_MEM_USED","unit":"Megabytes"},{"name":"mem_used_percent","rename":"EXEC_MEM_USED_PERCENT","unit":"Megabytes"},{"name":"mem_available_percent","rename":"EXEC_MEM_AVAILABLE_PERCENT","unit":"Megabytes"}]},"net":{"resources":["eth0"],"measurement":[{"name":"net_bytes_recv","rename":"EXEC_NET_BYTES_RECV","unit":"Bytes"},{"name":"net_bytes_sent","rename":"EXEC_NET_BYTES_SENT","unit":"Bytes"}]}},"append_dimensions":{"InstanceId":"\${aws:InstanceId}"}}}
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
""", True)
```