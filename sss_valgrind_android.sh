#!/usr/bin/env bash

install_valgrind() {
	adb root
	if [ $? -ne 0 ]; then
		echo "FAIL! Ensure adb is installed and device is pluged!"
		exit 1
	fi
	DEVICE_CPU_INFO=`adb shell cat /proc/cpuinfo`
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
	
	rm -r ./Inst
	echo "unzip valgrind package..."
	case $DEVICE_CPU_TYPE in
		"ARMv7")
			unzip -nq valgrind-arm.zip
			;;
		"ARM64")
			unzip -nq valgrind-arm64.zip
			;;
	esac
	if [[ $? -ne 0 ]]; then
		rm -r ./Inst
		echo "FAIL! Can not unzip valgrind package."
		exit 1
	fi

	adb push ./Inst/data/local/Inst /data/local
	if [[ $? -ne 0 ]]; then
		echo "FAIL! Can not push valgrind to device."
		echo "You can try to move the ./Inst/data/local/Inst to /data/local manually."
		exit 1
	else
		rm -r ./Inst
	fi

	echo "DONE, install valgrind success!"
	exit 0
}

push_sh_to_device() {
	PACKAGE_NAME="com.example.sunda.ctest"
	VALGRIND_PARAMS="-v --sigill-diagnostics=no --log-file=/sdcard/valgrind.%p.log --leak-check=full --show-reachable=yes"
	if [[ -z $PACKAGE_NAME ]]; then
		echo "FAIL! The app package name is not set"
		exit 1
	fi
	START_CALGRIND_SH="#!/system/bin/sh \n
PACKAGE=\"${PACKAGE_NAME}\" \n
VGPARAMS='${VALGRIND_PARAMS}' \n
export TMPDIR=/data/data/\$PACKAGE \n
exec /data/local/Inst/bin/valgrind \$VGPARAMS \$* "
	echo -e $START_CALGRIND_SH > start_valgrind.sh

	adb push start_valgrind.sh /data/local/
	if [ $? -ne 0 ]; then
		rm ./start_valgrind.sh
		echo "FAIL! Ensure adb is installed and device is pluged!"
		exit 1
	fi
	rm ./start_valgrind.sh

	adb shell chmod 777 /data/local/start_valgrind.sh
	if [ $? -ne 0 ]; then
		echo "FAIL! Can not chmod 777 /data/local/start_valgrind.sh"
		exit 1
	fi
}

replace_lib() {
	SYMBOLIZED_LIB_PATH="/Users/sunda/CTest/app/build/intermediates/cmake/debug/obj/armeabi-v7a/"
	ALL_SYMBOLIZED_LIB=`ls "$SYMBOLIZED_LIB_PATH"`
	if [[ -z $ALL_SYMBOLIZED_LIB ]]; then
		echo "FAIL! There is not symbolized lib."
		exit 1
	fi
	echo "$ALL_SYMBOLIZED_LIB" | while read LIB_PATH; do
		adb push "$SYMBOLIZED_LIB_PATH$LIB_PATH" "/data/data/$PACKAGE_NAME/lib"
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
	rm ./.temp
	GETPROP=`adb shell getprop wrap.$PACKAGE_NAME | tr -d "\r"`
	if [[ $LOG_WRAPPER != $GETPROP ]]; then
		echo -e "FAIL! Can not set device prop. Ensure the device can execute \"adb shell setprop\"."
		exit 1
	fi

	echo -e "\"$PACKAGE_NAME\" will relaunch..."
	adb shell am force-stop $PACKAGE_NAME
	adb shell am start -a android.intent.action.MAIN -n $PACKAGE_NAME/.CTestActivity
	clear
	echo "Launching app..."
	echo "This may take as long as a song. Have a cup of coffee ☕️ "
}

wait_terminate_app() {
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
			rm ./.temp
			break
		fi
	done
}

pull_logs() {
	echo "Getting back logs..."
	ALL_LOGS=`adb shell ls /sdcard/ | grep "valgrind.*.log" | tr -d "\r"`
	if [[ ${#ALL_LOGS} -lt 13 ]]; then
		echo "FAIL! There is no log file."
		exit 1
	fi

	echo "$ALL_LOGS" | while read LOG_PATH; do
		LOG_PATH="/sdcard/$LOG_PATH"
		adb pull "$LOG_PATH"
		if [[ $? -ne 0 ]]; then
			echo -e "FAIL! Can not pull log files: \"$LOG_PATH\""
			exit 1
		fi
	done

	adb shell rm /sdcard/valgrind.*.log
	echo "DONE. Please check the log(s) in `pwd`"
}

#install_valgrind
#获取所有包名
#adb shell pm list packages

push_sh_to_device
#replace_lib
launch_valgrind

wait_terminate_app
pull_logs

exit 0
