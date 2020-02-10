#!/usr/bin/env zsh

set -e

function good_by() {
	print -u 2 "Exiting... Good by;"
	exit 1
}

function get_install_tool() {
	print -u 2 "a>$a"
	which apt-get > /dev/null
	if [ $? -eq 0 ]; then
		echo "apt-get"
		return 0
	fi
	
	which yum > /dev/null
	if [ $? -eq 0 ]; then
		echo "yum"
		return 0
	fi

	print -u 2 "Error: unable to find either apt-get or yum to install required application"
	return 1
}

function install_expect() {
	local install_tool
	if Yes_or_no "Do you want to install 'expect'"; then
		install_tool=$(get_install_tool) || good_by
		sudo $install_tool -y install expect
		if [ $? -ne 0 ]; then
			print -u 2 "Error: failed to install 'expect'."
			exit 1
		fi
	else
		good_by
	fi
}

function install_openssl() {
	local install_tool
	if Yes_or_no "Do you want to install 'openssl'"; then
		install_tool=$(get_install_tool) || good_by
		case "$install_tool" in
			"apt-get")
				sudo apt-get install -y openssl
				;;
			"yum")
				sudo yum -y install mod_ssl
				;;
		esac
		if [ $? -ne 0 ]; then
			print "Error: failed to install 'openssl'."
			exit 1
		fi
	else
		good_by
	fi
}

function check_prereq() {
	which openssl > /dev/null 
	if [ $? -ne 0 ]; then
		print "Error: command line tool 'openssl' is not installed."
		install_openssl
	fi

        which expect > /dev/null 
        if [ $? -ne 0 ]; then
                print "Error: comand line tool 'expect' is not installed." 
		install_expect
        fi
}

function prompt_for_main_action() {
	local create
	while true; do
		vared -p "Do you want to create cert (1) self signed or (2) signed by CA cert: " create
		if [[ "$create" =~ "[12]" ]]; then
			echo "$create"
			break
		else
			create=""
		fi
	done
}

function ask_for_positive_number() {
	local prompt=$1
	local def_value=$2
	local ans=
	while true; do
		vared -p "$prompt [$def_value]: " ans
		if [[ -z "$ans" ]]; then
			echo "$def_value"
			break
		fi
		if [[ "$ans" =~ "^[123456789][0123456789]*$" ]]; then
			echo $ans
			break
		else
			ans=
		fi
	done
}

function yes_or_no() {
        local prompt=$1
	local default_answer=$2
        local ans
        while true; do
                vared -p "$prompt: " ans
                if [[ -z "$ans" ]]; then
                        ans="$default_answer"
                fi
                if [[ "$ans" =~ "^(y|Y|yes)$" ]]; then
                        return 0
                fi
                if [[ "$ans" =~ "^(n|N|no)$" ]]; then
                        return 1
                fi
                ans=
        done
}

function Yes_or_no() {
	yes_or_no "$1 [Y/n]" "yes"
}

function yes_or_No() {
        yes_or_no "$1 [y/N]" "no"
	return $?
}

function remove_existing_cert() {
	local cert_file_base_name=$1
	[[ -f $HOME/.ssl/certs/$cert_file_base_name.crt ]] && rm -f $HOME/.ssl/certs/$cert_file_base_name.crt
	[[ -f $HOME/.ssl/certs/$cert_file_base_name.key ]] && rm -f $HOME/.ssl/certs/$cert_file_base_name.key
}

function do_create_self_signed_cert() {
	local cert_file_base_name=$1
	local cn=$2
	local days_valid=$3
	openssl req -x509 -nodes -keyout $HOME/.ssl/certs/$cert_file_base_name.key \
		-out $HOME/.ssl/certs/$cert_file_base_name.crt \
		-subj "/CN=$cn" -sha256 -days $days_valid
}

function get_cn() {
	local cn
        print -u 2 "\nCommon Name (CN) in the certificate often has to match host name"
        print -u 2 "if you are to use it to secure web server."
        vared -p "Please provide Common Name (CN) for this cert [localhost]: " cn
        if [[ -z "$cn" ]]; then
                cn="localhost"
        fi
	echo "$cn"
	return
}

