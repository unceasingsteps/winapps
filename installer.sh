#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

MAKEDEMO=0
USEDEMO=0

. "${DIR}/install/inquirer.sh"

INSTALLED_EXES=()

function waUsage() {
	echo 'Usage:
  ./installer.sh --user    # Install everything in ${HOME}
  ./installer.sh --system  # Install everything in /usr'
	exit
}

function waNoSudo() {
	echo 'You are attempting to switch from a --system install to a --user install.
Please run "./installer.sh --system --uninstall" first.'
	exit
}

function waInstall() {
	${SUDO} mkdir -p "${SYS_PATH}/apps"
	. "${DIR}/bin/linapps" install
}

function waFindInstalled() {
	echo -n "  Checking for installed apps in RDP machine (this may take a while)..."
	if [ $USEDEMO != 1 ]; then
		rm -f ${HOME}/.local/share/linapps/installed.bat
		rm -f ${HOME}/.local/share/linapps/installed.tmp
		rm -f ${HOME}/.local/share/linapps/installed
		rm -f ${HOME}/.local/share/linapps/detected
		cp "${DIR}/install/ExtractPrograms.ps1" ${HOME}/.local/share/linapps/ExtractPrograms.ps1
		for F in $(ls "${DIR}/apps"); do
			. "${DIR}/apps/${F}/info"
			echo "IF EXIST \"${WIN_EXECUTABLE}\" ECHO ${F} >> \\\\tsclient\\home\\.local\\share\\linapps\\installed.tmp" >> ${HOME}/.local/share/linapps/installed.bat
		done;
		echo "powershell.exe -ExecutionPolicy Bypass -File \\\\tsclient\\home\\.local\\share\\linapps\\ExtractPrograms.ps1 > \\\\tsclient\home\\.local\\share\\linapps\\detected" >> ${HOME}/.local/share/linapps/installed.bat
		echo "RENAME \\\\tsclient\\home\\.local\\share\\linapps\\installed.tmp installed" >> ${HOME}/.local/share/linapps/installed.bat
		xfreerdp /d:"${RDP_DOMAIN}" /u:"${RDP_USER}" /p:"${RDP_PASS}" /v:${RDP_IP} +auto-reconnect +home-drive -wallpaper /span /wm-class:"RDPInstaller" /app:"C:\Windows\System32\cmd.exe" /app-icon:"${DIR}/../icons/windows.svg" /app-cmd:"/C \\\\tsclient\\home\\.local\\share\\linapps\\installed.bat" 1> /dev/null 2>&1 &
		COUNT=0
		while [ ! -f "${HOME}/.local/share/linapps/installed" ]; do
			sleep 5
			COUNT=$((COUNT + 1))
			if (( COUNT == 15 )); then
				echo " Finished."
				echo ""
				echo "The RDP connection failed to connect or run. Please confirm FreeRDP can connect with:"
				echo "  bin/linapps check"
				echo ""
				echo "If it cannot connect, this is most likely due to:"
				echo "  - You need to accept the security cert the first time you connect (with 'check')"
				echo "  - Not enabling RDP in the Linux VM"
				echo "  - Not being able to connect to the IP of the VM"
				echo "  - Incorrect user credentials in linapps.conf"
				echo "  - Not merging install/RDPApps.reg into the VM"
				exit
			fi
		done
		if [ $MAKEDEMO = 1 ]; then
			rm -rf /tmp/linapps_demo
			cp -a ${HOME}/.local/share/linapps /tmp/linapps_demo
			exit
		fi
	else
		rm -rf ${HOME}/.local/share/linapps
		cp -a /tmp/linapps_demo ${HOME}/.local/share/linapps
		#sleep 3
	fi
	echo " Finished."
}

function waConfigureApp() {
		. "${SYS_PATH}/apps/${1}/info"
		echo -n "  Configuring ${NAME}..."
		if [ ${USEDEMO} != 1 ]; then
			${SUDO} rm -f "${APP_PATH}/${1}.desktop"
			echo "[Desktop Entry]
Name=${NAME}
Exec=${BIN_PATH}/linapps ${1} %F
Terminal=false
Type=Application
Icon=${SYS_PATH}/apps/${1}/icon.${2}
StartupWMClass=${FULL_NAME}
Comment=${FULL_NAME}
Categories=${CATEGORIES}
MimeType=${MIME_TYPES}
" |${SUDO} tee "${APP_PATH}/${1}.desktop" > /dev/null
			${SUDO} rm -f "${BIN_PATH}/${1}"
			echo "#!/usr/bin/env bash
${BIN_PATH}/linapps ${1} $@
" |${SUDO} tee "${BIN_PATH}/${1}" > /dev/null
			${SUDO} chmod a+x "${BIN_PATH}/${1}"
		fi
		echo " Finished."
}

