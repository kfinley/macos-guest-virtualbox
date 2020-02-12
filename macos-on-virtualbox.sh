#!/usr/local/bin/bash
# url: https://github.com/kfinley/macos-on-virtualbox
# version 0.1.1

# Based on original source...
# Semi-automatic installer of macOS on VirtualBox
# (c) myspaghetti, licensed under GPL2.0 or higher
# url: https://github.com/myspaghetti/macos-guest-virtualbox
# version 0.87.1

# Requirements: 40GB available storage on host
# Dependencies: bash >= 4.3, xxd, gzip, unzip, wget, dmg2img,
#               VirtualBox with Extension Pack >= 6.0

function set_variables() {
    # Customize the installation by setting these variables:
    macOS_release_name="Catalina"        # install "HighSierra" "Mojave" or "Catalina"
    vmname="macOS-$macOS_release_name" # name of the VirtualBox virtual machine
    storagesize=40000                  # VM disk image size in MB. Minimum 22000
    cpucount=3                         # VM CPU cores, minimum 2
    memorysize=8192                    # VM RAM in MB, minimum 2048
    gpuvram=128                        # VM video RAM in MB, minimum 34, maximum 128
    resolution="1280x800"              # VM display resolution

    # The following commented commands, when run on a genuine Mac,
    # may provide the values for NVRAM and other parameters required by iCloud,
    # iMessage, and other connected Apple applications.
    # Parameters taken from a genuine Mac may result in a "Call customer support"
    # message if they do not match the genuine Mac exactly.
    # Non-genuine yet genuine-like parameters usually work.

    # system_profiler SPHardwareDataType
    DmiSystemFamily="MacBook Pro"                        # Model Name
    DmiSystemProduct="MacBookPro11,2"                    # Model Identifier
    DmiSystemSerial="NO_DEVICE_SN"                       # Serial Number (system)
    DmiSystemUuid="CAFECAFE-CAFE-CAFE-CAFE-DECAFFDECAFF" # Hardware UUID
    DmiOEMVBoxVer="string:1"                             # Apple ROM Info
    DmiOEMVBoxRev="string:.23456"                        # Apple ROM Info
    DmiBIOSVersion="string:MBP7.89"                      # Boot ROM Version
    # ioreg -l | grep -m 1 board-id
    DmiBoardProduct="Mac-3CBD00234E554E41"
    # nvram 4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:MLB
    DmiBoardSerial="NO_LOGIC_BOARD_SN"
    MLB="${DmiBoardSerial}"
    # nvram 4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:ROM
    ROM='%aa*%bbg%cc%dd'
    # ioreg -l -p IODeviceTree | grep \"system-id
    SYSTEM_UUID="aabbccddeeff00112233445566778899"
    # csrutil status
    SYSTEM_INTEGRITY_PROTECTION='77' # '10' - enabled, '77' - disabled
}

# welcome message
function welcome() {
    printf '
                Semi-automatic installer of macOS on VirtualBox
-------------------------------------------------------------------------------

This script installs only open-source software and unmodified Apple binaries.

The script checks for dependencies and will prompt to install them if unmet.

For iCloud and iMessage connectivity, the script needs to be edited with genuine
or genuine-like Apple parameters. macOS will work without these parameters, but
Apple-connected apps will not.

The installation requires about '"${highlight_color}"'40GB'"${default_color}"' of available storage, 25GB for
temporary installation files and 15GB for the virtual machine'"'"'s dynamically
allocated storage disk image.

The script can be resumed, as described when running the following command:
'
    would_you_like_to_know_less
    printf '
'"${highlight_color}"'Press enter to review the script settings.'"${default_color}"
    clear_input_buffer_then_read

    # custom settings prompt
    printf '
vmname="'"${vmname}"'"                   # name of the VirtualBox virtual machine
macOS_release_name="'"${macOS_release_name}"'"      # install "HighSierra" "Mojave" or "Catalina"
storagesize='"${storagesize}"'                # VM disk image size in MB. minimum 22000
cpucount='"${cpucount}"'                       # VM CPU cores, minimum 2
memorysize='"${memorysize}"'                  # VM RAM in MB, minimum 2048
gpuvram='"${gpuvram}"'                      # VM video RAM in MB, minimum 34, maximum 128
resolution="'"${resolution}"'"            # VM display resolution

These values may be customized by editing them at the top of the script file.

'"${highlight_color}"'Press enter to continue, CTRL-C to exit.'"${default_color}"
    clear_input_buffer_then_read
}

# check dependencies

function check_bash_version() {
    if [ -z "${BASH_VERSION}" ]; then
        echo "Can't determine BASH_VERSION. Exiting."
        exit
    elif [ "${BASH_VERSION:0:1}" -lt 4 ]; then
        echo "Please run this script on Bash 4.3 or higher."
        if [ -n "$(sw_vers 2>/dev/null)" ]; then
            echo "macOS detected. Make sure the script is not running on"
            echo "the default /bin/bash which is version 3."
        fi
        exit
    elif [ "${BASH_VERSION:0:1}" -eq 4 -a "${BASH_VERSION:2:1}" -le 2 ]; then
        echo "Please run this script on Bash 4.3 or higher."
        exit
    fi
}

function check_gnu_coreutils_prefix() {
    if [ -n "$(gcsplit --help 2>/dev/null)" ]; then
        function csplit() {
            gcsplit "$@"
        }
        function tac() {
            gtac "$@"
        }
        function split() {
            gsplit "$@"
        }
        function base64() {
            gbase64 "$@"
        }
        function expr() {
            gexpr "$@"
        }
        function od() {
            god "$@"
        }
    fi
}

