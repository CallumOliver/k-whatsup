#!/bin/bash
# 
#Defining variables
DIRECTORY="/tmp/k-whatsup-dir"

#Defining Functions

pause_function () {
	read -p "Press any key to continue... " -n1 -s
	echo  ""
}

converse_function () {
  echo -e $say_var
  read -p "$ask_var" return_var
}
# example usage
#  say_var="\nquestion here\n newline"
#  ask_var="please enter it here:"
#  converse_function $say_var $ask_var


scan_function () {
#checks if directory exists before scan
	if [[ ! -d "$DIRECTORY" ]]
		then
			echo "$DIRECTORY does not exist in this folder. Creating $DIRECTORY now"
			mkdir -p $DIRECTORY
		else
			rm -rf $DIRECTORY
			mkdir -p $DIRECTORY
			mkdir "$DIRECTORY/nodes"
			mkdir "$DIRECTORY/pods"
			
	fi
	echo "Scanning begun."
	#date
	echo $(date) > "$DIRECTORY/date.txt"
	#important versions
	echo "Versions" > "$DIRECTORY/get-versions.txt"
	echo "AWS VPC CNI:" >> "$DIRECTORY/get-versions.txt"
	kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2 >> "$DIRECTORY/get-versions.txt"
	echo "AWS EBS :" >> "$DIRECTORY/get-versions.txt"
	echo "AWS EFS :" >> "$DIRECTORY/get-versions.txt"
	echo "AWS LB :" >> "$DIRECTORY/get-versions.txt"
	#namespace
	kubectl get ns > "$DIRECTORY/get-namespace.txt"
	#nodes
	kubectl get nodes > "$DIRECTORY/get-nodes.txt"
	echo -ne "Scanning all nodes ."
	for i in $(grep -v STATUS "$DIRECTORY/get-nodes.txt" | awk '{print $1}') ; do
		kubectl describe node $i > "$DIRECTORY/nodes/describe-$i.txt"
		echo -n "."
	done
	echo -ne ".|\n"	
		

	#pods
	kubectl get pods -A > "$DIRECTORY/get-pods.txt"
	echo -ne "Scanning unhealthy pods."
	for i in $(grep -v STATUS "$DIRECTORY/get-pods.txt" | grep -v " Running " | awk '{print $1, $2}' | tr ' ' '+')  ; do
		loop_ns="$(echo $i | cut -d '+' -f 1)"
		loop_pod="$(echo $i | cut -d '+' -f 2)"
		kubectl describe pod "$loop_pod" -n "$loop_ns" > "/tmp/k-whatsup-dir/pods/describe_$loop_ns_$loop_pod.txt"
		kubectl get pod "$loop_pod" -n "$loop_ns" -o yaml > "/tmp/k-whatsup-dir/pods/get_yaml_$loop_ns_$loop_pod.txt"
		echo -n "."
	done
	echo -ne ".|\n"
	
	#echo -n "."	
	echo scan ran
}

analyze_function () {
	#nodes
	not_ready_nodes="$(grep -v STATUS "$DIRECTORY/get-nodes.txt" | grep -v " Ready " | wc -l)"
	ready_nodes="$(grep -v STATUS "$DIRECTORY/get-nodes.txt" | grep " Ready " | wc -l)"
	echo -e "\nnodes status:\nNot ready nodes: $not_ready_nodes \nReady nodes: $ready_nodes"
	for i in $(grep -v STATUS "$DIRECTORY/get-nodes.txt" | grep -v " Ready " | cut -d ' ' -f 1) ; do
		echo "---"
		grep "Name:" "$DIRECTORY/nodes/describe-$i.txt"
		for p in LastHeartbeatTime MemoryPressure DiskPressure PIDPressure Ready; do grep $p K-whatsup-dir/nodes/describe-$i.txt ; done
		tac "$DIRECTORY/nodes/describe-$i.txt" | sed -e '/Events:/q' | tac
		echo "---"
	done
	
	#pods
	not_ready_pods="$(grep -v STATUS "$DIRECTORY/get-pods.txt" | grep -v " Running " | wc -l)"
	ready_pods="$(grep -v STATUS "$DIRECTORY/get-pods.txt" | grep " Running " | wc -l)"
	echo -e "\npod status:\nNot running pods: $not_ready_pods \nRunning pods: $ready_pods"
    for i in $(grep -v STATUS "$DIRECTORY/get-pods.txt" | awk '{print $1, $2, $3, $4}' | tr ' ' '+') ; do
      loop_ns="$(echo $i | cut -d '+' -f 1)"
      loop_pod="$(echo $i | cut -d '+' -f 2)"
      loop_readynumber="$(echo $i | cut -d '+' -f 3)"
      loop_status="$(echo $i | cut -d '+' -f 4)"
      if [[ $(expr $(echo $loop_readynumber | awk '{gsub(/.{1}/,"& ")}1')) != 1 ]]; then 
        loop_status="NotEntirelyRunning"
      fi
      if [[ $loop_status != "Running" ]]; then
    		echo "---"
    		grep -e "^Name:" "$DIRECTORY/pods/describe_$loop_ns_$loop_pod.txt"
    		kubectl top pod "$loop_pod" -n "$loop_ns"
			if [[ $loop_status == "NotEntirelyRunning" ]]; then
				echo "Number of ready pods no equial to desriced number $loop_readynumber"
			done
    		tac "$DIRECTORY/pods/describe_$loop_ns_$loop_pod.txt" | sed -e '/Events:/q' | tac
    		echo "---"
      fi
    done


	
	echo analyze ran
}



##
#Main code
#Sets inital converser function variables
# Check if yes all argument supplied to skip question loop
if [[ $* == *'-y'* ]]; then
  echo "Skipping questions, Running in yes mode"
  scan_function
  pause_function
  analyze_function
  pause_function
  #terminate after running
  exit 0
fi

# Run main questioning loop
me=$(whoami)
say_var="Welcome to New Box Helper\nScript running as user: $me\n"
ask_var="Proceed with a scan? (yes|no|quit)"
not_scanned="yes"


loop="runloop"
while [ $loop != "endloop" ]; do
        converse_function $say_var $ask_var
        lowecase_return_var=${return_var,,}
        say_var=""
		#if [ "$not_scanned" = "no" ]; then
		#	ask_var="Scan completed, Would you like to see the results (yes|no|quit)"
		#fi
        case $lowecase_return_var in
          y | yes)
                    clear
					if [ "$not_scanned" = "yes" ]; then
						scan_function
						not_scanned=no
						ask_var="Scan completed, Would you like to see the results (yes|no|quit)"
					else
						analyze_function
					fi
                ;;
          n | no)
                    clear
                ;;
          skip)
                    not_scanned=no
					ask_var="Scan completed, Would you like to see the results (yes|no|quit)"
                ;;
          exit | quit | q)
                        loop="endloop"
                ;;
          * )
                echo "Unknown Operator value supplied\ntype exit to end the application"
                echo  $return_var
                ;;
        esac
done
