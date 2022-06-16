#/bin/bash

opt_f=0
mindiff="14" #In days
self="$( basename $0 | rev | cut -d "." -f 2- | rev)"
acme_tiny_dir=/usr/local/sbin/acme-tiny/
acme_tiny_script=/usr/local/sbin/acme-tiny/acme_tiny.py
challenge_dir=/tmp/challenges
le_ssl_dir=/etc/ssl/letsencrypt
first_run=0
error=0

get_help(){
        echo "Usage: $self [-f] domains.txt"
        echo -e "\t-f: (When regenerating certificate) force regeneration despite certificate not expiring yet"
        return 0
}

http_challenge_check ()
{
    if [ -z "$1" ]; then
        echo "Requires target domain URL";
        return 1;
    fi;
    if ! [ -d "/tmp/challenges" ]; then
        mkdir "/tmp/challenges";
    fi;
    url="$1";
    file=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5);
    cont=$(echo $file | md5sum | cut -d " " -f 1);
    echo "$cont" > "${challenge_dir}/${file}";
    res=$(curl -L "http://${url}/.well-known/acme-challenge/${file}" 2>/dev/null);
    if [ -e "${challenge_dir}/${file}" ]; then
        rm "${challenge_dir}/${file}"
    fi
    if [ "$res" == "$cont" ]; then
        return 0
    else
        return 1
    fi;
}

update_acme_tiny(){
        if [ -d "$acme_tiny_dir" ]
        then
            oldir="$(pwd)"
            cd "$acme_tiny_dir"
            git pull &>/dev/null
            rc=$?
            cd "$oldir"
            return $rc
        else
            echo "acme_tiny not found, cloning!"
            git clone https://github.com/diafygi/acme-tiny $acme_tiny_dir
            return $?
        fi
}

webservers_help(){
    echo "Please add the following into your webserver configuration and press enter"
    echo -e "\nApache:"
    echo "Alias /.well-known/acme-challenge/ ${challenge_dir}"
    echo "<Directory ${challenge_dir}/>"
    echo "  Options FollowSymLinks"
    echo "  Require all granted"
    echo "</Directory>"
    echo ""
    echo "Nginx:"
    echo "location ^~ /.well-known/acme-challenge/ {"
    echo "  alias ${challenge_dir}/;"
    echo "  default_type text/html;"
    echo "}"
    echo ""
    read -p "Press enter to continue"
    
}

generate_csr(){
    dest_dir="$1"
    target_file="$2"
    target_domain="$(head -n 1 $target_file)"

    echo "Generating new domain key!" >&2
    openssl genrsa 4096 > "$dest_dir/domain.key"
    domain_key="$dest_dir/domain.key"

    subjects=$(cat $target_file | tr "\n" " " | sed -E -e 's#^[[:space:]]##g' -e 's#[[:space:]]$##g' -e 's#[[:space:]]+#, DNS:#g' -e 's#^(.)#DNS:\1#')
    csr_file="${dest_dir}/domain.csr"
    openssl req -new -sha256 -key "$domain_key" -subj "/" -addext "subjectAltName = ${subjects}" > "$csr_file"
    if [ $? -ne 0 ]
    then
        echo "OpenSSL returned non-zero, please check CSR file - $csr_file" >&2
        return 1
    fi

    echo "$csr_file"
    return 0

}

generate_crt() {
    dest_dir="$1"
    account_key="$2"
    csr="$3"

    $acme_tiny_script --account-key "$account_key" --csr "$csr" --acme-dir "$challenge_dir" --disable-check > "${dest_dir}/domain.crt"
    return $?
}

[[ -e "/etc/default/$self" ]] && source "/etc/default/$self"

if [ $UID -ne 0 ]
then
        echo "This program must be run as superuser, exitting!"
        exit 1
fi

if [ -z "$(which openssl)" ]
then
        echo "OpenSSL is required to run this script, please install it and try again!"
        exit 1
fi

if [ -z "$(which diff)" ]
then
        echo "Diff is required to run this script, please install diffutils and try again!"
        exit 1
fi


if [ "$#" -lt 1 ]
then
        get_help
        exit 1
fi

for arg in $@
do
    [[ "$arg" == "-f" ]] && opt_f=1
done

if ! update_acme_tiny
then
        echo "Something went wrong during acme_tiny update - check $acme_tiny dir!"
        exit 1
fi

if [ ! -d "$challenge_dir" ]
then
        echo "Challenge dir ($challenge_dir) not found, creating!"
        mkdir -p "$challenge_dir"