function check_dependencies() {

    # check if running on macOS and non-GNU coreutils
    if [ -n "$(sw_vers 2>/dev/null)" ]; then
        # Add Homebrew GNU coreutils to PATH if path exists
        homebrew_gnubin="/usr/local/opt/coreutils/libexec/gnubin"
        if [ -d "${homebrew_gnubin}" ]; then
            PATH="${homebrew_gnubin}:${PATH}"
        fi
        # if csplit isn't GNU variant, exit
        if [ -z "$(csplit --help 2>/dev/null)" ]; then
            echo ""
            printf 'macOS detected.\nPlease use a package manager such as '"${highlight_color}"'homebrew'"${default_color}"', '"${highlight_color}"'pkgsrc'"${default_color}"', '"${highlight_color}"'nix'"${default_color}"', or '"${highlight_color}"'MacPorts'"${default_color}"'.\n'
            echo "Please make sure the following packages are installed and that"
            echo "their path is in the PATH variable:"
            printf "${highlight_color}"'bash  coreutils  wget  unzip  dmg2img'"${default_color}"'\n'
            echo "Please make sure Bash and coreutils are the GNU variant."
            exit
        fi
    fi

    # check for xxd, gzip, unzip, coreutils, wget
    if [ -z "$(echo "xxd" | xxd -p 2>/dev/null)" \
        -o -z "$(gzip --help 2>/dev/null)" \
        -o -z "$(unzip -hh 2>/dev/null)" \
        -o -z "$(csplit --help 2>/dev/null)" \
        -o -z "$(wget --version 2>/dev/null)" ]; then
        echo "Please make sure the following packages are installed:"
        echo "coreutils    gzip    unzip    xxd    wget"
        echo "Please make sure the coreutils package is the GNU variant."
        exit
    fi

    # wget supports --show-progress from version 1.16
    if [[ "$(wget --version 2>/dev/null | head -n 1)" =~ 1\.1[6-9]|1\.2[0-9] ]]; then
        wgetargs="--quiet --continue --show-progress" # pretty
    else
        wgetargs="--continue" # ugly
    fi

    # VirtualBox in ${PATH}
    # Cygwin
    if [ -n "$(cygcheck -V 2>/dev/null)" ]; then
        if [ -n "$(cmd.exe /d /s /c call VBoxManage.exe -v 2>/dev/null)" ]; then
            function VBoxManage() {
                cmd.exe /d /s /c call VBoxManage.exe "$@"
            }
        else
            cmd_path_VBoxManage='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
            echo "Can't find VBoxManage in PATH variable,"
            echo "checking ${cmd_path_VBoxManage}"
            if [ -n "$(cmd.exe /d /s /c call "${cmd_path_VBoxManage}" -v 2>/dev/null)" ]; then
                function VBoxManage() {
                    cmd.exe /d /s /c call "${cmd_path_VBoxManage}" "$@"
                }
                echo "Found VBoxManage"
            else
                echo "Please make sure VirtualBox version 6.0 or higher is installed, and that"
                echo "the path to the VBoxManage.exe executable is in the PATH variable, or assign"
                echo "in the script the full path including the name of the executable to"
                printf 'the variable '"${highlight_color}"'cmd_path_VBoxManage'"${default_color}"
                exit
            fi
        fi
    # Windows Subsystem for Linux (WSL)
    elif [[ "$(cat /proc/sys/kernel/osrelease 2>/dev/null)" =~ [Mm]icrosoft ]]; then
        osrelease="$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
        if [[ "${osrelease}" =~ microsoft ]]; then # WSL2
            echo ""
            echo "Using WSL2 and VirtualBox requires using Hyper-V with VirtualBox."
            printf "${warning_color}"'VirtualBox usually doen'"'"'t work with WSL2 installed.'"${default_color}"'\n'
            echo ""
            printf "${highlight_color}"'Press enter to continue, CTRL-C to exit.'"${default_color}"
            clear_input_buffer_then_read
        elif [[ ("${osrelease}" =~ Microsoft) ]]; then # WSL (1)
            echo ""
            echo "Some versions of WSL require the script to run on a Windows filesystem path,"
            printf 'for example   '"${highlight_color}"'/mnt/c/Users/Public/Documents'"${default_color}"'\n'
            echo "Switch to a path on the Windows filesystem if VBoxManage.exe fails to"
            echo "create or open a file."
            echo ""
            printf "${highlight_color}"'Press enter to continue, CTRL-C to exit.'"${default_color}"
            clear_input_buffer_then_read
        fi
        if [ -n "$(VBoxManage.exe -v 2>/dev/null)" ]; then
            function VBoxManage() {
                VBoxManage.exe "$@"
            }
        else
            wsl_path_VBoxManage='/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe'
            echo "Can't find VBoxManage in PATH variable,"
            echo "checking ${wsl_path_VBoxManage}"
            if [ -n "$("${wsl_path_VBoxManage}" -v 2>/dev/null)" ]; then
                PATH="${PATH}:${wsl_path_VBoxManage%/*}"
                function VBoxManage() {
                    VBoxManage.exe "$@"
                }
                echo "Found VBoxManage"
            else
                echo "Please make sure VirtualBox is installed on Windows, and that the path to the"
                echo "VBoxManage.exe executable is in the PATH variable, or assigned in the script"
                printf 'to the variable '"${highlight_color}"'wsl_path_VBoxManage'"${default_color}"' including the name of the executable.'
                exit
            fi
        fi
    # everything else (not cygwin and not wsl)
    elif [ -z "$(VBoxManage -v 2>/dev/null)" ]; then
        echo "Please make sure VirtualBox version 6.0 or higher is installed,"
        echo "and that the path to the VBoxManage executable is in the PATH variable."
        exit
    fi

    # VirtualBox version
    vbox_version="$(VBoxManage -v 2>/dev/null)"
    vbox_version="$(printf ${vbox_version} | tr -d '\r')"
    if [ -z "${vbox_version}" -o -z "${vbox_version:2:1}" ]; then
        echo "Can't determine VirtualBox version. Exiting."
        exit
    elif [[ ("${vbox_version:0:1}" -lt 5) || ("${vbox_version:0:1}" = 5 && "${vbox_version:2:1}" -lt 2) ]]; then
        echo ""
        echo "Please make sure VirtualBox version 5.2 or higher is installed."
        echo "Exiting."
        exit
    elif [[ "${vbox_version:0:1}" = 5 ]]; then
        echo ""
        printf "${highlight_color}"'VirtualBox version '"${vbox_version}"' detected.'"${default_color}"' Please see the following
URL for issues with the VISO filesystem on VirtualBox 5.2 to 5.2.36:

  https://github.com/myspaghetti/macos-guest-virtualbox/issues/86

'"${highlight_color}"'Press enter to continue, CTRL-C to exit.'"${default_color}"
        clear_input_buffer_then_read
    fi

    # Oracle VM VirtualBox Extension Pack
    extpacks="$(VBoxManage list extpacks 2>/dev/null)"
    if [ "$(expr match "${extpacks}" '.*Oracle VM VirtualBox Extension Pack')" -le "0" \
        -o "$(expr match "${extpacks}" '.*Usable:[[:blank:]]*false')" -gt "0" ]; then
        echo "Please make sure Oracle VM VirtualBox Extension Pack is installed, and that"
        echo "all installed VirtualBox extensions are listed as usable when"
        echo "running the command \"VBoxManage list extpacks\""
        exit
    fi

    # dmg2img
    if [ -z "$(dmg2img -d 2>/dev/null)" ]; then
        if [ -z "$(cygcheck -V 2>/dev/null)" ]; then
            echo "Please install the package dmg2img."
            exit
        elif [ -z "$(${PWD}/dmg2img -d 2>/dev/null)" ]; then
            echo "Locally installing dmg2img"
            wget "http://vu1tur.eu.org/tools/dmg2img-1.6.6-win32.zip" \
                ${wgetargs} \
                --output-document="dmg2img-1.6.6-win32.zip"
            if [ ! -s dmg2img-1.6.6-win32.zip ]; then
                echo "Error downloading dmg2img. Please provide the package manually."
                exit
            fi
            unzip -oj "dmg2img-1.6.6-win32.zip" "dmg2img.exe"
            rm "dmg2img-1.6.6-win32.zip"
            chmod +x "dmg2img.exe"
        fi
    fi

    # set Apple software update catalog URL according to macOS version
    HighSierra_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
    Mojave_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
    Catalina_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
    if [[ "${macOS_release_name:0:1}" =~ [Cc] ]]; then
        macOS_release_name="Catalina"
        CFBundleShortVersionString="10.15"
        sucatalog="${Catalina_sucatalog}"
#         printf 'As of January 2020, macOS Catalina 10.15.2 and 10.15.3 '"${warning_color}"'do not boot'"${default_color}"' on VirtualBox.
# For a workaround, please visit the following URL:
#   '"${highlight_color}"'https://github.com/myspaghetti/macos-guest-virtualbox/issues/134#issuecomment-578764413'"${default_color}"'

# '"${highlight_color}"'Press enter to continue, CTRL-C to exit.'"${default_color}"
        #clear_input_buffer_then_read
    elif [[ "${macOS_release_name:0:1}" =~ [Hh] ]]; then
        macOS_release_name="HighSierra"
        CFBundleShortVersionString="10.13"
        sucatalog="${HighSierra_sucatalog}"
    else
        macOS_release_name="Mojave"
        CFBundleShortVersionString="10.14"
        sucatalog="${Mojave_sucatalog}"
    fi
    print_dimly "${macOS_release_name} selected to be downloaded and installed"
}
# Done with dependencies

