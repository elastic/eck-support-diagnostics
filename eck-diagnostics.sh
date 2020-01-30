#!/usr/bin/env bash 

output_path=/tmp
diag_name=eck_diag_$(hostname)_$(date "+%d_%b_%Y_%H_%M_%S")
kubernetes_skip_logs=false 
kubernetes_logs_since="1h"
kubernetes_namespace="default"
kubernetes_operator_namespace="elastic-system"
kubernetes_label_selector="common.k8s.elastic.co/type"
kubernetes_kinds="pods,pv,pvc,configmap,ingress,service,deployment,statefulset,events,networkpolicies"

HARD_LIMIT_LOG_LINES=10000  # retrieving all log lines with --since (without --tail) results in hanging and high CPU as per https://github.com/kubernetes/kubernetes/issues/48465

assign_output_paths() {
 diag_folder=$output_path/$diag_name
 docker_folder=$diag_folder/docker
 kubernetes_folder=$diag_folder/kubernetes
 kubernetes_logs_folder=$kubernetes_folder/logs
}

assign_output_paths

create_folders(){
	case $1 in
		system)
		mkdir -p $diag_folder
		;;
		docker)
		mkdir -p $docker_folder
		;;
		logs)
		mkdir -p $logs_folder
		;;
		kubernetes)
		mkdir -p $kubernetes_logs_folder
		;;
	esac
}

clean(){
	print_msg "Cleaning temp files..." "INFO"
	rm -rf $diag_folder
}




