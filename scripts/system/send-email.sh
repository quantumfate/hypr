#!/usr/bin/env bash
# Author: Leon Connor Holm

# This script is inteded to be used to 
# react to email notifications on click

personal_mailto() {

	echo ""
}

uni_mailto() {

	echo ""
}

alt_mailto() {
		
	echo ""
}
if [[ "$1" == "--personal" ]]; then
	personal_mailto
elif [[ "$1" == "--uni" ]]; then
	uni_mailto
elif [[ "$1" == "--alt" ]]; then
	alt_mailto
else
	echo -e "Available Options : --personal, --uni, --alt"
fi