function prompt_delete_existing_vm() {
    print_dimly "stage: prompt_delete_existing_vm"
    if [ -n "$(VBoxManage showvminfo "${vmname}" 2>/dev/null)" ]; then
        echo ''
        echo 'A virtual machine named "'"${vmname}"'" already exists.'
        printf "${warning_color}"'Delete existing virtual machine "'"${vmname}"'"?'"${default_color}"
        delete=""
        read -n 1 -p ' [y/N] ' delete
        echo ""
        if [ "${delete,,}" == "y" ]; then
            VBoxManage unregistervm "${vmname}" --delete
        else
            echo ""
            printf "${highlight_color}"'Please assign a different VM name to variable "vmname" by editing the script,'"${default_color}"
            echo "or skip this check manually as described when running the following command:"
            would_you_like_to_know_less
            exit
        fi
    fi
}

# Attempt to create new virtual machine named "${vmname}"
function create_vm() {
    print_dimly "stage: create_vm"
    if [ -n "$(VBoxManage createvm --name "${vmname}" --ostype "MacOS1013_64" --register 2>&1 >/dev/null)" ]; then
        printf '\nError: Could not create virtual machine "'"${vmname}"'".
'"${highlight_color}"'Please delete exising "'"${vmname}"'" VirtualBox configuration files '"${warning_color}"'manually'"${default_color}"'.

Error message:
'
        VBoxManage createvm --name "${vmname}" --ostype "MacOS10_64" --register 2>/dev/tty
        exit
    fi
}

function prepare_macos_installation_files() {
    print_dimly "stage: prepare_macos_installation_files"
    # Find the correct download URL in the Apple catalog
    echo ""
    echo "Downloading Apple macOS ${macOS_release_name} software update catalog"
    wget "${sucatalog}" \
        ${wgetargs} \
        --output-document="${macOS_release_name}_sucatalog"

    # if file was not downloaded correctly
    if [ ! -s "${macOS_release_name}_sucatalog" ]; then
        wget --debug -O /dev/null -o "${macOS_release_name}_wget.log" "${sucatalog}"
        echo ""
        echo "Couldn't download the Apple software update catalog."
        if [ "$(expr match "$(cat "${macOS_release_name}_wget.log")" '.*ERROR[[:print:]]*is not trusted')" -gt "0" ]; then
            printf '
Make sure certificates from a certificate authority are installed.
Certificates are often installed through the package manager with
a package named '"${highlight_color}"'ca-certificates'"${default_color}"
        fi
        echo "Exiting."
        exit
    fi

    echo "Trying to find macOS ${macOS_release_name} InstallAssistant download URL"
    tac "${macOS_release_name}_sucatalog" | csplit - '/InstallAssistantAuto.smd/+1' '{*}' -f "${macOS_release_name}_sucatalog_" -s
    for catalog in "${macOS_release_name}_sucatalog_"* "error"; do
        if [[ "${catalog}" == error ]]; then
            rm "${macOS_release_name}_sucatalog"*
            printf "Couldn't find the requested download URL in the Apple catalog. Exiting."
            exit
        fi
        urlbase="$(tail -n 1 "${catalog}" 2>/dev/null)"
        urlbase="$(expr match "${urlbase}" '.*\(http://[^<]*/\)')"
        wget "${urlbase}InstallAssistantAuto.smd" \
            ${wgetargs} \
            --output-document="${catalog}_InstallAssistantAuto.smd"
        found_version="$(head -n 6 "${catalog}_InstallAssistantAuto.smd" | tail -n 1)"
        if [[ "${found_version}" == *${CFBundleShortVersionString}* ]]; then
            echo "Found download URL: ${urlbase}"
            echo ""
            rm "${macOS_release_name}_sucatalog"*
            break
        fi
    done
    echo "Downloading macOS installation files from swcdn.apple.com"
    for filename in "BaseSystem.chunklist" \
        "InstallInfo.plist" \
        "AppleDiagnostics.dmg" \
        "AppleDiagnostics.chunklist"; do
        wget "${urlbase}${filename}" \
            ${wgetargs} \
            --output-document "${macOS_release_name}_${filename}"
    done

    # echo ""
    # echo "Splitting the several-GB InstallESDDmg.pkg into 1GB parts because"
    # echo "VirtualBox hasn't implemented UDF/HFS VISO support yet and macOS"
    # echo "doesn't support ISO 9660 Level 3 with files larger than 2GB."
    # split -a 2 -b 1000000000 "${macOS_release_name}_InstallESD.dmg" "${macOS_release_name}_InstallESD.part"

    if [[ ! -s "ApfsDriverLoader.efi" ]]; then
        echo ""
        echo "Downloading open-source APFS EFI drivers used for VirtualBox 6.0 and 5.2"
        [[ "${vbox_version:0:1}" -gt 6 || ("${vbox_version:0:1}" = 6 && "${vbox_version:2:1}" -ge 1) ]] && echo "...even though that's not the version of VirtualBox that's been detected."
        wget 'https://github.com/acidanthera/AppleSupportPkg/releases/download/2.0.4/AppleSupport-v2.0.4-RELEASE.zip' \
            ${wgetargs} \
            --output-document 'AppleSupport-v2.0.4-RELEASE.zip'
        unzip -oj 'AppleSupport-v2.0.4-RELEASE.zip'
    fi
}

