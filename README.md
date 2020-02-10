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
