#!/bin/bash

APP_VM="zsvpn-client"
PROXY_VM="sys-zsvpn"
TEMPLATE="debian-10"
ZSVPN_VERS="2.1.8"
ZSVPN_ZIP="zsvpn_$ZSVPN_VERS.zip"
ZSVPN_TAR="zsvpn-$ZSVPN_VERS.tar.gz"
ZSVPN_LINK="https://zsvpn.com/dl/linux/$ZSVPN_ZIP"
ZSVPN_HASH="6802d6599105313ba04fadf672d9d937dc31bd383dbc54a3b789d07128cc354c"
QUBES_VPN_SUPPORT_LINK="https://github.com/tasket/Qubes-vpn-support.git"
CONFIG_FILE="vpn-client.conf"
VPN_FOLDER_PATH="/rw/config/vpn"

#############################################################################
# [AppVM]
#############################################################################

create_and_start_app_vm() {
  # Create a $TEMPLATE based AppVM.
  qvm-create $APP_VM --class AppVM --template $TEMPLATE --label yellow
  # Start AppVM.
  qvm-start $APP_VM
}

get_zsvpn() {
  if ! qvm-run --quiet $APP_VM "wget $ZSVPN_LINK"; then
    print_error_and_exit "Couldn't download $ZSVPN_ZIP from $ZSVPN_LINK."
  fi
  
  hash=$(qvm-run --pass-io $APP_VM "openssl dgst -sha3-256 $ZSVPN_ZIP" \
    | awk '{print $2}')
  if [ "$hash" != "$ZSVPN_HASH" ]; then
    print_error_and_exit "Detected illegal file hash ($hash)."
  fi
  
  # Unzip $ZSVPN_ZIP.
  qvm-run --quiet $APP_VM "unzip -d zsvpn $ZSVPN_ZIP"
  
  # Untar $ZSVPN_TAR.
  qvm-run --quiet $APP_VM "tar xf zsvpn/$ZSVPN_TAR -C zsvpn --strip 1"
}

start_zsvpn() {
  qvm-run --quiet $APP_VM 'sudo zsvpn/zsvpn'& # Run in background.
}

parse_openvpn_args() {
  if ! openvpn_output=$(qvm-run --pass-io $APP_VM \
    'ps aux | grep "sudo /usr/sbin/openvpn" | grep -v grep'); then
    print_error_and_exit "Couldn't find openvpn process."
  fi
  
  # Parse --config arg (default.ovpn).
  config_arg=$(echo $openvpn_output | awk '{print $14}')
  
  # Parse --cipher arg (typically AES-128-CPC).
  cipher_arg=$(echo $openvpn_output | awk '{print $16}')
  
  # Parse --remote IP arg [I-II].
  remote_ip_arg=$(echo $openvpn_output | awk '{print $18}')
  
  # Parse --remote PORT arg [II-II].
  remote_port_arg=$(echo $openvpn_output | awk '{print $19}')
  
  # Parse --proto arg.
  proto_arg=$(echo $openvpn_output | awk '{print $21}')
  
  # Parse --ca arg (ca.crt).
  ca_arg=$(echo $openvpn_output | awk '{print $23}')
  ca_file=$(basename $ca_arg)
  
  # Parse --cert arg (user.crt).
  cert_arg=$(echo $openvpn_output | awk '{print $25}')
  cert_file=$(basename $cert_arg)
  
  # Parse --key arg (user.key).
  key_arg=$(echo $openvpn_output | awk '{print $27}')
  key_file=$(basename $key_arg)
}

#############################################################################
# [dom0]
#############################################################################

transfer_openvpn_files_to_dom0() {
  # E.g. default.ovpn
  qvm-run --pass-io $APP_VM "cat $config_arg" > $CONFIG_FILE
  # E.g. ca.crt.
  qvm-run --pass-io $APP_VM "cat $ca_arg" > $ca_file
  # E.g. user.crt.
  qvm-run --pass-io $APP_VM "cat $cert_arg" > $cert_file
  # E.g. user.key.
  qvm-run --pass-io $APP_VM "cat $key_arg" > $key_file
}

modify_openvpn_config_file() {
  # We need to modify the $CONFIG_FILE to satisfy Qubes-openvpn-support.
  echo "" >> $CONFIG_FILE
  echo "remote $remote_ip_arg $remote_port_arg" >> $CONFIG_FILE
  echo "proto $proto_arg" >> $CONFIG_FILE
  echo "cipher $cipher_arg" >> $CONFIG_FILE
  echo "ca $ca_file" >> $CONFIG_FILE
  echo "cert $cert_file" >> $CONFIG_FILE
  echo "key $key_file" >> $CONFIG_FILE
  echo "auth-nocache" >> $CONFIG_FILE
}