function create_nvram_files() {
    print_dimly "stage: create_nvram_files"
    # Each NVRAM file may contain multiple entries.
    # Each entry contains a namesize, datasize, name, guid, attributes, and data.
    # Each entry is immediately followed by a crc32 of the entry.
    # The script creates each file with only one entry for easier editing.
    #
    # The hex strings are stripped by xxd, so they can
    # look like "0xAB 0xCD" or "hAB hCD" or "AB CD" or "ABCD" or a mix of formats
    # and have extraneous characters like spaces or minus signs.

    # Load the binary files into VirtualBox VM NVRAM with the builtin command dmpstore
    # in the VM EFI Internal Shell, for example:
    # dmpstore -all -l fs0:\system-id.bin
    #
    # DmpStore code is available at this URL:
    # https://github.com/mdaniel/virtualbox-org-svn-vbox-trunk/blob/master/src/VBox/Devices/EFI/Firmware/ShellPkg/Library/UefiShellDebug1CommandsLib/DmpStore.c

    function generate_nvram_bin_file() {
        # input: name data guid (three positional arguments, all required)
        # output: function outputs nothing to stdout
        #         but writes a binary file to working directory
        local namestring="${1}" # string of chars
        local filename="${namestring}"
        # represent string as string-of-hex-bytes, add null byte after every byte,
        # terminate string with two null bytes
        local name="$(
            for ((i = 0; i < "${#namestring}"; i++)); do
                printf -- "${namestring:${i}:1}" | xxd -p | tr -d '\n'
                printf '00'
            done
            printf '0000'
        )"
        # size of string in bytes, represented by eight hex digits, big-endian
        local namesize="$(printf "%08x" $((${#name} / 2)))"
        # flip four big-endian bytes byte-order to little-endian
        local namesize="$(printf "${namesize}" | xxd -r -p | od -tx4 -N4 -An --endian=little)"
        # strip string-of-hex-bytes representation of data of spaces, "x", "h", etc
        local data="$(printf -- "${2}" | xxd -r -p | xxd -p)"
        # size of data in bytes, represented by eight hex digits, big-endian
        local datasize="$(printf "%08x" $((${#data} / 2)))"
        # flip four big-endian bytes byte-order to little-endian
        local datasize="$(printf "${datasize}" | xxd -r -p | od -tx4 -N4 -An --endian=little)"
        # guid string-of-hex-bytes is five fields, 8+4+4+4+12 bytes long
        # first three are little-endian, last two big-endian
        # for example, 00112233-4455-6677-8899-AABBCCDDEEFF
        # is stored as 33221100-5544-7766-8899-AABBCCDDEEFF
        local g="$(printf -- "${3}" | xxd -r -p | xxd -p)" # strip spaces etc
        local guid="${g:6:2} ${g:4:2} ${g:2:2} ${g:0:2} ${g:10:2} ${g:8:2} ${g:14:2} ${g:12:2} ${g:16:16}"
        # attributes in four bytes little-endian
        local attributes="07 00 00 00"
        # the data structure
        local entry="${namesize} ${datasize} ${name} ${guid} ${attributes} ${data}"
        # calculate crc32 using gzip, flip crc32 bytes into big-endian
        local crc32="$(printf "${entry}" | xxd -r -p | gzip -c | tail -c8 | od -tx4 -N4 -An --endian=big)"
        # save binary data
        printf -- "${entry} ${crc32}" | xxd -r -p - "${vmname}_${filename}.bin"
    }

    # MLB
    MLB_b16="$(printf -- "${MLB}" | xxd -p)"
    generate_nvram_bin_file MLB "${MLB_b16}" "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14"

    # ROM
    # Convert the mixed-ASCII-and-base16 ROM value
    # into an ASCII string that represents a base16 number.
    ROM_b16="$(for ((i = 0; i < ${#ROM}; )); do
        let j=i+1
        if [ "${ROM:${i}:1}" == "%" ]; then
            echo -n "${ROM:${j}:2}"
            let i=i+3
        else
            x="$(echo -n "${ROM:${i}:1}" | od -t x1 -An | tr -d ' ')"
            echo -n "${x}"
            let i=i+1
        fi
    done)"
    generate_nvram_bin_file ROM "${ROM_b16}" "4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14"

    # system-id
    generate_nvram_bin_file system-id "${SYSTEM_UUID}" "7C436110-AB2A-4BBB-A880-FE41995C9F82"

    # SIP / csr-active-config
    generate_nvram_bin_file csr-active-config "${SYSTEM_INTEGRITY_PROTECTION}" "7C436110-AB2A-4BBB-A880-FE41995C9F82"
}

function create_macos_installation_files_viso() {
    print_dimly "stage: create_macos_installation_files_viso"
    echo "Creating EFI startup script"
    echo 'echo -off' >"${vmname}_startup.nsh"
    if [[ ("${vbox_version:0:1}" -lt 6) || ("${vbox_version:0:1}" = 6 && "${vbox_version:2:1}" = 0) ]]; then
        echo 'load fs0:\EFI\OC\Drivers\AppleImageLoader.efi
load fs0:\EFI\OC\Drivers\AppleUiSupport.efi
load fs0:\EFI\OC\Drivers\ApfsDriverLoader.efi
map -r' >>"${vmname}_startup.nsh"
    fi
    echo 'if exist "fs0:\EFI\NVRAM\MLB.bin" then
  dmpstore -all -l fs0:\EFI\NVRAM\MLB.bin
  dmpstore -all -l fs0:\EFI\NVRAM\ROM.bin
  dmpstore -all -l fs0:\EFI\NVRAM\csr-active-config.bin
  dmpstore -all -l fs0:\EFI\NVRAM\system-id.bin
endif
for %a run (1 5)
  if exist "fs%a:\EFI\NVRAM\MLB.bin" then
    dmpstore -all -l fs%a:\EFI\NVRAM\MLB.bin
    dmpstore -all -l fs%a:\EFI\NVRAM\ROM.bin
    dmpstore -all -l fs%a:\EFI\NVRAM\csr-active-config.bin
    dmpstore -all -l fs%a:\EFI\NVRAM\system-id.bin
  endif
endfor
for %a run (1 5)
  if exist "fs%a:\System\Library\CoreServices\boot.efi" then
    "fs%a:\System\Library\CoreServices\boot.efi"
  endif
endfor
for %a run (1 5)
  if exist "fs%a:\macOS Install Data\Locked Files\Boot Files\boot.efi" then
    "fs%a:\macOS Install Data\Locked Files\Boot Files\boot.efi"
  endif
endfor' >>"${vmname}_startup.nsh"

    echo ""
    echo "Creating VirtualBox 6 virtual ISO containing the"
    echo "installation files from swcdn.apple.com"
    echo ""
    pseudouuid="$(od -tx -N16 /dev/urandom | xxd -r | xxd -p)"
    pseudouuid="${pseudouuid:0:8}-${pseudouuid:8:4}-${pseudouuid:12:4}-${pseudouuid:16:4}-${pseudouuid:20:12}"
    echo "--iprt-iso-maker-file-marker-bourne-sh "${pseudouuid}"
--volume-id=${macOS_release_name:0:5}-files" >"${macOS_release_name}_Installation_files.viso"

    # Apple macOS installation files
    for filename in "BaseSystem.chunklist" \
        "InstallInfo.plist" \
        "AppleDiagnostics.dmg" \
        "AppleDiagnostics.chunklist" \
        "BaseSystem.dmg"; do
        if [ -s "${macOS_release_name}_${filename}" ]; then
            echo "/${filename}=\"${macOS_release_name}_${filename}\"" >>"${macOS_release_name}_Installation_files.viso"
        fi
    done

    if [ -s "${macOS_release_name}_InstallESD.part00" ]; then
        for part in "${macOS_release_name}_InstallESD.part"*; do
            echo "/InstallESD${part##*InstallESD}=\"${part}\"" >>"${macOS_release_name}_Installation_files.viso"
        done
    fi

    # NVRAM binary files
    for filename in "MLB.bin" "ROM.bin" "csr-active-config.bin" "system-id.bin"; do
        if [ -s "${vmname}_${filename}" ]; then
            echo "/ESP/EFI/NVRAM/${filename}=\"${vmname}_${filename}\"" >>"${macOS_release_name}_Installation_files.viso"
        fi
    done

    # EFI drivers for VirtualBox 6.0 and 5.2
    for filename in "ApfsDriverLoader.efi" "AppleImageLoader.efi" "AppleUiSupport.efi"; do
        if [ -s "${filename}" ]; then
            echo "/ESP/EFI/OC/Drivers/${filename}=\"${filename}\"" >>"${macOS_release_name}_Installation_files.viso"
        fi
    done

    # EFI startup script
    echo "/ESP/startup.nsh=\"${vmname}_startup.nsh\"" >>"${macOS_release_name}_Installation_files.viso"

}