fi

if [ ! -d "$le_ssl_dir" ]
then
        echo "Certificate directory ($le_ssl_dir) not found, creating!"
        mkdir -p "$le_ssl_dir"
        chmod 700 "$le_ssl_dir"
        first_run=1
fi

target_file="${@: -1}"

if [ ! -f "$target_file" ]
then
        echo "Input file \"$1\" not found!"
        exit 1
fi


if [ "$error" -ne 0 ]
then
    exit 1
fi

primary_domain="$(head -n 1 $target_file)"
destination_dir="$le_ssl_dir/$primary_domain"

if [ ! -d "$destination_dir" ]
then
        first_run=1
        mkdir "$destination_dir"
fi

if [ ! -f "$destination_dir/domains.txt" ] || [ ! -f "$destination_dir/domain.crt" ]
then
    first_run=1
fi

if [ "$first_run" -eq 1 ]
then
        webservers_help
        for domain in $(cat "$target_file")
        do
            echo "Prefliht checking domain $domain"
            if ! http_challenge_check "$domain";
            then
                echo "Preflight HTTP challenge failed for \"${domain}\""
                error=1
            fi
        done
        if [[ "$error" -eq 1 ]]
        then
            echo "One (Or more) preflight checks failed, exitting!"
            exit 1
        fi
        echo "Domain cert not yet found, attempting to generate!"
        cp "$target_file" "${destination_dir}/domains.txt"
        if [ ! -f "${destination_dir}/account.key" ]; then
            echo "Generating Lets Encrypt account key!"
            openssl genrsa 4096 > "$destination_dir/account.key"
        fi
        le_account_key="${destination_dir}/account.key"
        echo "Generating CSR"
        csr=$(generate_csr "$destination_dir" "$target_file")
        echo "Attempting to generate the certificate!"
        generate_crt "$destination_dir" "$le_account_key" "$csr"
        rc=$?
        if [[ "$rc" -ne 0 ]]
        then
            echo "acme_tiny returned non-zero ($rc), please check!"
            exit 1
        fi
        echo "Certificate generated successfully!"
        echo
        echo "Apache config:"
        echo -e "SSLEngine on\nSSLCertificateFile ${destination_dir}/domain.crt\nSSLCertificateKeyFile ${destination_dir}/domain.key\n"
        echo "Nginx config:"
        echo -e "ssl_certificate ${destination_dir}/domain.crt\nssl_certificate_key ${destination_dir}/domain.key"

else
    le_account_key="${destination_dir}/account.key"
    cert_expiration="$(openssl x509 -in ${destination_dir}/domain.crt -text -noout | grep 'Not After' | cut -d ':' -f 2-)"
    cert_expiration_timestamp=$(date -d "${cert_expiration}" "+%s")
    current_timestamp=$(date "+%s")
    mindiff_seconds=$((mindiff * 24 * 60 * 60))

    if [[ -e "${destination_dir}/domains.txt" ]]
    then
        if ! /usr/bin/diff "${target_file}" "${destination_dir}/domains.txt" &>/dev/null && [[ "$opt_f" -ne "1" ]]
        then
            echo "WARNING - \"${destination_dir}/domains.txt\" already exists and differs from input file!"
            echo "To force certificate regeneration with different domains, use the -f option!"
            exit 1
        fi
    fi

    if [[ "$((cert_expiration_timestamp - current_timestamp))" -lt "$mindiff_seconds" ]] || [[ "$opt_f" -eq "1" ]]
    then
        for domain in $(cat "$target_file")
        do
            echo "Prefliht checking domain $domain"
            if ! http_challenge_check "$domain"
            then
                echo "Preflight HTTP challenge failed for \"${domain}\""
                error=1
            fi
        done
        if [[ "$error" -eq 1 ]]
        then
            echo "One (Or more) preflight checks failed, exitting!"
            exit 1
        fi
    
        le_account_key="${destination_dir}/account.key"
        csr=$(generate_csr "$destination_dir" "$target_file")
        generate_crt "$destination_dir" "$le_account_key" "$csr"
        rc=$?
        if [[ "$rc" -ne 0 ]]
        then
            echo "acme_tiny returned non-zero ($rc), please check!"
            exit 1
        fi
    else
        echo "Certificate expires in more than $mindiff days ($(echo $(( (cert_expiration_timestamp - current_timestamp) / 60 / 60 / 24)) ) days from now), renewal not needed!"
        echo "Use -f to forcibly renew the certificate!"
        exit 0
    fi
fi
