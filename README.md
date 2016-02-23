# clusterflux
shell script for creating local InfluxDB clusters

Example of starting a 3 node cluster:
```
clusterflux.sh -e ~/i/go/src/github.com/influxdata/influxdb/cmd/influxd/influxd -t cflux -f ~/issues/droprp.sh
```
The command above does the following:
* Creates `/tmp/clusterflux`
* Creates 3 sub folders `/tmp/clusterflux/n1, `n2`, and `n3` which hold config & data for nodes
* Copies `~/issues/droprp.sh` test script to the tmp dir
* Attaches to the `cflux` tmux session or creates it if it doesn't exist
* Starts up the cluster