# Create the target virtual disk image
function create_target_vdi() {
    print_dimly "stage: create_target_vdi"
    if [ -w "${vmname}.vdi" ]; then
        echo "${vmname}.vdi target system virtual disk image exists."
    elif [ "${macOS_release_name}" = "Catalina" -a "${storagesize}" -lt 25000 ]; then
        echo "Attempting to install macOS Catalina on a disk smaller than 25000MB will fail."
        echo "Please assign a larger virtual disk image size. Exiting."
        exit
    elif [ "${storagesize}" -lt 22000 ]; then
        echo "Attempting to install macOS on a disk smaller than 22000MB will fail."
        echo "Please assign a larger virtual disk image size. Exiting."
        exit
    else
        echo "Creating ${vmname} target system virtual disk image."
        VBoxManage createmedium --size="${storagesize}" \
            --filename "${vmname}.vdi" \
            --variant standard 2>/dev/tty
    fi
}

function configure_vm() {
    print_dimly "stage: configure_vm"
    VBoxManage modifyvm "${vmname}" --cpus "${cpucount}" --memory "${memorysize}" \
        --vram "${gpuvram}" --pae on --boot1 none --boot2 none --boot3 none \
        --boot4 none --firmware efi --rtcuseutc on --usbxhci on --chipset ich9 \
        --mouse usbtablet --keyboard usb --audiocontroller hda --audiocodec stac9221

    VBoxManage setextradata "${vmname}" \
        "VBoxInternal2/EfiGraphicsResolution" "${resolution}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemFamily" "${DmiSystemFamily}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemProduct" "${DmiSystemProduct}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemSerial" "${DmiSystemSerial}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemUuid" "${DmiSystemUuid}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiOEMVBoxVer" "${DmiOEMVBoxVer}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiOEMVBoxRev" "${DmiOEMVBoxRev}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiBIOSVersion" "${DmiBIOSVersion}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiBoardProduct" "${DmiBoardProduct}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiBoardSerial" "${DmiBoardSerial}"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemVendor" "Apple Inc."
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/efi/0/Config/DmiSystemVersion" "1.0"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/smc/0/Config/DeviceKey" \
        "ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
    VBoxManage setextradata "${vmname}" \
        "VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC" 0
}

function confirm_boot() {
    print_dimly "stage: confirm_boot"
    echo 'Boot image will be attached and the VM will boot to a "Shell>" prompt.'
    echo 'Confirm the system boots then power off the machine.'

    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1

    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        ) ]]; then
        echo "Could not attach boot image."
        echo "Confirm the VM is not currently running. Exiting."
        exit
    fi

    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)
}

function populate_virtual_disks() {
    print_dimly "stage: populate_virtual_disks"
    # Attach virtual disk images of the base system, installation, and target
    # to the virtual machine
    
    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
             --type dvddrive --medium "scripts/${macOS_release_name}_BaseSystem-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 2 \
             --type dvddrive --medium "scripts/Install_${macOS_release_name}-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 3 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null

    ) ]]; then
        echo "One or more virtual storage files could not be loaded."
        echo "Confirm the VM is shutdown. Exiting."
        exit
    fi
    printf "Starting virtual machine ${vmname}. This should take a couple of minutes."
    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)
    prompt_lang_utils
    prompt_terminal_ready
    print_dimly "Please wait"
    kbstring='disks="$(diskutil list | grep -o "\*[0-9][^ ]* GB *disk[0-9]$" | grep -o "[0-9].*" | sort -gr | grep -o disk[0-9] )" && '\
'disks=(${disks[@]}) && '\
'if [ -z "${disks}" ]; then echo "Could not find disks"; fi && '\
'[ -n "${disks[0]}" ] && '\
'diskutil partitionDisk "/dev/${disks[0]}" 1 GPT APFS "'"Macintosh HD"'" R && '
    send_keys
    print_dimly "Partitioning complete"

    # shut down the virtual machine
    kbstring='shutdown -h now'
    send_keys
    send_enter
    printf 'Partitioning the target virtual disk'
    printf 'and rebooting the virtual machine.

The virtual machine may report that disk space is critically low; this is fine.

When finished the script will shut down the virtual machine.'

    print_dimly "If the partitioning fails, exit the script by pressing CTRL-C."
    print_dimly "Otherwise, please wait."
}


function delete_temporary_files() {
    print_dimly "stage: delete_temporary_files"
    if [[ ! "$(VBoxManage showvminfo "${vmname}")" =~ State:[\ \t]*powered\ off ]]; then
        printf 'Temporary files may be deleted when the virtual machine is powered off
and without a suspended state by running the following command at the script'"'"'s
working directory:

  '"${highlight_color}${0} delete_temporary_files${default_color}"'\n'
    else
        # detach temporary VDIs and attach the macOS target disk
        VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
        VBoxManage storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null 2>&1
        VBoxManage storageattach "${vmname}" --storagectl SATA --port 0 \
            --type hdd --nonrotational on --medium "${vmname}.vdi"
        printf 'The following temporary files are safe to delete:
      "'"${macOS_release_name}_Apple"*'"
      "'"${macOS_release_name}_BaseSystem"*'"
      "'"${macOS_release_name}_Install"*'"
      "'"${vmname}_"*".bin"'"
      "'"${vmname}_csr-active-config.bin"'"
      "'"${vmname}_startup.nsh"'"
      "'"ApfsDriverLoader.efi"'"
      "'"Apple"*".efi"'"
      "'"AppleSupport-v2.0.4-RELEASE.zip"'"\n'
        if [ -w "dmg2img.exe" ]; then
            printf '      "'"dmg2img.exe"'"\n'
        fi
        echo ""
        printf "${warning_color}"'Delete temporary files?'"${default_color}"
        delete=""
        read -n 1 -p " [y/N] " delete
        echo ""
        if [ "${delete,,}" == "y" ]; then
            rm "${macOS_release_name}_"* \                                                
                "${vmname}_"*".bin" \
                "${vmname}_startup.nsh" \
                "ApfsDriverLoader.efi" \
                "Apple"*".efi" \
                "scripts/"*"iso" \
                "scripts/"*".dmg"
                "AppleSupport-v2.0.4-RELEASE.zip" 2>/dev/null
            rm "dmg2img.exe" 2>/dev/null
        fi
    fi

}

function init_installer() {
    print_dimly "stage: init_installer"
    # Attach virtual disk images of the base system, installation, and target
    # to the virtual machine
    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
             --type dvddrive --medium "scripts/${macOS_release_name}_BaseSystem-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 2 \
             --type dvddrive --medium "scripts/Install_${macOS_release_name}-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 3 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null

    ) ]]; then
        echo "One or more virtual storage files could not be loaded. Exiting."
        exit
    fi

    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)

    echo "Starting virtual machine ${vmname}. This should take a couple of minutes."
    prompt_lang
    select_reinstall

    echo 'Continue through installer until the VM reboots.'
    echo 'When the VM reboots it will not startup. This is expected...'
    echo ''
    echo 'Power off the machine and press enter to continue'
    clear_input_buffer_then_read
    confirm_boot
}

