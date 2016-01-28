#!/bin/sh

# base directory where cluster configs will be created
BASEDIR="/tmp/influxdb-cluster"
# preserve BASEDIR and all of its contents if PRESERVE > 0
PRESERVE=0
# path to influxd binary
INFLUXD=influxd
# generated influxd config file name
CONFIG="influxd.toml"
# do not start influxd using -join if NOJOIN > 1
NOJOIN=0

# parse command line options
while getopts ":b:c:pe:j" opt; do
	case $opt in
		b)
			BASEDIR="$OPTARG"
			;;
		c)
			CONFIG="$OPTARG"
			;;
		p)
			PRESERVE=1
			;;
		e)
			INFLUXD=$OPTARG
			;;
		j)
			NOJOIN=1
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

# delete the base dir if it exists and we're not supposed to preserve it
if [ -d "$BASEDIR" -a "$PRESERVE" -le 0 ]; then
	rm -rf $BASEDIR
fi

# create the base dir for cluster configs
if [ ! -d "$BASEDIR" ]; then
	mkdir -p $BASEDIR
fi

# change to the base dir
cd $BASEDIR

# addNode takes a node number and creates a sub directory for the node's
# config and data files
addNode () {
	# node's base directory
	NODEDIR="$BASEDIR/n$1"
	# node's config file
	NODECFG="$NODEDIR/$CONFIG"

	# make the node's base directory
	mkdir -p $NODEDIR

	# tell influxd to generate a default config for the node
	eval ${INFLUXD} config > $NODECFG
	# replace the port numbers in the config based on the node number passed in
	sed -i.bak s/:80/localhost:8$1/g $NODECFG
	# replace the default InfluxDB data dir with this node's dir
	sed -i.bak s@$HOME@$NODEDIR@g $NODECFG
	# append node to list of peers
	if [ -z "$JOIN" ]; then
		JOIN="localhost:8${1}91"
	else
		JOIN="$JOIN, localhost:8${1}91"
	fi
}

# call addNode to generate node configurations
if [ "$PRESERVE" -le 0 ]; then
	addNode "1"
	addNode "2"
	addNode "3"
fi

# finish building (or clearing) -join arguments
if [ "$NOJOIN" -gt 0 ]; then
	JOIN=""
else
	JOIN="-join $JOIN"
fi

set -x
# bring up the nodes and join them as a cluster
eval ${INFLUXD} -config $BASEDIR/n1/$CONFIG &
#eval ${INFLUXD} -config $BASEDIR/n1/$CONFIG -join "localhost:8191,localhost:8291,localhost:8391" &
eval ${INFLUXD} -config $BASEDIR/n2/$CONFIG $JOIN &
eval ${INFLUXD} -config $BASEDIR/n3/$CONFIG $JOIN &
