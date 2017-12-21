#!/usr/bin/env bash

install_valgrind() {
	DEVICE_CPU_INFO=`adb shell cat /proc/cpuinfo`
	if [ $? -ne 0 ]; then
		echo "FAIL! Ensure adb is installed and device is pluged!"
		exit 1
	fi
	DEVICE_CPU_INDEX=`echo $DEVICE_CPU_INFO | awk -F"AArch64" '{print $1}' | wc -c`
	if [ $DEVICE_CPU_INDEX -ge ${#DEVICE_CPU_INFO} ]; then
		DEVICE_CPU_INDEX=`echo $DEVICE_CPU_INFO | awk -F"ARMv7" '{print $1}' | wc -c`
		if [ $DEVICE_CPU_INDEX -ge ${#DEVICE_CPU_INFO} ]; then
			echo "FAIL! Can not support the device cpu arch now."
			echo "You can try to install valgrind manually, see http://www.valgrind.org"
			exit 1
		else
			DEVICE_CPU_TYPE="ARMv7"
		fi
	else
		DEVICE_CPU_TYPE="ARM64"
	fi
	echo "DEVICE_CPU_TYPE: $DEVICE_CPU_TYPE"
	
	rm -rf ./Inst
	echo "Unzip valgrind package..."
	case $DEVICE_CPU_TYPE in
		"ARMv7")
			unzip -nq valgrind-arm.zip
			;;
		"ARM64")
			unzip -nq valgrind-arm64.zip
			;;
	esac
	if [[ $? -ne 0 ]]; then
		rm -rf ./Inst
		echo "FAIL! Can not unzip valgrind package."
		exit 1
	fi

	adb push ./Inst/data/local/Inst /data/local
	if [[ $? -ne 0 ]]; then
		echo "FAIL! Can not push valgrind to device."
		echo "You can try to move the `pwd`/Inst/data/local/Inst to /data/local manually."
		exit 1
	else
		rm -rf ./Inst
	fi

	echo "DONE, install valgrind success!"
}

input_parameter() {
	if [[ ! -e .sss_last_input ]]; then
		PACKAGE_NAME="com.sunshushu.test"
		APP_MAIN_ACTIVITY="MainActivity"
		SYMBOLIZED_LIB_PATH="`pwd`/valgrind_test/app/build/intermediates/cmake/debug/obj/armeabi-v7a"
		echo -e "${PACKAGE_NAME}\n${APP_MAIN_ACTIVITY}\n${SYMBOLIZED_LIB_PATH}" > .sss_last_input
	fi

	echo "Type valgrind parameter, nullable."
	echo -e " (You don't need to set \"--log-file\". By default, the log will be written to file(s) and got back automatically.)"
	read VALGRIND_PARAMS
	echo "$VALGRIND_PARAMS" | grep -q "log-file"
	if [[ $? -ne 0 ]]; then
		VALGRIND_PARAMS="$VALGRIND_PARAMS --log-file=/sdcard/valgrind.%p.log"
	fi

	PACKAGE_NAME=`sed -n "1p" .sss_last_input`
	echo "Type the package name of your android app. [$PACKAGE_NAME]"
	while read PACKAGE_NAME_INPUT; do
		if [[ -n $PACKAGE_NAME_INPUT ]]; then
			PACKAGE_NAME="$PACKAGE_NAME_INPUT"
		else
			echo "$PACKAGE_NAME"
		fi
		if [[ ${#PACKAGE_NAME} -gt 26 ]]; then
			echo "FAIL! The length of package name can not be greater than 26."
			exit 1
		fi
		ALL_PACKAGES=`adb shell pm list packages`
		if [[ $? -ne 0 ]]; then
			echo "Ensure adb is installed and device is pluged!"
			continue
		fi
		echo "$ALL_PACKAGES" | grep -q "package:${PACKAGE_NAME}"
		if [[ $? -ne 0 ]]; then
			echo "There is no specified app on the device, try again."
			continue
		else
			break
		fi
	done

	APP_MAIN_ACTIVITY=`sed -n "2p" .sss_last_input`
	echo "Type the main avtivity name of the app. [$APP_MAIN_ACTIVITY]"
	read APP_MAIN_ACTIVITY_INPUT
	if [[ -n $APP_MAIN_ACTIVITY_INPUT ]]; then
		APP_MAIN_ACTIVITY="$APP_MAIN_ACTIVITY_INPUT"
	else
		echo "$APP_MAIN_ACTIVITY"
	fi

	SYMBOLIZED_LIB_PATH=`sed -n "3p" .sss_last_input`
	echo "Type the directory of lib with symbol table. [$SYMBOLIZED_LIB_PATH]"
	while read SYMBOLIZED_LIB_PATH_INPUT; do
		if [[ -n $SYMBOLIZED_LIB_PATH_INPUT ]]; then
			SYMBOLIZED_LIB_PATH="$SYMBOLIZED_LIB_PATH_INPUT"
		else
			echo "$SYMBOLIZED_LIB_PATH"
		fi
		ALL_SYMBOLIZED_LIB=`ls "$SYMBOLIZED_LIB_PATH" | grep -e ".so" -e ".a"`
		if [[ -z $ALL_SYMBOLIZED_LIB ]]; then
			echo "There is not lib file, try again."
			continue
		else
			break
		fi
	done

	echo -e "${PACKAGE_NAME}\n${APP_MAIN_ACTIVITY}\n${SYMBOLIZED_LIB_PATH}" > .sss_last_input
}

push_sh_to_device() {
	START_CALGRIND_SH="#!/system/bin/sh \n
PACKAGE=\"${PACKAGE_NAME}\" \n
VGPARAMS='${VALGRIND_PARAMS}' \n
export TMPDIR=/data/data/\$PACKAGE \n
exec /data/local/Inst/bin/valgrind \$VGPARAMS \$* "
	echo -e $START_CALGRIND_SH > start_valgrind.sh

	adb push start_valgrind.sh /data/local/
	if [ $? -ne 0 ]; then
		rm -f ./start_valgrind.sh
		echo "FAIL! Ensure adb is installed and device is pluged!"
		exit 1
	fi
	rm -f ./start_valgrind.sh

	adb shell chmod 777 /data/local/start_valgrind.sh
	if [ $? -ne 0 ]; then
		echo "FAIL! Can not execute: adb shell chmod 777 /data/local/start_valgrind.sh"
		exit 1
	fi
}

replace_lib() {
	echo "Replace app lib..."
	echo "$ALL_SYMBOLIZED_LIB" | while read LIB_PATH; do
		adb push "$SYMBOLIZED_LIB_PATH/$LIB_PATH" "/data/data/$PACKAGE_NAME/lib"
		if [[ $? -ne 0 ]]; then
			echo "FAIL! Can not push symbolized lib to /data/data/$PACKAGE_NAME/lib"
			exit 1
		fi
	done
}

launch_valgrind() {
	LOG_WRAPPER="logwrapper /data/local/start_valgrind.sh"
	adb root
	echo -e "setprop wrap.$PACKAGE_NAME \"$LOG_WRAPPER\"\n exit" > .temp
	adb shell < .temp
	rm -f ./.temp
	GETPROP=`adb shell getprop wrap.$PACKAGE_NAME | tr -d "\r"`
	if [[ $LOG_WRAPPER != $GETPROP ]]; then
		echo -e "FAIL! Can not set device system property. Ensure the device can execute \"adb shell setprop\"."
		exit 1
	fi

	echo -e "\"$PACKAGE_NAME\" will relaunch..."
	adb shell am force-stop $PACKAGE_NAME
	adb shell am start -a android.intent.action.MAIN -n "$PACKAGE_NAME/.$APP_MAIN_ACTIVITY"
	clear
	echo "Launching app..."
	echo "This may take as long as a song. Have a cup of coffee ☕️ "
}

wait_and_terminate_app() {
	while true; do
		echo -e " (Input \"done\" to terminate app and get back logs.)"
		read NEXT_ACTION
		if [[ $NEXT_ACTION != "done" ]]; then
			continue
		fi
		clear
		echo "Terminating app..."
		adb shell am force-stop $PACKAGE_NAME
		if [[ $? -ne 0 ]]; then
			echo "Please plugin your device."
		else
			echo -e "setprop wrap.$PACKAGE_NAME \"\"\n exit" > .temp
			adb shell < .temp
			rm -f ./.temp
			break
		fi
	done
}

pull_logs() {
	echo "Getting back logs..."
	ALL_LOGS=`adb shell ls /sdcard/ | grep "valgrind.*.log" | tr -d "\r"`
	if [[ ${#ALL_LOGS} -lt 13 ]]; then
		echo "DONE, There is no log file."
		exit 0
	fi

	echo "$ALL_LOGS" | while read LOG_PATH; do
		LOG_PATH="/sdcard/$LOG_PATH"
		adb pull "$LOG_PATH"
		if [[ $? -ne 0 ]]; then
			echo -e "FAIL! Can not pull log files: \"$LOG_PATH\""
			exit 1
		fi
	done

	adb shell rm -f /sdcard/valgrind.*.log
	echo "DONE. Check the log(s) in `pwd`"
}

if [[ $# -eq 0 ]]; then
	input_parameter
else
	if [[ $1 = "-i" ]]; then
		install_valgrind
		exit 0
	fi
	if [[ $# -eq 4 ]]; then
		VALGRIND_PARAMS=$1
		PACKAGE_NAME=$2
		APP_MAIN_ACTIVITY=$3
		SYMBOLIZED_LIB_PATH=$4
	else
		echo "FAIL! Parameter error."
		echo "Perhaps you should try to execute this script without any arguments."
		echo "Or you could use it like this:"
		echo "sss_valgrind_android.sh \"valgrind_parameters\" \"com.example.test\" \"MainActivity\" \"/lib_with_symbol_table_path\""
		exit 1
	fi
fi

push_sh_to_device
replace_lib
launch_valgrind
wait_and_terminate_app
pull_logs

exit 0