create_archive(){

	if [ -d $diag_folder ]
		then
			print_msg "Compressing diag file..." "INFO"
                        cd $output_path && tar czf $diag_name.tar.gz $diag_name/* 2>&1
                        print_msg "Diag ready at $output_path/$diag_name.tar.gz" "INFO"
                else
                        print_msg "Nothing to do." "INFO"
			exit 1
	fi
}

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

show_help(){
	echo "ECK Diagnostics"
	echo "Usage: ./eck-diagnostics.sh [OPTIONS]"
	echo ""
	echo "Options:"
	echo "-s|--system #collects system information"
	echo "-d|--docker #collects docker information"
	echo "-k|--kubernetes #collects kubernetes information Optionally specify kinds | $kubernetes_kinds"
	echo "-n|--kubernetes-namespace #location of user resources | $kubernetes_namespace"
	echo "-N|--kubernetes-operator-namespace # location of elastic operators | $kubernetes_operator_namespace"
	echo "-t|--kubernetes-logs-since #kubernetes logs since | $kubernetes_logs_since (max $HARD_LIMIT_LOG_LINES)"
	echo "-nl|--kubernetes-skip-logs #don't collect kubernetes logs"
	echo "-o|--output-path #Specifies the output directory to dump the diagnostic bundles | $output_path"
	echo "-h|--help #shows this"
	echo ""
	echo "Sample usage:"
	echo "\"./eck-diagnostics.sh -d -s -k\" #collects docker, system and kubernetes level info"
	echo ""
}

is_supported_os(){
 os=$(uname -a) 
 if [[ $os == *"Darwin"* ]] || [[ $os == *"CYGWIN"* ]]; then
  return 1; #false, not supported
 else
  return 0; #true, looks good
 fi
}

get_system(){
    

	#system info
	print_msg "Gathering system info..." "INFO"
	uname -a > $diag_folder/uname.txt
	cat /etc/*-release > $diag_folder/linux-release.txt
	top -n1 -b > $diag_folder/top.txt
	ps -eaf > $diag_folder/ps.txt
	df -h > $diag_folder/df.txt

	#network
	sleep 1
	print_msg "Gathering network info..." "INFO"
	sleep 1
	sudo netstat -anp > $diag_folder/netstat_all.txt 2>&1
	sudo netstat -ntulpn > $diag_folder/netstat_listening.txt 2>&1
	sudo iptables -L > $diag_folder/iptables.txt 2>&1
	sudo route -n > $diag_folder/routes.txt 2>&1

	#mounts
	sudo mount > $diag_folder/mounts.txt 2>&1
	sudo cat /etc/fstab > $diag_folder/fstab.txt 2>&1

	#SAR
	print_msg "Gathering SAR output..." "INFO"
	sleep 1
	#check sar exists
	if [ -x "$(type -P sar)" ];
		then
			#sar individual devices - sample 5 times every 1 second
			print_msg "SAR [sampling individual I/O devices]" "INFO"
			sar -d -p 1 5 > $diag_folder/sar_devices.txt 2>&1
			#CPU usage - individual cores - sample 5 times every 1 second
			print_msg "SAR [sampling CPU cores usage]" "INFO"
			sar -P ALL 1 5 > $diag_folder/sar_cpu_cores.txt 2>&1
			#load average last 1-5-15 minutes - 1 sample
			print_msg "SAR [collect load average]" "INFO"
			sar -q 1 1 > $diag_folder/sar_load_average_sampled.txt 2>&1
			#memory - sample 5 times every 1 second
			print_msg "SAR [sampling memory usage]" "INFO"
			sar -r 1 5 > $diag_folder/sar_memory_sampled.txt 2>&1
			#swap - sample once
			print_msg "SAR [collect swap usage]" "INFO"
			sar -S 1 1 > $diag_folder/sar_swap_sampled.txt 2>&1
			#network
			print_msg "SAR [collect network stats]" "INFO"
			sar -n DEV > $diag_folder/sar_network.txt 2>&1
		else
			print_msg "'sar' command not found. Please install package 'sysstat' to collect extended system stats" "WARN"
	fi
}

get_docker(){

	print_msg "Grabbing docker ps..." "INFO"
	# output of docker ps -a
	docker ps -a > $docker_folder/ps.txt

	print_msg "Grabbing docker info..." "INFO"
	# output of docker info
	docker info > $docker_folder/info.txt 2>&1

	print_msg "Grabbing docker images..." "INFO"
	# output of docker info
	docker images --all --digests > $docker_folder/images.txt 2>&1

	i=5
	print_msg "Grabbing $i repeated container stats..." "INFO"
	# sample container stats
	while [ $i -ne 0 ] ; do date >> $docker_folder/stats_samples.txt ; print_msg "Grabbing docker stats $i" "INFO"; docker stats --no-stream >> $docker_folder/stats_samples.txt ; i=$((i-1)); done
}

get_kubernetes(){

        #Base K8s info
	request="kubectl get nodes -o=json "
	print_msg "Calling $request" "INFO"
	$request > $kubernetes_folder/nodes.json
	request="kubectl version -o=json "
	print_msg "Calling $request" "INFO"
	$request > $kubernetes_folder/version.json

        #Elastic Custom Resources from User Namespace
	request="kubectl get elastic -o=json -n=$kubernetes_namespace"
	print_msg "Calling $request" "INFO"
	$request > $kubernetes_folder/elastic-resources.json

        #Resources from User Namespace
	request="kubectl get $kubernetes_kinds -o=json -n=$kubernetes_namespace -l $kubernetes_label_selector"
	print_msg "Calling $request" "INFO"
	$request > $kubernetes_folder/resources.json

        #Secrets (name only)
	request="kubectl get secrets -n=$kubernetes_namespace -l $kubernetes_label_selector"
	print_msg "Calling $request (Retrieves Names Only)" "INFO"
	$request > $kubernetes_folder/secrets.txt

        #Resources from Operator Namespace
	request="kubectl get $kubernetes_kinds -o=json -n=$kubernetes_operator_namespace"
	print_msg "Calling $request" "INFO"
	$request > $kubernetes_folder/operator-resources.json
  

        $kubernetes_skip_logs && return;

        #Operator Logs
        mkdir -p $kubernetes_logs_folder/operator
	kubectl get pods -o=custom-columns=NAMESPACE:.metadata.namespace,KIND:.kind,NAME:.metadata.name --no-headers -n=$kubernetes_operator_namespace | \
	while read namespace kind name
	do
		request="kubectl logs $name --tail=$HARD_LIMIT_LOG_LINES --since=$kubernetes_logs_since -n $namespace "
		print_msg "Calling $request" "INFO"
		$request > $kubernetes_logs_folder/operator/$name.log
	done


        #Pod Logs
        mkdir -p $kubernetes_logs_folder/user
	kubectl get pods -o=custom-columns=NAMESPACE:.metadata.namespace,KIND:.kind,NAME:.metadata.name --no-headers -n=$kubernetes_namespace -l $kubernetes_label_selector | \
	while read namespace kind name
	do
		request="kubectl logs $name --tail=$HARD_LIMIT_LOG_LINES --since=$kubernetes_logs_since -n $namespace "
		print_msg "Calling $request" "INFO"
		$request > $kubernetes_logs_folder/user/$name.log
	done

}

process_action(){
	case $1 in
		kubernetes)
		if [ -x "$(command -v kubectl)" ] ; then
			create_folders kubernetes
			get_kubernetes 
                else
			print_msg "kubectl command not found, skipping system information collection (-k)" "ERROR"
			return
		fi
		;;
		system)
		if is_supported_os && pgrep -x "kubelet" >/dev/null; then
			create_folders system
			get_system
		else
			print_msg "Unsupported OS, or kubelet process not found skipping system information collection (-s)" "ERROR"
			return
		fi
		;;
		docker)
		if is_supported_os && [ -x "$(command -v docker)" ] && pgrep -x "kubelet" >/dev/null ; then
			create_folders docker
			get_docker 
		else
			print_msg "Unsupported OS or kubelet/docker not found, skipping docker information collection (-d)" "ERROR"
			return
		fi	
		;;
	esac
	shift
}


print_msg(){
	#$1 msg
	#$2 sev
	local sev=
	if [ -n $2 ]
		then
			sev="[$2]"
	fi
	echo "`date` $sev:  $1"

}

isValue(){ # Is this a string value, and not another parameter?
 if  [[ -z "$1" ]] || [[ $1 = \-* ]] ; then
  return 1; #return false, this is not a valid parameter value
 else
  return 0; #looks good
 fi
}

#BEGIN

# no arguments -> show help
if [ "$#" -eq 0 ]; then
	show_help
# arguments - parse them
else
	while :; do
	    	case $1 in
		    -h|--help)
	            show_help 
 		    exit 0
                    ;;
		    -k|--kubernetes)
		    if isValue $2; then
                    	kubernetes_kinds=$2
                        shift
                    fi
	            actions="$actions kubernetes"
                    ;;
		    -n|--kubernetes-namespace)
		    if isValue "$2"; then
                       kubernetes_namespace="$2" 
                       shift
		    else
                       die 'ERROR: "-n|--kubernetes-namespace" requires a valid string'
                    fi
                    ;;
		    -N|--kubernetes-operator-namespace)
		    if isValue "$2"; then
                       kubernetes_operator_namespace="$2" 
                       shift
		    else
                       die 'ERROR: "-N|--kubernetes-operator-namespace" requires a valid string'
                    fi
	            ;;
		    -t|--kubernetes-logs-since)
		    if isValue "$2"; then
                       kubernetes_logs_since="$2" 
                       shift
		    else
                       die 'ERROR: "-t|--kubernetes-logs-since" requires a valid string'
                    fi
                    ;;
		    -nl|--kubernetes-skip-logs)
                    kubernetes_skip_logs=true
                    ;;
	            -s|--system)
	            #gather system data
	            actions="$actions system"
		    ;;
		    -o|--output-path)
		    if isValue "$2"; then
			output_path=$2
			assign_output_paths
			shift
                    else
                        die 'ERROR: "-o|--output-path" requires a valid full filesystem path'
                    fi
                    ;;
	            -d|--docker)
	            #gather docker data
	            actions="$actions docker"
	            ;;
	    	    --)              # End of all options.
            	    shift
                    break
                    ;;
                    -?*)
                    printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
                    ;;
                    *)               # Default case: No more options, so break out of the loop.
                    break
		esac
	    	shift
	done
fi

print_msg "ECK Diagnostics" "INFO"

# go through identified actions and execute
if [ -z "$actions" ]
	then
		: #do nothing
	else
		actions=($actions)
		actionsLength=${#actions[@]}

		for ((a=0; a<$actionsLength; a++))
        	do
        		process_action ${actions[$a]}
		done

fi

create_archive && clean
