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

function single_vm {
	VM_UUID=$1

	echo $VM_UUID
}

function main {
	VMS=$(xe vm-list | perl -lne '$\ = ""; my $str = ""; while (<>) { $str .= $_; } my @splitted = split /\R\R+/, $str; my %vms = (); foreach my $vm (@splitted) { my ($uuid, $name, $status) = split /\R/, $vm; $uuid =~ s#^.*?:\s*##g; $name =~ s#^.*?:\s*##g; $status =~ s#^.*?:\s*##g; $vms{$uuid} = "$name ($status)"; chomp $vms{$uuid}; } foreach (keys(%vms)) { print qq#$_ $vms{$_} #; }')

	CHOSEN_OPTION=$(whiptail --title "Menu example" --menu "Choose an option" 25 78 16 "q" "exit" $VMS 3>&1 1>&2 2>&3)

	if [[ "$CHOSEN_OPTION" == "q" ]]; then
		exit 0
	else
		single_vm "$CHOSEN_OPTION"
	fi
}


main