function get_signing_cert_cn() {
	local cn
	print -u 2 "\nCommon Name (CN) for a signing CA cert will be used as its unique identity"
	while true; do
		vared -p "Please provide Common Name for this signing CA cert: " cn
		local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')
		if [[ -z $cert_file_base_name ]]; then
			cn=
		elif [[ -f "$HOME/.ssl/ca/ca.$cert_file_base_name.crt" ]]; then
			print -u 2 "\nError: certificate file $HOME/.ssl/ca/ca.$cert_file_base_name.crt already exist. Please try again"
			cn=
		else
			echo "$cn"
			break
		fi
	done
}

function get_validity_duration() {
	print -u 2 "\nEvery certificate has validity period defined in days from the moment"
        print -u 2 "when it was created. Once cert is created validity period cannot be changed"
        ask_for_positive_number "How many days do you want the certificate to be valid for" "1825"
}

function create_new_ca_signing_cert() {
	local cn=$(get_signing_cert_cn | tail -1)
        local days_valid=$(get_validity_duration | tail -1)
	local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')
	rm -rf $HOME/.ssl/workspace
	mkdir -p $HOME/.ssl/workspace
	cat<<EOF | expect -f -
spawn openssl genrsa -des3 -out $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key 2048

expect "Enter pass phrase for $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key:"

send -- "1234\r"

expect "Verifying - Enter pass phrase for $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key:"

send -- "1234\r"

expect eof
EOF
	if [[ -f "$HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key" ]]; then
		print -u 2 "Generated password protected $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key key file"
	else
		print -u 2 "Error: Failed to generate $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key file"
		return 1
	fi

	cat<<EOF | expect -f -
spawn openssl rsa -in $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key -out $HOME/.ssl/ca/ca.$cert_file_base_name.key

expect "Enter pass phrase for $HOME/.ssl/workspace/ca.$cert_file_base_name.pass.key:"

send -- "1234\r"

expect eof
EOF
	if [[ -f "$HOME/.ssl/ca/ca.$cert_file_base_name.key" ]]; then
		print -u 2 "Generated password-less $HOME/.ssl/ca/ca.$cert_file_base_name.key key file"
	else
		print -u 2 "Error: Failed to generted $HOME/.ssl/ca/ca.$cert_file_base_name.key file"
		return 1
	fi

	# generate ca cert
	# -subj "/C=US/ST=California/L=San Francisco/O=Internet of All Things Ltd/OU=Command And Control/CN=$cn"
	openssl req -x509 -new -nodes -key $HOME/.ssl/ca/ca.$cert_file_base_name.key \
		-sha256 -days $days_valid -out $HOME/.ssl/ca/ca.$cert_file_base_name.crt \
		-subj "/C=US/ST=California/L=San Francisco/O=Internet of All Things Ltd/OU=Command And Control/CN=$cn"

        if [[ -f "$HOME/.ssl/ca/ca.$cert_file_base_name.crt" ]]; then
                print -u 2 "Generated CA signing cert $HOME/.ssl/ca/ca.$cert_file_base_name.crt file"
        else
                print -u 2 "Error: Failed to generte $HOME/.ssl/ca/ca.$cert_file_base_name.crt file"
                return 1
        fi
	echo "ca.$cert_file_base_name"
}