#############################################################################
# [ProxyVM]
#############################################################################

create_and_start_proxy_vm() {
  # Create a ProxyVM (based on the default TemplateVM).
  qvm-create $PROXY_VM --class AppVM --label purple
  # Enable networking capabilities. 
  qvm-prefs $PROXY_VM provides_network True
  # Enable autostart.
  qvm-prefs $PROXY_VM autostart True
  # Enable vpn-handler service.
  qvm-features $PROXY_VM service.vpn-handler-openvpn True
  # Start ProxyVM.
  qvm-start $PROXY_VM
}

get_qubes_vpn_support() {
  # Clone Qubes-vpn-support GitHub repository.
  if ! qvm-run --quiet $PROXY_VM "git clone $QUBES_VPN_SUPPORT_LINK"; then
    print_error_and_exit "Couldn't clone $QUBES_VPN_SUPPORT_LINK."
  fi
  
  qvm-run --quiet $PROXY_VM "cd Qubes-vpn-support && sudo bash ./install"
}

transfer_openvpn_files_to_proxy_vm() {
  qvm-run --quiet $PROXY_VM "sudo mkdir -p $VPN_FOLDER_PATH"
  
  cat $CONFIG_FILE | qvm-run --pass-io $PROXY_VM \
    "sudo sh -c 'cat > $VPN_FOLDER_PATH/$CONFIG_FILE'"
  cat $ca_file | qvm-run --pass-io $PROXY_VM \
    "sudo sh -c 'cat > $VPN_FOLDER_PATH/$ca_file'"
  cat $cert_file | qvm-run --pass-io $PROXY_VM \
    "sudo sh -c 'cat > $VPN_FOLDER_PATH/$cert_file'"
  cat $key_file | qvm-run --pass-io $PROXY_VM \
    "sudo sh -c 'cat > $VPN_FOLDER_PATH/$key_file'"
}

restart_proxy_vm() {
  qvm-shutdown --wait $PROXY_VM && qvm-start $PROXY_VM
}

#############################################################################
# [Utils]
#############################################################################

print_error_and_exit() {
  printf "[ERROR] $1\n" >&2
  exit 1
}

print_info() {
  printf "[INFO] $1\n"
}

remove_vm() {
  qvm-kill $1 &> /dev/null 
  qvm-remove --force $1 &> /dev/null
}

cleanup_dom0() {
  rm $CONFIG_FILE 2> /dev/null
  rm $ca_file $cert_file $key_file 2> /dev/null
}

cleanup_vms() {
  remove_vm $APP_VM
  remove_vm $PROXY_VM
}

#############################################################################
# [Traps]
#############################################################################

interrupt_trap() {
  # We're just her to trigger our exit trap.
  print_info "Cancelling..."
  exit 1
}

exit_trap() {
  cleanup_dom0
  if [ $? -eq 1 ] ; then
    # Something went wrong.
    print_info "Cleaning up..."
    cleanup_vms
  fi
}

#############################################################################
# [Entry Point]
#############################################################################

# Don't continue if $APP_VM is already present.
if qvm-ls $APP_VM &> /dev/null ; then
  print_info "AppVM ($APP_VM) already present."
  print_info "Cancelling..."
  exit 1
fi
  
# Don't continue if $PROXY_VM is already present.
if qvm-ls $PROXY_VM &> /dev/null ; then
  print_info "ProxyVM ($PROXY_VM) already present."
  print_info "Cancelling..."
  exit 1
fi

# Register trap handlers.
trap interrupt_trap INT
trap exit_trap EXIT

print_info "Creating and starting temporary AppVM ($APP_VM)."
create_and_start_app_vm

print_info "Downloading, verifying, and unpacking $ZSVPN_ZIP...";
print_info "...this may take some time depending on your internet connection."
get_zsvpn

print_info "Starting VPN client (zsvpn).";
start_zsvpn

# Wait for user to login and connect.
read -p "Press any key to continue..."

print_info "Parsing OpenVPN's command line arguments."
parse_openvpn_args

print_info "Transfering OpenVPN files to dom0."
transfer_openvpn_files_to_dom0

print_info "Modifying $CONFIG_FILE."
modify_openvpn_config_file

print_info "Shutting down and removing $APP_VM."
remove_vm $APP_VM

print_info "Creating and starting ProxyVM ($PROXY_VM)."
create_and_start_proxy_vm

print_info "Downloading and installing Qubes-vpn-support."
get_qubes_vpn_support

print_info "Transfering OpenVPN files to $PROXY_VM."
transfer_openvpn_files_to_proxy_vm

print_info "Restarting $PROXY_VM."
restart_proxy_vm

print_info "Done, you should soon see a 'LINK IS UP' pupup notification."
print_info "Have fun with your new $PROXY_VM ProxyVM :)"