function start_installer() {
    print_dimly "stage: start_installer"
    # Attach virtual disk images of the base system, installation, and target
    # to the virtual machine
    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null

    ) ]]; then
        echo "One or more virtual storage files could not be loaded. Exiting."
        exit
    fi

    echo "Starting virtual machine ${vmname}. This should take a couple of minutes."
    echo "After install is complete the VM will restart."
    echo "The VM will not boot. This is expected..."
    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)
    echo ''
    echo 'Power off the machine and press enter to continue'
    clear_input_buffer_then_read
    confirm_boot
}

function fix_init_installer() {
    print_dimly "stage: fix_init_installer"

    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
             --type dvddrive --medium "scripts/${macOS_release_name}_BaseSystem-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 2 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null

    ) ]]; then
        echo "One or more virtual storage files could not be loaded. Exiting."
        exit
    fi

    printf "Starting virtual machine ${vmname}. This should take a couple of minutes."
    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)

    prompt_utils
    prompt_terminal_ready
    printf "Replacing macOS Install Data boot.efi file..."
    print_dimly "Please wait"
    
    kbstring='mv "/Volumes/Macintosh HD/macOS Install Data/Locked Files/Boot Files/boot.efi" "/Volumes/Macintosh HD/macOS Install Data/Locked Files/Boot Files/_boot.efi" && ' 
    send_keys
    
    kbstring='cp /System/Library/CoreServices/boot.efi "/Volumes/Macintosh HD/macOS Install Data/Locked Files/Boot Files/boot.efi" && '
    send_keys
    
    kbstring='shutdown -h now'
    send_keys
    send_enter
}

function fix_preboot() {
    print_dimly "stage: fix_preboot"

    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 0 \
             --type dvddrive --medium "scripts/${macOS_release_name}_Boot_Image.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
             --type dvddrive --medium "scripts/${macOS_release_name}_BaseSystem-10.15.3.iso" >/dev/null

        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 2 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null
    ) ]]; then
        echo "One or more virtual storage files could not be loaded. Exiting."
        exit
    fi

    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)
    prompt_utils
    prompt_terminal_ready
    printf "Replacing boot.efi file on Preboot volume and Macintosh HD..."

    print_dimly "Please wait"
    kbstring='preboot="$(diskutil list | grep Preboot | grep -o disk[0-9]s[0-9])"'\
' && '\
'diskutil mount $preboot'\
' && '\
'cd /Volumes/Preboot'\
' && '\
'uuid="$(ls)"'\
' && '\
'mv "/Volumes/Preboot/$uuid/System/Library/CoreServices/boot.efi" "/Volumes/Preboot/$uuid/System/Library/CoreServices/_boot.efi"'\
' && '\
'mv "/Volumes/Macintosh HD/System/Library/CoreServices/boot.efi" "/Volumes/Macintosh HD/System/Library/CoreServices/_boot.efi"'\
' && '\
'cp "/System/Library/CoreServices/boot.efi" "/Volumes/Preboot/$uuid/System/Library/CoreServices/boot.efi"'\
' && '\
'cp /System/Library/CoreServices/boot.efi "/Volumes/Macintosh HD/System/Library/CoreServices/boot.efi"'\
' && '\
    send_keys

    kbstring='shutdown -h now'
    send_keys
    send_enter

    echo 'Once the files are copied the VM will power off'
}

function start_catalina() {
    print_dimly "stage: start_catalina"
    echo 'Starting Catalina...'
    
    VBoxManage storagectl "${vmname}" --remove --name SATA >/dev/null 2>&1
    if [[ -n $(
        VBoxManage 2>&1 storagectl "${vmname}" --add sata --name SATA --hostiocache on >/dev/null
        
        VBoxManage 2>&1 storageattach "${vmname}" --storagectl SATA --port 1 \
            --type hdd --nonrotational on --medium "${vmname}.vdi" >/dev/null

    ) ]]; then
        echo "One or more virtual storage files could not be loaded. Exiting."
        exit
    fi

    echo "Starting virtual machine ${vmname}. This should take a couple of minutes."
    (VBoxManage startvm "${vmname}" >/dev/null 2>&1)

}