function get_ca_cert() {
	setopt null_glob
	local ca_certs=("Create new CA cert" $HOME/.ssl/ca/ca.*.crt)
	if [ "${#ca_certs[@]}" -eq 0 ]; then
		if Yes_or_no "There are no CA certificates are available. Do you want to create one?"; then
			create_new_ca_signing_cert || return 1
		else
			return 1
		fi
	else
		local ca_index
		print -u 2 "Found following CA certificates that can be used for signing"
		while true; do
			for i in {1..${#ca_certs}}; do
				print -u 2 "\t$i) ${ca_certs[i]}"
			done
			vared -p "Please select one: " ca_index
			if [[ -z "$ca_index" ]]; then
				ca_index="0"
			fi
			if (( $ca_index > 0)) && (( $ca_index <= ${#ca_certs} )); then
				if (( $ca_index == 1 )); then
					create_new_ca_signing_cert
					break
				else
					basename ${ca_certs[$ca_index]} | sed 's/.crt$//'
					break
				fi
			else
				ca_index=
			fi
		done
		
	fi
}

function create_self_signed_cert() {
	local cn=$(get_cn | tail -1)
	local days_valid=$(get_validity_duration | tail -1)
	local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')

	while true; do
		if [[ -f "$HOME/.ssl/certs/$cert_file_base_name.crt" ]]; then
			print "\nCertificate for this CN already exist $HOME/.ssl/certs/$cn.crt"
			if yes_or_No "Do you want to override it"; then
				remove_existing_cert $cert_file_base_name
				do_create_self_signed_cert $cert_file_base_name $cn $days_valid
				break
			elif Yes_or_no "Do you want to change CN"; then
				cn=$(get_cn | tail -1)
				cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')
			else
				print "Certificate will not be created. Good by."
				exit 1
			fi
		else
			remove_existing_cert $cert_file_base_name
			do_create_self_signed_cert $cert_file_base_name $cn $days_valid
			break
		fi
	done

	print "\nA new self signed certificate and corresponding key were created and\nare available here\n"
	print "\t$HOME/.ssl/certs/$cert_file_base_name.crt\n\t$HOME/.ssl/certs/$cert_file_base_name.key"
}

function do_create_cert_signed_by_ca_cert() {
	local ca_base_name=$1
	local cert_file_base_name=$2
	local cn=$3
	local days_valid=$4

	echo "ca_base_name $ca_base_name"
	echo "cert_file_base_name $cert_file_base_name"
	echo "cn $cn"

        rm -rf $HOME/.ssl/workspace
        mkdir -p $HOME/.ssl/workspace

	# make certificate key 
	openssl genrsa -out $HOME/.ssl/certs/$cert_file_base_name.key 2048


	# make certificate signing request (csr)
	openssl req -new -key $HOME/.ssl/certs/$cert_file_base_name.key \
		-out $HOME/.ssl/workspace/$cert_file_base_name.csr \
		-subj "/C=US/ST=California/L=San Francisco/O=Internet of All Things Ltd/OU=Command And Control/CN=$cn"

	cat <<EOF > $HOME/.ssl/workspace/ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $cn
EOF

	openssl x509 -req -in $HOME/.ssl/workspace/$cert_file_base_name.csr \
		-CA $HOME/.ssl/ca/$ca_base_name.crt -CAkey $HOME/.ssl/ca/$ca_base_name.key -CAcreateserial \
		--out $HOME/.ssl/certs/$cert_file_base_name.crt -days $days_valid -sha256 \
		-extfile $HOME/.ssl/workspace/ext

	if [[ -f "$HOME/.ssl/certs/$cert_file_base_name.crt" ]]; then
		print "\nA new certificate and corresponding key were created and are available here\n"
		print "\t$HOME/.ssl/certs/$cert_file_base_name.crt"
		print "\t$HOME/.ssl/certs/$cert_file_base_name.key"
		print "\nThis certificate was signed by\n"
		print "\t$HOME/.ssl/ca/$ca_base_name.crt"
		print "\t$HOME/.ssl/ca/$ca_base_name.key"
	else
		print -u 2 "Error: failed to create $HOME/.ssl/certs/$cert_file_base_name.crt"
	fi
}

function create_cert_signed_by_ca_cert() {
	local res
	res=$(get_ca_cert) || good_by
	local ca_base_name=$(echo $res | tail -1)

	print "\nNew certificate will be created signed by $ca_base_name.crt"
        local cn=$(get_cn | tail -1)
        local days_valid=$(get_validity_duration | tail -1)
        local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')

        while true; do
                if [[ -f "$HOME/.ssl/certs/$cert_file_base_name.crt" ]]; then
                        print "\nCertificate for this CN already exist $HOME/.ssl/certs/$cn.crt"
                        if yes_or_No "Do you want to override it"; then
                                remove_existing_cert $cert_file_base_name
                                do_create_cert_signed_by_ca_cert $ca_base_name $cert_file_base_name $cn $days_valid
                                break
                        elif Yes_or_no "Do you want to change CN"; then
                                cn=$(get_cn | tail -1)
                                cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')
                        else
                                print "Certificate will not be created. Good by."
                                exit 1
                        fi
                else
                        remove_existing_cert $cert_file_base_name
                        do_create_cert_signed_by_ca_cert $ca_base_name $cert_file_base_name $cn $days_valid
                        break
                fi
        done
}

check_prereq
mkdir -p ~/.ssl/ca
mkdir -p ~/.ssl/certs

action=$(prompt_for_main_action)
case $action in
	"1")
		create_self_signed_cert
		;;
	"2")
		create_cert_signed_by_ca_cert
		;;
esac