function waConfigureApps() {
	APPS=()
	for F in $(cat "${HOME}/.local/share/linapps/installed" |sed 's/\r/\n/g'); do
		. "${DIR}/apps/${F}/info"
		APPS+=("${FULL_NAME} (${F})")
		INSTALLED_EXES+=("$(echo "${WIN_EXECUTABLE##*\\}" |tr '[:upper:]' '[:lower:]')")
	done
	IFS=$'\n' APPS=($(sort <<<"${APPS[*]}"))
	unset IFS
	OPTIONS=("Set up all detected pre-configured applications" "Select which pre-configured applications to set up" "Do not set up any pre-configured applications")
	menuFromArr APP_INSTALL "How would you like to handle linapps pre-configured applications?" "${OPTIONS[@]}"
	if [ "${APP_INSTALL}" = "Select which pre-configured applications to set up" ]; then
		checkbox_input "Which pre-configured apps would you like to set up?" APPS SELECTED_APPS
		echo "" > "${HOME}/.local/share/linapps/installed"
		for F in "${SELECTED_APPS[@]}"; do
			APP="${F##*(}"
			APP="${APP%%)}"
			echo "${APP}" >> "${HOME}/.local/share/linapps/installed"
		done
	fi	
	${SUDO} cp "${DIR}/bin/linapps" "${BIN_PATH}/linapps"
	COUNT=0
	if [ "${APP_INSTALL}" != "Do not set up any pre-configured applications" ]; then
		for F in $(cat "${HOME}/.local/share/linapps/installed" |sed 's/\r/\n/g'); do
			COUNT=$((COUNT + 1))
			${SUDO} cp -r "apps/${F}" "${SYS_PATH}/apps"
			waConfigureApp "${F}" svg
		done
	fi
	rm -f "${HOME}/.local/share/linapps/installed"
	rm -f "${HOME}/.local/share/linapps/installed.bat"
	if (( $COUNT == 0 )); then
		echo "  No configured applications."
	fi
}


function waConfigureWindows() {
	echo -n "  Configuring Windows..."
	if [ ${USEDEMO} != 1 ]; then
		${SUDO} rm -f "${APP_PATH}/windows.desktop"
		${SUDO} mkdir -p "${SYS_PATH}/icons"
		${SUDO} cp "${DIR}/icons/windows.svg" "${SYS_PATH}/icons/windows.svg"
		echo "[Desktop Entry]
Name=Windows
Exec=${BIN_PATH}/linapps windows %F
Terminal=false
Type=Application
Icon=${SYS_PATH}/icons/windows.svg
StartupWMClass=Micorosoft Windows
Comment=Micorosoft Windows
Categories=Windows
" |${SUDO} tee "${APP_PATH}/windows.desktop" > /dev/null
		${SUDO} rm -f "${BIN_PATH}/windows"
		echo "#!/usr/bin/env bash
${BIN_PATH}/linapps windows
" |${SUDO} tee "/${BIN_PATH}/windows" > /dev/null
		${SUDO} chmod a+x "${BIN_PATH}/windows"
	fi
	echo " Finished."
}

function waUninstallUser() {
	rm -f "${HOME}/.local/bin/linapps"
	rm -rf "${HOME}/.local/share/linapps"
	for F in $(grep -l -d skip "bin/linapps" "${HOME}/.local/share/applications/"*); do
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
	for F in $(grep -l -d skip "bin/linapps" "${HOME}/.local/bin/"*); do
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
}

function waUninstallSystem() {
	${SUDO} rm -f "/usr/local/bin/linapps"
	${SUDO} rm -rf "/usr/local/share/linapps"
	for F in $(grep -l -d skip "bin/linapps" "/usr/share/applications/"*); do
		if [ -z "${SUDO}" ]; then
			waNoSudo
		fi
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
	for F in $(grep -l -d skip "bin/linapps" "/usr/local/bin/"*); do
		if [ -z "${SUDO}" ]; then
			waNoSudo
		fi
		echo -n "  Removing ${F}..."
		${SUDO} rm ${F}
		echo " Finished."
	done
}

if [ -z "${1}" ]; then
	OPTIONS=(User System)
	menuFromArr INSTALL_TYPE "Would you like to install for the current user or the whole system?" "${OPTIONS[@]}"
elif [ "${1}" = '--user' ]; then
	INSTALL_TYPE='User'
elif [ "${1}" = '--system' ]; then
	INSTALL_TYPE='System'
else
	waUsage
fi

if [ "${INSTALL_TYPE}" = 'User' ]; then
	SUDO=""
	BIN_PATH="${HOME}/.local/bin"
	APP_PATH="${HOME}/.local/share/applications"
	SYS_PATH="${HOME}/.local/share/linapps"
	if [ -n "${2}" ]; then
		if [ "${2}" = '--uninstall' ]; then
			# Uninstall
			echo "Uninstalling..."
			waUninstallUser
			exit
		else
			usage
		fi
	fi
elif [ "${INSTALL_TYPE}" = 'System' ]; then
	SUDO="sudo"
	sudo ls > /dev/null
	BIN_PATH="/usr/local/bin"
	APP_PATH="/usr/share/applications"
	SYS_PATH="/usr/local/share/linapps"
	if [ -n "${2}" ]; then
		if [ "${2}" = '--uninstall' ]; then
			# Uninstall
			echo "Uninstalling..."
			waUninstallSystem
			exit
		else
			usage
		fi
	fi
fi

echo "Removing any old configurations..."
waUninstallUser
waUninstallSystem

echo "Installing..."

# Inititialize
waInstall

# Check for installed apps
waFindInstalled

# Install windows
waConfigureWindows

# Configure apps
waConfigureApps

echo "Installation complete."
