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
		'vm-vif-list' 'Lists the VIFs from the specified VMs' \
		"vm-cd-list" "List CDs" \
	)

	

	OPTION=$(whiptail --title "Menu example" --menu "$VM_NAME ($VM_STATUS)" $LINES $COLUMNS $(( $LINES - 8 )) \
		"back" "Return to the main menu." \
		"${POSSIBLE_PARAMS[@]}" \
		"vm-start" "Start VM" \
		"vm-suspend" "Suspend VM" \
		"diagnostic-vm-status" "Query the hosts on which the VM can boot, check the sharing/locking status of all VBDs." \
		"vm-reboot" "Reboots the VM" \
		"vm-reset-powerstate" "Pull plug and restart VM" \
		"vm-pause" "Pause VM" \
		"vm-unpause" "Unpause VM" \
		"vm-resume" "Resume VM" \
		"vm-shutdown" "Shut down VM" \
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
	elif [[ "$OPTION" == "vm-reset-powerstate" ]]; then
		if (whiptail --title "Hard-reset VM?" --yesno "Are you sure? This may cause data loss." $LINES $COLUMNS); then
			set +e
			RES=$(xe $OPTION uuid=$1 --force 2>&1)
			EC=$?
			set -e

			FULL_STR=""

			if [[ "$EC" == "0" ]]; then
				FULL_STR="$RES";
			else
				FULL_STR="$RES\n\nExit-Code: $EC";
			fi


			whiptail --title "Example Dialog" --msgbox "$FULL_STR" $LINES $COLUMNS
		else
			echo "User selected No, exit status was $?."
		fi

	else
		set +e
		RES=$(xe $OPTION uuid=$1 2>&1)
		EC=$?
		set -e

		whiptail --title "Example Dialog" --msgbox "$RES\n\nExit-Code: $EC" $LINES $COLUMNS
	fi
	
	single_vm $VM_UUID
}

function main {
	VMS=$(xe vm-list | perl -lne '$\ = ""; my $str = ""; while (<>) { $str .= $_; } my @splitted = split /\R\R+/, $str; my %vms = (); foreach my $vm (@splitted) { my ($uuid, $name, $status) = split /\R/, $vm; $uuid =~ s#^.*?:\s*##g; $name =~ s#^.*?:\s*##g; $status =~ s#^.*?:\s*##g; $vms{$uuid} = "$name ($status)"; chomp $vms{$uuid}; } foreach (keys(%vms)) { print qq#"$_" "$vms{$_}" #; }')

	CHOSEN_OPTION=$(eval "whiptail --title 'Menu example' --menu 'Choose an option' $LINES $COLUMNS $(( $LINES - 8 )) \
		'cd-list' 'List CDs and ISOs' \
		'network-list' 'List networks' \
		'sr-list' 'List SRs' \
		$VMS 'q' 'exit' 3>&1 1>&2 2>&3")

	if [[ "$CHOSEN_OPTION" == "q" ]]; then
		exit 0
	elif [[ "$CHOSEN_OPTION" == "cd-list" ]]; then
		xe cd-list
	elif [[ "$CHOSEN_OPTION" == "network-list" ]]; then
		xe network-list
	elif [[ "$CHOSEN_OPTION" == "sr-list" ]]; then
		xe sr-list
	else
		single_vm "$CHOSEN_OPTION"
	fi
}


main
