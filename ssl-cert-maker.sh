#!/usr/bin/env zsh

ACCEPT_EXT_AS_IS=""

san_names=()
san_ips=()

function good_by() {
	print -u 2 "Exiting... Good by"
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
	local openssl_major_version=$(openssl version | awk '/OpenSSL/ { print $2 }' | awk -F. '{ print $1 }')
	local openssl_minor_version=$(openssl version | awk '/OpenSSL/ { print $2 }' | awk -F. '{ print $2 }')
	if [[ -z "$openssl_major_version" ]] || [[ -z "$openssl_minor_version" ]]; then
		print "Error: unable to determine OpenSSL version. Please check that you have OpenSSL installed"
		print "Found version: " $(openssl version)
		exit 1
	fi
	if [ $openssl_major_version -lt 1 ] || [ $openssl_minor_version -lt 1 ]; then
		print "Error: only OpenSSL version 1.1.* or greater are supported"
		print "Found version: " $(openssl version)
		exit 1
	fi

        which expect > /dev/null 
        if [ $? -ne 0 ]; then
                print "Error: comand line tool 'expect' is not installed." 
		install_expect
        fi
}

function prompt_for_main_action() {
	local cli_supplied_action=$1
	if [[ -z "$cli_supplied_action" ]]; then
		local create
		while true; do
			print -u 2 "Do you want to create:"
			print -u 2 "\t1) self signed certificate"
			print -u 2 "\t2) cert signed by CA cert"
			print -u 2 "\t3) signing CA cert"
			vared -p "Please select one option: " create
			if [[ "$create" =~ "[123]" ]]; then
				echo "$create"
				break
			else
				create=""
			fi
		done
	elif [[ "$cli_supplied_action" =~ "[123]" ]]; then
		echo "$cli_supplied_action"
	else
		print -u 2 "Error: Invalid main action requested"
		return 1
	fi
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
	local cli_cn=$1
        local cli_duration=$2

	local cn
        if [[ -z "$cli_cn" ]]; then
                cn=$(get_signing_cert_cn | tail -1)
        else
                cn=$cli_cn
        fi

        local days_valid
        if [[ -z "$cli_duration" ]]; then
                days_valid=$(get_validity_duration | tail -1)
        else
                days_valid=$cli_duration
        fi

	local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')
	if [[ ! -z "$cli_cn" ]] && [[ -f "$HOME/.ssl/ca/ca.$cert_file_base_name.crt" ]]; then
		print -u 2 "Error: CA certificate with this CN already exists"
		good_by
		return
	fi
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
                print -u 2 "\nGenerated CA signing cert $HOME/.ssl/ca/ca.$cert_file_base_name.crt file"
        else
                print -u 2 "\nError: Failed to generte $HOME/.ssl/ca/ca.$cert_file_base_name.crt file"
                return 1
        fi
	echo "ca.$cert_file_base_name"
}

