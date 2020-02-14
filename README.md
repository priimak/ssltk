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

* Can be run in mode without asking any questions which can be done by passing
command line parameters.

* Pass `help` to the script to display help showing command line aguments

```
$ ./ssl-cert-maker.sh help
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
```

Below is example where we create new CA cert and another cert signed with this
newly created CA cert.

```
$ ./ssl-cert-maker.sh
Do you want to create:
	1) self signed certificate
	2) cert signed by CA cert
	3) signing CA cert
Please select one option: 2
Found following CA certificates that can be used for signing
	1) Create new CA cert
	2) /home/priimak/.ssl/ca/ca.Abba.crt
	3) /home/priimak/.ssl/ca/ca.Borg.crt
	4) /home/priimak/.ssl/ca/ca.Command_And_Control.crt
Please select one: 1

Common Name (CN) for a signing CA cert will be used as its unique identity
Please provide Common Name for this signing CA cert: White House

Every certificate has validity period defined in days from the moment
when it was created. Once cert is created validity period cannot be changed
How many days do you want the certificate to be valid for [1825]: 60
Generated password protected /home/priimak/.ssl/workspace/ca.White_House.pass.key key file
Generated password-less /home/priimak/.ssl/ca/ca.White_House.key key file

Generated CA signing cert /home/priimak/.ssl/ca/ca.White_House.crt file

New certificate will be created signed by ca.White_House.crt

Common Name (CN) in the certificate often has to match host name
if you are to use it to secure web server.
Please provide Common Name (CN) for this cert [localhost]: www.my.cool.site.com

Every certificate has validity period defined in days from the moment
when it was created. Once cert is created validity period cannot be changed
How many days do you want the certificate to be valid for [1825]: 30
Generating RSA private key, 2048 bit long modulus (2 primes)
....................................................................................+++++
...............................................................................................................................................+++++
e is 65537 (0x010001)

Certificate subject alt names is set to provided CN only
You can cange it by manually editing generated extention file
Do you want to edit extention file to add or change alt_names? [y/N]: 
Signature ok
subject=C = US, ST = California, L = San Francisco, O = Internet of All Things Ltd, OU = Command And Control, CN = www.my.cool.site.com
Getting CA Private Key

A new certificate and corresponding key were created and are available here

	/home/priimak/.ssl/certs/www.my.cool.site.com.crt
	/home/priimak/.ssl/certs/www.my.cool.site.com.key

This certificate was signed by

	/home/priimak/.ssl/ca/ca.White_House.crt
	/home/priimak/.ssl/ca/ca.White_House.key
```
