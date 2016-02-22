#!/bin/sh

# base directory where cluster configs will be created
BASEDIR="/tmp/clusterflux"
# preserve BASEDIR and all of its contents if PRESERVE > 0
PRESERVE=0
# path to influxd binary
INFLUXD=influxd
# generated influxd config file name
CONFIG="influxd.toml"
# do not start influxd using -join if NOJOIN > 1
NOJOIN=0
# list of peers to join
JOIN=""
# number of nodes that are both meta & data nodes
NODES=3
META_NODES=0
DATA_NODES=0

# parse command line options
while getopts ":b:c:pe:jt:d:m:n:k:f:" opt; do
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
		t)
			TMUX_SESSION=$OPTARG
			;;
		d)
			# data only nodes
			DATA_NODES=$OPTARG
			;;
		m)
			# meta only nodes
			META_NODES=$OPTARG
			;;
		n)
			# meta & data nodes
			NODES=$OPTARG
			;;
		k)
			tmux kill-session -t $OPTARG
			exit 0
			;;
		f)
			TEST_FILE=$OPTARG
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

# copy utility scripts to base dir
echo 'influx -port 8186 -execute "show servers"' > $BASEDIR/servers.sh && chmod ug+x $BASEDIR/servers.sh
if [ ! -z "$TEST_FILE" ]; then
	cp $TEST_FILE $BASEDIR
	testFileName=$(echo "$TEST_FILE" | awk -F/ '{print $NF}')
	chmod ug+x $BASEDIR/$testFileName
fi

# change to the base dir
cd $BASEDIR

# createNodeConfig takes a node number and creates a sub directory for the node's
# config and data files
createNodeConfig () {
	# node's base directory
	NODEDIR="$BASEDIR/n$1"
	# node's config file
	NODECFG="$NODEDIR/$CONFIG"
	# true if data only node
	ONLY="$2"

	if [ "$PRESERVE" -le 0 ]; then
		# make the node's base directory
		mkdir -p $NODEDIR

		# tell influxd to generate a default config for the node
		eval ${INFLUXD} config > $NODECFG
		# replace the port numbers in the config based on the node number passed in
		sed -i.bak s/:80/localhost:8$1/g $NODECFG
		# replace the default InfluxDB data dir with this node's dir
		sed -i.bak s@$HOME@$NODEDIR@g $NODECFG
		# update config for meta or data only
		if [ "$ONLY" = "meta" ]; then
			perl -0777 -i.original -pe 's/\[data\]\n  enabled = true/[data]\n  enabled = false/igs' $NODECFG
		elif [ "$ONLY" = "data" ]; then
			perl -0777 -i.original -pe 's/\[meta\]\n  enabled = true/[meta]\n  enabled = false/igs' $NODECFG
		fi
	fi

	# append node to list of peers
	if [ "$NOJOIN" -le 0 ]; then
		if [ "$JOIN" = "" ]; then
			JOIN="-join localhost:8${1}91"
		else
			JOIN="$JOIN,localhost:8${1}91"
		fi
	fi
}

# startNode starts influxd for the specified node
startNode() {
	# node's number
	nodeNum=$1
	# node's name
	NODE="n$nodeNum"
	# node's base directory
	NODEDIR="$BASEDIR/$NODE"
	# node's config file
	NODECFG="$NODEDIR/$CONFIG"

	#if [ "$NODE" = "n1" ]; then
	#	echo "$NODE: no join"
	#	if [ ! -z "$TMUX_SESSION" ]; then
	#		tmux send-keys -t $TMUX_SESSION:$tmuxWindow.$((firstPane + nodeNum)) "eval ${INFLUXD} -config $BASEDIR/$NODE/$CONFIG &" C-m
	#	else
	#		eval ${INFLUXD} -config $BASEDIR/$NODE/$CONFIG &
	#	fi
	#else
		echo "$NODE: $JOIN"
		if [ ! -z "$TMUX_SESSION" ]; then
			tmux send-keys -t $TMUX_SESSION:$tmuxWindow.$((firstPane + nodeNum)) "eval ${INFLUXD} -config $BASEDIR/$NODE/$CONFIG $JOIN &" C-m
		else
			eval ${INFLUXD} -config $BASEDIR/$NODE/$CONFIG $JOIN &
		fi
	#fi
}

totalNodes=$((NODES + META_NODES + DATA_NODES))

if [ ! -z "$TMUX_SESSION" ]; then
	sessionExists=$(tmux ls  2>/dev/null | grep -e "^$TMUX_SESSION:" | wc -l)
	if [ "$sessionExists" -le "0" ]; then
		tmux new-session -d -s $TMUX_SESSION
		tmuxWindow=0
	else
		tmux new-window -t $TMUX_SESSION -a
		tmuxWindow=$(tmux display-message -p | awk '{print $2}' | awk -F: '{print $1}')
	fi

	firstPane=$(tmux display-message -p | awk '{print $5}')

	tmux split-window -h -t $TMUX_SESSION -p 60 
	totalLines=$(tput lines)
	panelSize=$((totalLines / totalNodes))
fi

nextNodeNum=1

# createNodes creates the requested number of nodes of the specified type
createNodes () {
	numNodes=$1
	nodeType="$2"

	for i in $(seq 1 $numNodes); do
		if [ ! -z "$TMUX_SESSION" -a "$nextNodeNum" -gt "1" ]; then
			tmux split-window -v -t $TMUX_SESSION:$tmuxWindow.$((firstPane + 1)) -l $panelSize
		fi
		createNodeConfig "$nextNodeNum" "$nodeType"
		nextNodeNum=$((nextNodeNum+1))
	done
}

# create all of the requested nodes
createNodes "$NODES" "both"
createNodes "$META_NODES" "meta"
createNodes "$DATA_NODES" "data"

# bring up the nodes and join them as a cluster
for i in $(seq 1 $totalNodes); do
	startNode "$i"
done

if [ ! -z "$TMUX_SESSION" ]; then
	tmux select-pane -t $TMUX_SESSION:$tmuxWindow.$firstPane
	if [ "$tmuxWindow" -eq "0" ]; then
		tmux -2 attach-session -t $TMUX_SESSION
	fi
fi
