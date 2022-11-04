#!/bin/bash

function echoerr() {
	echo "$@" 1>&2
}

function red_text {
        echoerr -e "\e[31m$1\e[0m"
}

set -e
set -o pipefail
set -u

function calltracer () {
        echo 'Last file/last line:'
        caller
}

trap 'calltracer' ERR

function help () {
        echo "Possible options:"
        echo "  --help                                             this help"
        echo "  --debug                                            Enables debug mode (set -x)"
        exit $1
}
for i in $@; do
        case $i in
                -h|--help)
                        help 0
                        ;;
                --debug)
                        set -x
                        ;;
                *)
                        red_text "Unknown parameter $i" >&2
                        help 1
                        ;;
        esac
done

if ! command -v whiptail >/dev/null 2>/dev/null; then
	red_text "whiptail is not installed. Run sudo apt-get install whiptail to install it"
	exit 1
fi

function run_command_whiptail {
	TITLE=$1
	COMMAND=$2
	set +e
	RES=$(eval $COMMAND 2>&1)
	EC=$?
	set -e


	FULL_STR=""

	if [[ "$EC" == "0" ]]; then
		FULL_STR="$RES";
	else
		FULL_STR="$RES\n\nExit-Code: $EC";
	fi


	whiptail --title "$TITLE" --msgbox "$FULL_STR" $LINES $COLUMNS
}

function get_status_for_vm {
	xe vm-list | grep -A2 "$1" | tail -n1 | sed -e 's/.*: //'
}

function get_vm_name_by_uuid {
	xe vm-list | grep -A1 "$1" | tail -n1  | sed -e 's/.*:\s*//'
}

function single_vm {
	VM_UUID=$1

	VM_STATUS=$(get_status_for_vm $VM_UUID)
	VM_NAME=$(get_vm_name_by_uuid $VM_UUID)

	echo $VM_UUID

	POSSIBLE_PARAMS=(
		"diagnostic-vm-status" "Query the hosts on which the VM can boot, check the sharing/locking status of all VBDs." \
		'vm-vif-list' 'Lists the VIFs from the specified VMs' \
		"vm-cd-list" "List CDs" \
		"vm-reset-powerstate" "Pull plug and restart VM" \
		"vm-snapshot" "Create snapshop"
		"vm-shutdown" "Shut down VM" \
		"vm-reboot" "Reboots the VM" \
		"snapshot-list" "Lists all snapshots for this VM" \
		"vm-cd-eject" "Eject currently mounted CD"
	)

	if [[ "$VM_STATUS" != "running" ]]; then
		if [[ "$VM_STATUS" != "paused" ]]; then
			POSSIBLE_PARAMS+=(
				"vm-start" "Start VM"
			)
		fi
	fi

	if [[ "$VM_STATUS" == "suspended" ]]; then
		POSSIBLE_PARAMS+=(
			"vm-resume" "Resume VM"
		)
	else
		if [[ "$VM_STATUS" == "running" ]]; then
			POSSIBLE_PARAMS+=(
				"vm-suspend" "Suspend VM"
			)
		fi
	fi

	if [[ "$VM_STATUS" == "paused" ]]; then
		POSSIBLE_PARAMS+=(
			"vm-unpause" "Unpause VM"
		)
	else
		POSSIBLE_PARAMS+=(
			"vm-pause" "Pause VM"
		)
	fi
	

	OPTION=$(whiptail --title "$VM_NAME ($VM_STATUS)" --menu "$VM_NAME ($VM_STATUS)" $LINES $COLUMNS $(( $LINES - 8 )) \
		"back" "Return to the main menu." \
		"${POSSIBLE_PARAMS[@]}" \
		'q' 'exit' \
		3>&1 1>&2 2>&3
	)

	echo $OPTION


	if [[ "$OPTION" == "back" ]]; then
		echo "Going back...";
		main
		exit 0
	elif [[ "$OPTION" == "q" ]]; then
		exit 0
	elif [[ "$OPTION" == "vm-snapshot" ]]; then
		SNAPSHOP_NAME=$(whiptail --inputbox "Name of this snapshot" 8 39 "Snapshot ($(date))" --title "Snapshot name" 3>&1 1>&2 2>&3)
		SNAPSHOP_NAME=$(echo "$SNAPSHOP_NAME" | sed -e 's/"//')

		exitstatus=$?
		if [ $exitstatus = 0 ]; then
			run_command_whiptail "Snapshot" "xe vm-snapshot vm=$VM_UUID new-name-label=\"$SNAPSHOP_NAME\""
		fi
	elif [[ "$OPTION" == "vm-cd-add" ]]; then
		AVAILABLE_CDS=$(xe cd-list | grep "name-label" | sed -e 's#.*: ##' | sed -e 's#\(.*\)#"\1" "\1" #' | tr -d '\n')
		CD_NAME=$(eval "whiptail --title 'Menu example' --menu 'Choose an option' $LINES $COLUMNS $(( $LINES - 8 )) 'back' 'Return to the main menu.' $AVAILABLE_CDS")

		exitstatus=$?
		if [ $exitstatus = 0 ]; then
			xe vm-cd-add cd-name="$CD_NAME" device=0 uuid=$VM_UUID
		else
			echo "User selected Cancel."
		fi
	elif [[ "$OPTION" == "vm-reset-powerstate" ]]; then
		if (whiptail --title "Hard-reset VM?" --yesno "Are you sure? This may cause data loss." $LINES $COLUMNS); then
			run_command_whiptail "$OPTION" "xe $OPTION uuid=$VM_UUID --force"
		else
			echo "User selected No, exit status was $?."
		fi

	else
		run_command_whiptail "$OPTION" "xe $OPTION uuid=$VM_UUID"
	fi
	
	single_vm $VM_UUID
}

function main {
	VMS=$(xe vm-list | perl -lne '$\ = ""; my $str = ""; while (<>) { $str .= $_; } my @splitted = split /\R\R+/, $str; my %vms = (); foreach my $vm (@splitted) { my ($uuid, $name, $status) = split /\R/, $vm; $uuid =~ s#^.*?:\s*##g; $name =~ s#^.*?:\s*##g; $status =~ s#^.*?:\s*##g; $vms{$uuid} = "$name ($status)"; chomp $vms{$uuid}; } foreach (keys(%vms)) { print qq#"$_" "$vms{$_}" #; }')

	CHOSEN_OPTION=$(eval "whiptail --title 'XCP GUI' --menu 'Choose an option' $LINES $COLUMNS $(( $LINES - 8 )) \
		'cd-list' 'List CDs and ISOs' \
		'network-list' 'List networks' \
		'sr-list' 'List SRs' \
		$VMS 'q' 'exit' 3>&1 1>&2 2>&3")

	if [[ "$CHOSEN_OPTION" == "q" ]]; then
		exit 0
	elif [[ "$CHOSEN_OPTION" == "cd-list" ]]; then
		run_command_whiptail "cd-list" "xe cd-list"
		main
	elif [[ "$CHOSEN_OPTION" == "network-list" ]]; then
		run_command_whiptail "network-list" "xe network-list"
		main
	elif [[ "$CHOSEN_OPTION" == "sr-list" ]]; then
		run_command_whiptail "sr-list" "xe sr-list"
		main
	else
		single_vm "$CHOSEN_OPTION"
	fi
}


main
