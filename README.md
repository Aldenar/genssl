# GenSSL
A lightweight wrapper script around the brilliant [acme-tiny.py](https://github.com/diafygi/acme-tiny) script, meant to simplify generation and automatic maintenance of Lets Encrypt SSL certificates for multitude of independent domains on a single machine.

## What this does
This script is useful if all you want is to generate a SSL certificate for 1 or more domains, and do not like the bulky certbot.

Ideal solution for lower-powered machines like Raspberry Pi!

## What this does not
This script supports only simple HTTP challenges - Meaning no DNS challange, and no wildcard certificates, sorry!

## Requirements
This script contains only the absolutely necessary to generate a certificate.

As such, the user has to have an already configured webserver and a HTTP-Reachable (port 80) domain without authentication.

## Usage
The basic usage is simple:
1. Download the script
2. Make it executable - `chmod +x genssl.sh`
3. Create a file with a list of domains to be included in the certificate (1 per line)
4. Run `genssl.sh *input_file*`

## Webserver settings
As the script is meant to be ran automatically (In cron etc), it stores all the HTTP challanges in a central directory (`/tmp/challenges/` by default)

As such, it requires the user to add a special snippet of configuration to their webserver.

To simplify this, it prints two configuration snippets to add to target domains' webserver configuration - One for Apache v2.4+ and one for Nginx.

## Certificate renewal
If ran for an already existing certificate, the script checks its expiration. If there's less than 14 days until its expiration (the default), it attempts to regenerate it. Otherwise, it simply exits.

To enable automatic renewal, the script may be run in cron. 

Example /etc/cron.d/genssl:
```
3 0 * * 1,3,5,7 root for cert in /etc/ssl/letsencrypt/*/domains.txt; do /path/to/genssl.sh "$cert" >> /var/log/genssl.log; done
```

## Copyright
In short - I don't care what you do with the script. Modify it, share it, spam your friends with it.

I made it to simplify my own life, and am happy if it helps even a single person more.
