# Datadog Integration


To install and configure datadog agent in databricks clusters

Edit datadog.sh; add the datadog key in place of `your-api-key` and copy the file to dbfs

The scrpt collects spark metrics and system metrics from the driver.

One the executors, it adds a tag `cluster-name-cluster-id-executors` so that in datadog, we could aggregate the metrics like CPU, Ram etc for the whole cluster.

To debug, 
	- check the log at `/tmp/datadog_start.log`
	- check datadog status via `sudo datadog-agent status`

