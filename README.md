SSL Tool Kit (SSLTK)
====================

User-friendly command line utilities for managing ssl certificates.

ssl-cert-maker.sh
-----------------

Command line utility for creating self and properly signed
ssl certificates using sensible defaults. Just run this utility
and you will be prompted with set of questions that you need to answer
in order to create signed certificate. 

```
curl -LO https://raw.githubusercontent.com/priimak/ssltk/master/ssl-cert-maker.sh && \
  chmod 755 ssl-cert-maker.sh
``` 

* This script is written in zsh and thus require it to be installed.
Internally it uses `openssl` and `expect` command line tools.

* The script was tested under ubuntu 18.04LTS.

* Certificates will be written under `~/.ssl/certs` and CA signing certs
under `~/.ssl/ca`
 
* When creating properly signed certificates `ssl-cert-maker.sh` can 
create Certeficate Authority (CA) signing certificates or reuse 
existing ones.

* There are only two options that user can set on certificates, number of
days cert is valid for (default value is 5 years) and a Common Name (CN).
For self signed certs default value of CN is "`localhost`". No default CN
is provided for CA certs.

* When creating certificates signed with CA certs Subject Alt Names section
will be created with just one DNS entry containing provided CN value.

Below is example where we create new CA cert and another cert signed with this
newly created CA cert.

```
$ ./ssl-cert-maker.sh
Do you want to create cert (1) self signed or (2) signed by CA cert: 2
Found following CA certificates that can be used for signing
	1) Create new CA cert
	2) /home/ubuntu/.ssl/ca/ca.Abba.crt
	3) /home/ubuntu/.ssl/ca/ca.Borg.crt
	4) /home/ubuntu/.ssl/ca/ca.Command_And_Control.crt
Please select one: 1

Common Name (CN) for a signing CA cert will be used as its unique identity
Please provide Common Name for this signing CA cert: White House 

Every certificate has validity period defined in days from the moment
when it was created. Once cert is created validity period cannot be changed
How many days do you want the certificate to be valid for [1825]: 60 
Generated password protected /home/ubuntu/.ssl/workspace/ca.White_House.pass.key key file
Generated password-less /home/ubuntu/.ssl/ca/ca.White_House.key key file
Generated CA signing cert /home/ubuntu/.ssl/ca/ca.White_House.crt file

New certificate will be created signed by ca.White_House.crt

Common Name (CN) in the certificate often has to match host name
if you are to use it to secure web server.
Please provide Common Name (CN) for this cert [localhost]: www.my.cool.site.com

Every certificate has validity period defined in days from the moment
when it was created. Once cert is created validity period cannot be changed
How many days do you want the certificate to be valid for [1825]: 30
ca_base_name ca.White_House
cert_file_base_name www.my.cool.site.com
cn www.my.cool.site.com
Generating RSA private key, 2048 bit long modulus (2 primes)
.............+++++
.............+++++
e is 65537 (0x010001)
Signature ok
subject=C = US, ST = California, L = San Francisco, O = Internet of All Things Ltd, OU = Command And Control, CN = www.my.cool.site.com
Getting CA Private Key

A new certificate and corresponding key were created and are available here

	/home/ubuntu/.ssl/certs/www.my.cool.site.com.crt
	/home/ubuntu/.ssl/certs/www.my.cool.site.com.key

This certificate was signed by

	/home/ubuntu/.ssl/ca/ca.White_House.crt
	/home/ubuntu/.ssl/ca/ca.White_House.key
```