function documentation() {
    low_contrast_stages=""
    for stage in ${stages}; do
        low_contrast_stages="${low_contrast_stages}"'    '"${low_contrast_color}${stage}${default_color}"'\n'
    done
    printf "
        ${highlight_color}NAME${default_color}
Run MacOS Catalina (10.15.13) Guest on VirtualBox

        ${highlight_color}DESCRIPTION${default_color}
The script downloads, configures, and installs macOS High Sierra, Mojave,
and Catalina on VirtualBox 5.2, 6.0, and 6.1. The script is semi-automatic
and requires a little user interaction. A default fresh install only
requires the user to sit patiently and, ten times, Press enter when prompted.

        ${highlight_color}USAGE${default_color}
    ${low_contrast_color}${0} [STAGE]... ${default_color}

The script is divided into stages. Stage titles may be given as command-line
arguments for the script. When the script is run with no command-line
arguments, each of the available stages, except \"documentation\", is executed
in succession in the order listed:

${low_contrast_stages}
When \"documentation\" is the first command-line argument, only the
\"documentation\" stage is executed and all other arguments are ignored.

The four stages \"check_bash_version\", \"check_gnu_coreutils_prefix\",
\"set_variables\", and \"check_dependencies\" are always performed when any stage
title other than \"documentation\" is specified first, and if the checks pass
then the stages specified in the command-line arguments are performed.

        ${highlight_color}EXAMPLES${default_color}
    ${low_contrast_color}${0} configure_vm${default_color}

The above stage might be used after copying an existing VM VDI to a different
VirtualBox installation and having the script automatically configure the VM.

    ${low_contrast_color}${0} delete_temporary_files${default_color}

The above stage might be used when no more virtual machines need to be installed,
and the temporary files can be deleted.

    ${low_contrast_color}${0} "'\\'"${default_color}
${low_contrast_color}configure_vm create_nvram_files create_macos_installation_files_viso${default_color}

The above stages might be used to update the EFI and NVRAM variables required
for iCloud and iMessage connectivity and other Apple-connected apps.

        ${highlight_color}iCloud and iMessage connectivity${default_color}
iCloud, iMessage, and other connected Apple services require a valid device
name and serial number, board ID and serial number, and other genuine
(or genuine-like) Apple parameters. These parameters may be edited at the top
of the script, accompanied by an explanation. Editing them is not required when
installing or running macOS, only when connecting to the iCould app, iMessage,
and other apps that authenticate the device with Apple.

The variables needed to be assigned in the script are the following:

${low_contrast_color}DmiSystemFamily    # Model name${default_color}
${low_contrast_color}DmiSystemProduct   # Model identifier${default_color}
${low_contrast_color}DmiSystemSerial    # System serial number${default_color}
${low_contrast_color}DmiSystemUuid      # Hardware UUID${default_color}
${low_contrast_color}DmiOEMVBoxVer      # Apple ROM info (major version)${default_color}
${low_contrast_color}DmiOEMVBoxRev      # Apple ROM info (revision)${default_color}
${low_contrast_color}DmiBIOSVersion     # Boot ROM version${default_color}
${low_contrast_color}DmiBoardProduct    # Main Logic Board identifier${default_color}
${low_contrast_color}DmiBoardSerial     # Main Logic Board serial (EFI)${default_color}
${low_contrast_color}MLB                # Main Logic Board serial (NVRAM)${default_color}
${low_contrast_color}ROM                # ROM identifier (NVRAM)${default_color}
${low_contrast_color}SYSTEM_UUID        # System identifier (NVRAM)${default_color}

The comments at the top of the script specify how to view these variables
on a genuine Mac.

        ${highlight_color}Applying the EFI and NVRAM parameters${default_color}
The EFI and NVRAM parameters may be set in the script before installation by
editing them at the top of the script, and applied after the last step of the
installation by resetting the virtual machine and booting into the
EFI Internal Shell. When resetting or powering up the VM, immediately press
Esc when the VirtualBox logo appears. This boots into the EFI Internal Shell or
the boot menu. If the boot menu appears, select \"Boot Manager\" and then
\"EFI Internal Shell\" and then allow the startup.nsh script to run
automatically, applying the EFI and NVRAM variables before booting macOS.

        ${highlight_color}Changing the EFI and NVRAM parameters after installation${default_color}
The variables mentioned above may be edited and applied to an existing macOS
virtual machine by executing the following command and copying the generated
files to the macOS EFI partition:

    ${low_contrast_color}${0} "'\\'"${default_color}
${low_contrast_color}configure_vm create_nvram_files create_macos_installation_files_viso${default_color}

After running the command, attach the resulting VISO file to the virtual
machine's storage through VirtualBox Manager or VBoxManage. Power up the VM
and boot macOS, then start Terminal and execute the following commands, making
sure to replace \"/Volumes/path/to/VISO/\" with the correct path:

${low_contrast_color}mkdir ESP${default_color}
${low_contrast_color}sudo su # this will prompt for a password${default_color}
${low_contrast_color}diskutil mount -mountPoint ESP disk0s1${default_color}
${low_contrast_color}cp /Volumes/path/to/VISO/ESP/* ESP/${default_color}

After copying the files, boot into the EFI Internal Shell as desribed in the
section \"Applying the EFI and NVRAM parameters\".

        ${highlight_color}Storage size${default_color}
The script by default assigns a target virtual disk storage size of 80GB, which
is populated to about 15GB on the host on initial installation. After the
installation is complete, the storage size may be increased. First increase the
virtual disk image size through VirtualBox Manager or VBoxManage, then in
Terminal in the virtual machine run ${low_contrast_color}sudo diskutil repairDisk disk0${default_color}, and then
${low_contrast_color}sudo diskutil apfs resizeContainer disk1 0${default_color} or from Disk Utility, after
repairing the disk from Terminal, delete the \"Free space\" partition so it allows
the system APFS container to take up the available space.

        ${highlight_color}Graphics controller${default_color}
Selecting the VBoxSVGA controller instead of VBoxVGA for the graphics controller may considerably increase graphics performance.

        ${highlight_color}Performance and unsupported features${default_color}
Developing and maintaining VirtualBox or macOS features is beyond the scope of
this script. Some features may behave unexpectedly, such as USB device support,
audio support, and other features.

After successfully creating a working macOS virtual machine, consider importing
it into QEMU/KVM so it can run with hardware passthrough at near-native
performance. QEMU/KVM requires additional configuration that is beyond the
scope of the script.

For more information visit the URL:
        ${highlight_color}https://github.com/kyle/macos-on-virtualbox${default_color}

Based on original source found here:
        ${highlight_color}https://github.com/myspaghetti/macos-guest-virtualbox${default_color}
"
}

# GLOBAL VARIABLES AND FUNCTIONS THAT MIGHT BE CALLED MORE THAN ONCE

# terminal text colors
warning_color="\e[48;2;255;0;0m\e[38;2;255;255;255m"    # white on red
highlight_color="\e[48;2;0;0;9m\e[38;2;255;255;255m"    # white on black
low_contrast_color="\e[48;2;0;0;9m\e[38;2;128;128;128m" # grey on black
default_color="\033[0m"

# prints positional parameters in low contrast preceded and followed by newline
function print_dimly() {
    printf "\n${low_contrast_color}$@${default_color}\n"
}

# don't need sleep when we can read!
function sleep() {
    read -t "${1}" >/dev/null 2>&1
}

# QWERTY-to-scancode dictionary. Hex scancodes, keydown and keyup event.
# Virtualbox Mac scancodes found here:
# https://wiki.osdev.org/PS/2_Keyboard#Scan_Code_Set_1
# First half of hex code - press, second half - release, unless otherwise specified
declare -A kscd=(
    ["ESC"]="01 81"
    ["1"]="02 82"
    ["2"]="03 83"
    ["3"]="04 84"
    ["4"]="05 85"
    ["5"]="06 86"
    ["6"]="07 87"
    ["7"]="08 88"
    ["8"]="09 89"
    ["9"]="0A 8A"
    ["0"]="0B 8B"
    ["-"]="0C 8C"
    ["="]="0D 8D"
    ["BKSP"]="0E 8E"
    ["TAB"]="0F 8F"
    ["q"]="10 90"
    ["w"]="11 91"
    ["e"]="12 92"
    ["r"]="13 93"
    ["t"]="14 94"
    ["y"]="15 95"
    ["u"]="16 96"
    ["i"]="17 97"
    ["o"]="18 98"
    ["p"]="19 99"
    ["["]="1A 9A"
    ["]"]="1B 9B"
    ["ENTER"]="1C 9C"
    ["CTRLprs"]="1D"
    ["CTRLrls"]="9D"
    ["a"]="1E 9E"
    ["s"]="1F 9F"
    ["d"]="20 A0"
    ["f"]="21 A1"
    ["g"]="22 A2"
    ["h"]="23 A3"
    ["j"]="24 A4"
    ["k"]="25 A5"
    ["l"]="26 A6"
    [";"]="27 A7"
    ["'"]="28 A8"
    ['`']="29 A9"
    ["LSHIFTprs"]="2A"
    ["LSHIFTrls"]="AA"
    ['\']="2B AB"
    ["z"]="2C AC"
    ["x"]="2D AD"
    ["c"]="2E AE"
    ["v"]="2F AF"
    ["b"]="30 B0"
    ["n"]="31 B1"
    ["m"]="32 B2"
    [","]="33 B3"
    ["."]="34 B4"
    ["/"]="35 B5"
    ["RSHIFTprs"]="36"
    ["RSHIFTrls"]="B6"
    ["ALTprs"]="38"
    ["ALTrls"]="B8"
    ["LALT"]="38 B8"
    ["SPACE"]="39 B9"
    [" "]="39 B9"
    ["CAPS"]="3A BA"
    ["CAPSLOCK"]="3A BA"
    ["F1"]="3B BB"
    ["F2"]="3C BC"
    ["F3"]="3D BD"
    ["F4"]="3E BE"
    ["F5"]="3F BF"
    ["F6"]="40 C0"
    ["F7"]="41 C1"
    ["F8"]="42 C2"
    ["F9"]="43 C3"
    ["F10"]="44 C4"
    ["UP"]="E0 48 E0 C8"
    ["RIGHT"]="E0 4D E0 CD"
    ["LEFT"]="E0 4B E0 CB"
    ["DOWN"]="E0 50 E0 D0"
    ["HOME"]="E0 47 E0 C7"
    ["END"]="E0 4F E0 CF"
    ["PGUP"]="E0 49 E0 C9"
    ["PGDN"]="E0 51 E0 D1"
    ["CMDprs"]="E0 5C"
    ["CMDrls"]="E0 DC"
    # all codes below start with LSHIFTprs as commented in first item:
    ["!"]="2A 02 82 AA" # LSHIFTprs 1prs 1rls LSHIFTrls
    ["@"]="2A 03 83 AA"
    ["#"]="2A 04 84 AA"
    ["$"]="2A 05 85 AA"
    ["%"]="2A 06 86 AA"
    ["^"]="2A 07 87 AA"
    ["&"]="2A 08 88 AA"
    ["*"]="2A 09 89 AA"
    ["("]="2A 0A 8A AA"
    [")"]="2A 0B 8B AA"
    ["_"]="2A 0C 8C AA"
    ["+"]="2A 0D 8D AA"
    ["Q"]="2A 10 90 AA"
    ["W"]="2A 11 91 AA"
    ["E"]="2A 12 92 AA"
    ["R"]="2A 13 93 AA"
    ["T"]="2A 14 94 AA"
    ["Y"]="2A 15 95 AA"
    ["U"]="2A 16 96 AA"
    ["I"]="2A 17 97 AA"
    ["O"]="2A 18 98 AA"
    ["P"]="2A 19 99 AA"
    ["{"]="2A 1A 9A AA"
    ["}"]="2A 1B 9B AA"
    ["A"]="2A 1E 9E AA"
    ["S"]="2A 1F 9F AA"
    ["D"]="2A 20 A0 AA"
    ["F"]="2A 21 A1 AA"
    ["G"]="2A 22 A2 AA"
    ["H"]="2A 23 A3 AA"
    ["J"]="2A 24 A4 AA"
    ["K"]="2A 25 A5 AA"
    ["L"]="2A 26 A6 AA"
    [":"]="2A 27 A7 AA"
    ['"']="2A 28 A8 AA"
    ["~"]="2A 29 A9 AA"
    ["|"]="2A 2B AB AA"
    ["Z"]="2A 2C AC AA"
    ["X"]="2A 2D AD AA"
    ["C"]="2A 2E AE AA"
    ["V"]="2A 2F AF AA"
    ["B"]="2A 30 B0 AA"
    ["N"]="2A 31 B1 AA"
    ["M"]="2A 32 B2 AA"
    ["<"]="2A 33 B3 AA"
    [">"]="2A 34 B4 AA"
    ["?"]="2A 35 B5 AA"
)

function clear_input_buffer_then_read() {
    while read -d '' -r -t 0; do
        read -d '' -t 0.1 -n 10000
        break
    done
    read
}

# read variable kbstring and convert string to scancodes and send to guest vm
function send_keys() {
    scancode=$(for ((i = 0; i < ${#kbstring}; i++)); do
        c[i]=${kbstring:i:1}
        echo -n ${kscd[${c[i]}]}" "
    done)
    VBoxManage controlvm "${vmname}" keyboardputscancode ${scancode} 1>/dev/null 2>&1
}

# read variable kbspecial and send keystrokes by name,
# for example "CTRLprs c CTRLrls", and send to guest vm
function send_special() {
    scancode=""
    for keypress in ${kbspecial}; do
        scancode="${scancode}${kscd[${keypress}]}"" "
    done
    VBoxManage controlvm "${vmname}" keyboardputscancode ${scancode} 1>/dev/null 2>&1
}

function send_enter() {
    kbspecial="ENTER"
    send_special
}

function prompt_lang_utils() {
    prompt_lang
    prompt_utils
}

function prompt_lang() {
    # called after the virtual machine boots up
    printf '\n'"${highlight_color}"'Press enter when the Language window is ready.'"${default_color}"
    clear_input_buffer_then_read
    send_enter
}

function prompt_utils() {
    printf '\n'"${highlight_color}"'Press enter when the macOS Utilities window is ready.'"${default_color}"
    clear_input_buffer_then_read
    kbspecial='CTRLprs F2 CTRLrls u ENTER t ENTER'
    send_special
}

function select_reinstall() {
    printf '\n'"${highlight_color}"'Press enter when the macOS Utilities window is ready.'"${default_color}"
    clear_input_buffer_then_read
    kbspecial='DOWN DOWN TAB SPACE'
    send_special
}

function prompt_terminal_ready() {
    # called after the Utilities window is ready
    printf '\n'"${highlight_color}"'Press enter when the Terminal command prompt is ready.'"${default_color}"
    clear_input_buffer_then_read
}

function add_another_terminal() {
    # at least one terminal has to be open before calling this function
    kbspecial='CMDprs n CMDrls'
    send_special
    sleep 1
}

function if_num_of_terminals_lt_count_then_run_next_kbstring() {
    # sleep if "${count}" or more bash shells are active
    # when less than "${count}" are active, run "${next_string}"
    # "${count}" and "${next_string}" need to be passed as positional parameters
    local count="${1}"
    local next_kbstring="${2}"
    kbstring='while [ "$( ps -c | grep -c bash )" -ge '"${count}"' ]; do sleep 2; done; '"${next_kbstring}"
    send_keys
    send_enter
}

function cycle_through_terminal_windows() {
    kbspecial='CMDprs ` CMDrls'
    send_special
    sleep 1
}

function would_you_like_to_know_less() {
    if [ -z "$(less --version 2>/dev/null)" ]; then
        printf '  '"${highlight_color}${0} documentation${default_color}"'\n'
    else
        printf '  '"${highlight_color}${0} documentation | less -R${default_color}"'\n'
    fi
}

# command-line argument processing
stages='
    check_bash_version 
    check_gnu_coreutils_prefix 
    set_variables 
    welcome 
    check_dependencies 
    prompt_delete_existing_vm 
    create_vm 
    create_nvram_files 
    prepare_macos_installation_files
    create_macos_installation_files_viso 
    create_target_vdi 
    configure_vm 
    confirm_boot
    populate_virtual_disks 
    init_installer
    continue_installer
    fix_init_installer
    start_installer
    fix_preboot
    start_catalina
    delete_temporary_files
    
'
stages_without_newlines="$(printf "${stages}" | tr -d '\n')"
# every stage name must be preceded and followed by a space character
# for the command-line argument checking below to work
[ -z "${1}" ] && for stage in ${stages}; do ${stage}; done && exit
[ "${1}" = "documentation" ] && documentation && exit
for argument in $@; do
    [[ "${stages_without_newlines}" != *" ${argument} "* ]] &&
        echo "" &&
        echo "Can't parse one or more specified arguments. See documentation" &&
        echo "by entering the following command:" &&
        would_you_like_to_know_less && echo "" && echo "Available stages: ${stages}" && exit
done
check_bash_version
check_gnu_coreutils_prefix
set_variables
check_dependencies
for argument in "$@"; do ${argument}; done