function get_ca_cert() {
	local cli_ca_cn=$1
	if [[ ! -z "$cli_ca_cn" ]] ; then
		if [[ -f "$HOME/.ssl/ca/ca.$cli_ca_cn.crt" ]]; then
			echo "ca.$cli_ca_cn"
			return
		else
			print -u 2 "Error: Could not find CA cert for this CN $cli_ca_cn"
			return 1
		fi

	fi

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
	local cli_cn=$1
	local cli_duration=$2

	local cn
	if [[ -z "$cli_cn" ]]; then
		cn=$(get_cn | tail -1)
	else
		cn=$cli_cn
	fi

	local days_valid
	if [[ -z "$cli_duration" ]]; then
		days_valid=$(get_validity_duration | tail -1)
	else
		days_valid=$cli_duration
	fi
	local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')

	while true; do
		if [[ -f "$HOME/.ssl/certs/$cert_file_base_name.crt" ]]; then
			print "\nCertificate for this CN already exist $HOME/.ssl/certs/$cn.crt"
			if [[ ! -z "$cli_cn" ]]; then
				good_by
				break
			fi
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
EOF

	if [[ -z "$san_names" ]] && [[ -z "$san_ips" ]]; then
		echo "DNS.1 = $cn" >> $HOME/.ssl/workspace/ext

		if [[ -z "$ACCEPT_EXT_AS_IS" ]]; then
			print "\nCertificate subject alt names is set to provided CN only"
			print "You can cange it by manually editing generated extention file"
			if yes_or_No "Do you want to edit extention file to add or change alt_names?"; then
				vim $HOME/.ssl/workspace/ext
			fi
		fi

	else
		if [[ ! -z "$san_names" ]]; then
	        	for i in {1..${#san_names}}; do
                		echo "DNS.$i = $san_names[$i]" >> $HOME/.ssl/workspace/ext
        		done
		fi
		if [[ ! -z "$san_ips" ]]; then
			for i in {1..${#san_ips}}; do
				echo "IP.$i = $san_ips[$i]" >> $HOME/.ssl/workspace/ext
			done
		fi
	fi

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
	local cli_ca_cn=$1
	local cli_cn=$2
	local cli_duration=$3

	local res
	res=$(get_ca_cert $cli_ca_cn) || good_by
	local ca_base_name=$(echo $res | tail -1)

	print "\nNew certificate will be created signed by $ca_base_name.crt"
	
	local cn
	if [[ -z "$cli_cn" ]]; then
		cn=$(get_cn | tail -1)
	else
		ACCEPT_EXT_AS_IS="true"
		cn=$cli_cn
	fi

	local days_valid
	if [[ -z "$cli_duration" ]]; then
		days_valid=$(get_validity_duration | tail -1)
	else
		days_valid=$cli_duration
	fi
	
        local cert_file_base_name=$(echo $cn | tr ' ' '_' | tr "\t" '_')

        while true; do
                if [[ -f "$HOME/.ssl/certs/$cert_file_base_name.crt" ]]; then
                        print "\nCertificate for this CN already exist $HOME/.ssl/certs/$cn.crt"
			if [[ ! -z "$cli_cn" ]]; then
				good_by
			elif yes_or_No "Do you want to override it"; then
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

function parse_cli_args_for_signed_cert() {
	for i in $@; do
		if [[ "$i" =~ "^--subjectAltName=.+$" ]]; then
			local san=${i[18,1000]}
			if [[ "$san" =~ ^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
				san_ips+=$san
			else
				san_names+=$san
			fi
		fi
	done
}

check_prereq
mkdir -p ~/.ssl/ca
mkdir -p ~/.ssl/certs

cli_action=$1
if [[ -z "$cli_action" ]]; then
	action=$(prompt_for_main_action $cli_action) || good_by
else
	action=$cli_action
fi
case $action in
	1|new_self_signed_cert)
		cli_cn=$2
		cli_days_valid=$3
		create_self_signed_cert $cli_cn $cli_days_valid
		;;

	2|new_signed_cert)
		parse_cli_args_for_signed_cert $@
		cli_ca_cn=$2
		cli_cn=$3
		cli_days_valid=$4
		create_cert_signed_by_ca_cert $cli_ca_cn $cli_cn $cli_days_valid
		;;

	3|new_ca_cert)
                cli_cn=$2
                cli_days_valid=$3
		create_new_ca_signing_cert $cli_cn $cli_days_valid > /dev/null
		;;

	help)
		cat<<EOF
Make ssl certificates. Run it without any options and you will be
prompted with questions needed to create ssl certs or or supply
it with command line parameters as shown below to create certs in
unsupervised fashion.

    ssl-cert-maker.sh new_self_signed_cert <cn> <days_valid>
    ssl-cert-maker.sh new_signed_cert <ca_cn> <cn> <days_valid> [--subjectAltName=<name_or_ip_addr> ...]
    ssl-cert-maker.sh new_ca_cert <cn> <days_valid>

When creating new signed certifcate in attanded mode Subject
Altrenative Name (SAN) is set to provided CN unless --subjectAltName=
command line parameters are used. If they SANs are provided on
command line then only the explictly provided values will in the
certificate. Note that script can correctly distinguish between ip
addresses and names passed as SANs.

EOF
		;;
esac
