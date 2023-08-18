---
categories: ["Posts", "Guias"]
title: "Pentesting en servidores de Minecraft (Java)"
logo: '/assets/posts/minecraft-security/logo.png'
image: '/assets/posts/minecraft-security/banner.jpeg'
description: "Explorando el tema de la seguridad en los servidores de este videojuego."
tags: ["Seguridad", "Minecraft", "Servidores"]
---

Si tienes un servidor de Minecraft, seguro te has preguntado como es que algunas personas llegan a ganar privilegios de administrador solamente para hacer el acto conocido como "griefing", pues es curioso pero muchas veces solo utilizan técnicas conocidas abusando de errores de configuración de los servidores; han sido pocos los casos donde se trataba de alguna vulnerabilidad que nadie conocía.

Pero sin embargo, me gustaría explicar un poco sobre de que va esto o como van a vulnerar servidores de Minecraft, asi que si es de tu agrado siéntate y tómate un respiro leyendo.

> La información que estoy dando en este post es en base a los conocimientos que tengo, "pueden" haber errores. Si encuentras uno eres libre de hacérmelo saber. 
>
> Igualmente hice esto con fines de enseñanza y saber, no soy responsable de actos maliciosos ni que termines en muchos problemas.
{: .prompt-warning }

## Introducción

En el mundo de servidores de este videojuego existen distintos tipos de software para poner a correr una simple instancia de un servidor, está el bien conocido Vanilla y otras versiones alternativas de terceros que se encargan de permitirle al administrador hacer más cosas de las que se podrían con el servidor oficial de Mojang. También existen software que aprovechan las modificaciones de las versiones alternativas para conectar multiples instancias y funcionar como un Proxy hacía ellas; esto se usa principalmente en las bien conocidas "Networks" para crear múltiples modalidades de juego y proveer una buena experiencia a los jugadores que entren.

Las instancias son llamadas informalmente por algunos como "Spigots" mientras que el software Proxy "[BungeeCord](https://github.com/SpigotMC/BungeeCord)", dado que BungeeCord fue uno de los primeros y más conocidos software de esta clase.

Una de las ventajas que introducen las versiones alternativas es el soporte para "plugins" que permiten al administrador expandir sus ideas para hacer minijuegos, innovación y demás en el servidor, de aquí han hecho posible muchos minijuegos que puedes ver en las distintas networks. También hay otras versiones que introducen el soporte para los bien conocidos mods junto a los plugins.

De las versiones alternativas al Vanilla de Mojang que existen y son conocidas actualmente en la comunidad, son:

- [Spigot](https://spigotmc.org): Creado por md_5, fue hecho como una versión mejorada de CraftBukkit para mejorar la API nativa y rendimiento de este. Este software permite alterar y agregar funciones al servidor a través de los llamados "plugins".

- [Paper](https://papermc.io): Un fork de Spigot hecho por Aikar, con inmensas mejoras en el rendimiento del servidor y bastantes mejoras en la API de Spigot. En versiones recientes también tiene implementado su propia API que es más extensa que la de Spigot.

- [Purpur](https://purpurmc.org): Otro fork, esta vez de Paper que implementa parches y funciones que nunca serían implementados en el upstream de este Fork.

- [Pufferfish](https://pufferfish.host/downloads): Un fork con parches de otros softwares como Paper y Purpur que tiene mejoras de rendimiento y estabilidad. Tiene una versión normal y una "plus".

- [Folia](https://papermc.io/software/folia): Fork de Paper hecho por su misma organización con el fin de hacer gran parte del servidor de Minecraft multi tarea, al ser altamente experimental y requerir de gran potencial solo puede ser obtenido si lo compilas desde su código fuente.

- [Magma](https://magmafoundation.org/): Una versión del servidor de Minecraft hibrída entre la API de Spigot y de Forge que permite usar mods y plugins juntos. Es más usado en los servidores de temática por ejemplo, "Pixelmon".

- [Arclight](https://github.com/IzzelAliz/Arclight): Otra versión híbrida entre plugins y mods, pero está hecha usando la librería [Mixin](https://github.com/SpongePowered/Mixin).

- [Sponge](https://spongepowered.org/): Una versión alternativa del servidor de Mojang que utiliza una API completamente distinta a la de Bukkit y Spigot 

De BungeeCord también existen otras variaciones, unas de paga, y otras gratis y de código abierto. Entre las más conocidas en el mundillo hispano de servidores de Minecraft están:

- [Velocity](https://github.com/PaperMC/Velocity): Un proxy de código abierto creado desde 0 con las intenciones de salir de la "nefasta" API de BungeeCord y prometer una buena escalabilidad y rendimiento. Licenciado bajo la GPLv3 es un proyecto perteneciente a la organización de [PaperMC](https://papermc.io) actualmente.

- [Waterfall](https://github.com/PaperMC/Waterfall): Fork de BungeeCord creado para solucionar fallos de estabilidad y rendimiento que tiene el proyecto original. Licenciado bajo la misma licencia que BungeeCord también pertenece a la organización de [PaperMC](https://papermc.io).

- [FlameCord](https://github.com/arkflame/FlameCord): Otro fork, esta vez de Waterfall y hecho para solucionar los problemas que tiene BungeeCord y sus derivados soportando ataques DDoS L7 y de bots. Perteneciente al estudio ArkFlame Development.

- [NullCordX](https://polymart.org/resource/nullcordx-30-off.1476): Fork de Waterfall hecho con las mismas intenciones que FlameCord pero con muuchas mejoras y carácteristicas adiccionales. Creado por "Shield Community" actualmente el proyecto es de paga y cuesta unos 10$, aunque a fecha de creación de este post está en 30% de descuento.

Obviamente existen otros software alternativos, pero te toca a ti descubrirlos.

## Enumeración

El servidor está asignado en la IANA al puerto 25565/tcp, algunos lo suelen colocar en rangos de puertos cercanos a este ya sea para evitar colisiones (Hostings), o para "esconderlo" de atacantes. Sigue un protocolo de estados (STATUS, LOGIN y PLAY) basado en packets para la comunicación cliente-servidor bajo el transporte TCP.

Al enviar un ping de cliente al servidor, te reportará la cantidad de jugadores y versión del servidor, las versiones alternativas suelen incluir por defecto el nombre del software en la respuesta del servidor, pero esto último normalmente es alterado o eliminado por varios servidores para evitar esto mismo que estamos haciendo.

![Status](/assets/posts/minecraft-security/status.png)
_La página web [Minecraft server status](https://mcsrvstat.us) te permite ver el estado de los servidores rápidamente_

### Modificaciones externas

Normalmente los anteriormente mencionados plugins se descargan de páginas como [SpigotMC](https://spigotmc.org/resources/), [Modrinth](https://modrinth.com), [Builtbybit](https://builtbybit.com/) o [Polymart](https://polymart.org), aunque los servidores grandes más que utilizar plugins de terceros cuentan con plugins desarrollados por sus propio equipo de programadores.

También hay unos cuantos que utilizan software híbrido entre mods y plugins para potenciar aún más su capacidad de agregar minijuegos y cosas interesantes, al coste de tener que lidiar con seguros problemas de incompatiblidad entre plugins y mods.

En los servidores Spigot existen comandos que te permiten ver que versión y software ejecutan el servidor junto a sus plugins, cuales puedes ejecutar ya que por defecto el usuario tiene acceso a ellos; estos comandos son: 

- `plugins` | Plugins del servidor
- `version` | Versión del software y de los plugins
- `icanhasbukkit` | Alias del comando de arriba

Muchos configuradores suelen bloquear estos comandos quitando los permisos o simplemente utilizando un plugin que verifique el comando que estás enviando, en caso de ser el último podrías intentar saltártelo agregando el prefix del proveedor del comando que en este caso seria `bukkit`, junto al comando separados por dos puntos (`bukkit:version`, `bukkit:plugins`). También puedes notar si el servidor usa un plugin determinado mediante sus comandos, comportamiento o a simple vista si no editan mucho las configuraciones (En muchos servidores de habla hispana pequeños, este caso es bastante visto).

Hablando de los mods (Fabric, Forge); la metodología no cambia mucho además de que para establecer una conexión con este tipo de servidores debes tener los mods cliente-servidor que tenga el servidor.

### Conexión y reverse proxies

No existe una implementación nativa por parte de Mojang para correr el servidor detrás de un proxy, pero si existen no oficiales como TCPShield e Infinity Guard. Cloudflare Spectrum también puede ser usado ya que es una tecnología que ciertamente permite cualquier transporte TCP; puedes verificar de forma sencilla si haces conexión directa con el servidor o a través de un proxy simplemente efectuando un ping ICMP y comprobando la dirección en servicios como [ipinfo.io](https://ipinfo.io)

Sobre los DNS, los SRV record de este servicio tienen por nombre `_minecraft`, pueden ser tranquilamente uno como este:

`_minecraft._tcp.play.buzonmc.com`

Si no existe un proxy TCP que cubra al backend, la comunicación entre el cliente y servidor es directa, por lo que podrías ver la dirección IPv4 del servidor y el servidor podría ver tu IPv4 tranquilamente. Algo parecido al HTTP.

### Estructura del servidor

Los servidores de Minecraft a veces suelen estar compuestos con varios servidores y proxies, normalmente a este tipo de servidor se le conoce como "Network".

A día de hoy, esta parte de la comunidad ha creado softwares para dividir la carga de conexiones a distintas instancias/replicas de un mismo servidor debido al alto coste de rendimiento que tiene correr un servidor con demasiados jugadores, de esta clase de software los más conocidos son MultiPaper (Instancias) y RedisBungee (Proxies). Uno permite la sincronización de varios servidores para tener los mismos datos de plugins y mundos mientras que el otro sincroniza el número de jugadores y sus estados en multiples instancias de BungeeCord.

No hay una forma especifíca de saber si un servidor utiliza tecnologías y softwares de este tipo, pero viendo la estructura desde afuera y el comportamiento te puede dar ideas respecto a ello. Por ejemplo existen servidores que tienen varias direcciones IPv4 asignadas al registro DNS A del servidor:

```bash
... [snip]
;; ANSWER SECTION:
mc.universocraft.com.	71	IN	A	51.79.***.****
mc.universocraft.com.	71	IN	A	51.79.***.***
mc.universocraft.com.	71	IN	A	51.79.***.***
mc.universocraft.com.	71	IN	A	51.79.***.***
mc.universocraft.com.	71	IN	A	51.79.***.***
mc.universocraft.com.	71	IN	A	51.161.***.***
mc.universocraft.com.	71	IN	A	51.79.***.***
mc.universocraft.com.	71	IN	A	51.161.***.***
mc.universocraft.com.	71	IN	A	51.79.***.***

;; Query time: 83 msec
;; SERVER: 1.1.1.1#53(1.1.1.1) (UDP)
;; WHEN: Thu Jul 06 19:15:45 -04 2023
;; MSG SIZE  rcvd: 193
```
*El servidor UniversoCraft, por ejemplo usa el algoritmo [Round Robin](https://es.wikipedia.org/wiki/Planificaci%C3%B3n_Round-robin) en sus DNS para rotar las direcciones de sus servidores. Muy probablemente esté usando algo asociado a RedisBungee*

## Explotación

### IP Forwading (BungeeCord)

BungeeCord para funcionar normalmente debe reenviar el handshake (apretón de manos) que envía el jugador cuando se conecta al servidor hacía la instancia a la que se está conectando dicho jugador, este handshake que se reenvía se altera para poder retransmitir la IP y UUID del jugador que recibe el proxy a la instancia destino sin problemas. Por eso se pide explicitamente que desactives el polémico "modo online" de las instancias que tienes conectadas al Bungee.

Vamos a mirar un poco a bajo nivel... esta es la secuencia y estructura de los packets que envía un cliente de Minecraft en la versión 1.19.4 protocolo 762, obviamente esto no se va a ver así si te pones a analizar packets a bajo nivel de verdad:

```

    ---  HANDSHAKE (Enviado por el cliente) ---
                
    +----------+----------+------------------------+--------------+---------------------+
    |          |          |                        |              |                     |
    |    ID    |NEXT STATE|    Server IP Address   | Server Port  |   Protocol Version  | 
    |   0x00   | LOGIN(2) |      172.19.0.100      |    25565     |         762         |
    |          |          |                        |              |                     |  
    +----------+----------+------------------------+--------------+---------------------+

    --- LOGIN START (Enviado por el cliente) ---

    +---------+----------+-----------------+-------------------------------------+
    |         |          |                 |                                     |
    |   ID    |   NAME   |     HAS UUID    |   UUID (if previous field is true)  |
    |  0x00   |  iVz0n_  |    true|false   |         bf02fe6e-a4ba-....          | 
    |         |          |                 |                                     |
    +---------+----------+-----------------+-------------------------------------+

    # Si está el modo online habilitado se habilita la encriptación y se hace el proceso
    # de autenticación de la cuenta. Del caso contrario el servidor simplemente envia el packet
    # LOGIN SUCCESS. Con la comprensión habilitada antes de esto, se comprimen los packets.

    --- LOGIN SUCCESS (Enviado por el servidor) ---

    +-------------+---------------------+--------------------+-----------...
    |             |                     |                    |
    |     ID      |       UUID          |        NAME        |    Number of properties,
    |    0x02     |  bf02fe6e-a4ba-.... |       iVz0n_       |    properties, signature... etc
    |             |                     |                    |
    +-------------+---------------------+--------------------+-----------...

```

El segundo packet enviado por el cliente, Login Start (O inicio de autenticación) es alterado por BungeeCord para poder pasar la información de la IP y UUID "real" del jugador de la siguiente forma:

```

    +---------+----------+-----------------+-------------------------------------+
    |         |          |                 |                                     |
    |   ID    |   NAME   |     HAS UUID    |           "Real" UUID               |
    |  0x00   |  iVz0n_  |       true      |         bf02fe6e-a4ba-....          | 
    |         |          |                 |                                     |
    +---------+----------+-----------------+-------------------------------------+
                                           |                                     |
                                           |        "Real" IP Address            |
                                           |          172.19.0.100               |
                                           |                                     |
                                           +-------------------------------------+

```

Estos dos campos se alteran porque BungeeCord, al funcionar como Proxy todas las conexiones que recibe las reenvía "en su nombre" hacía las instancias conectadas, por lo que en vez de ver la IPv4 real del jugador verías la IP del BungeeCord (que bien puede ser 127.0.0.1 si hosteas todo en el mismo servidor), por eso es necesario alterar los packets del protocolo para que el Proxy funcione, a Spigot se le implementó el "modo BungeeCord" para que pudiera aceptar este packet alterado sin ningún tipo de problemas.

Ahora, el problema de seguridad aquí es que la instancia de Spigot al estar en dicho modo no tiene forma de verificar a que Proxy debe aceptarle las conexiones por lo que simplemente se la acepta a todo el que tenga el ajuste para activar el protocolo de reenvío de IP (`ip-forwading`) habilitado. Seguido de esto tampoco hay ningún tipo de validación de los dos campos alterados por el Proxy, por lo cual podrías alterarlos por un valor arbitrario.

Puedes colocarte la UUID de otra persona mientras que en la dirección IPv4 puedes colocar lo que se te cante, literalmente...

![XD](/assets/posts/minecraft-security/XD1.png)
![XD](/assets/posts/minecraft-security/XD2.png)

Esto no es tanto una falla en el modelo de BungeeCord/Spigot, pero al menos debería existir una opción para validar las conexiones que se reciben y sus parámetros mediante un token o nonce junto a sus checks de valores o eso pienso yo. Velocity tiene su propio sistema de verificación de conexiones llamado [Modern Forwading](https://docs.papermc.io/velocity/security) a través de un secret, dicho modo solo puede ser usado en servidores Paper con versiones superiores a la 1.13.2.

> Un dato curioso es que mucha gente conocida como "griefers" suele buscar servidores de networks que no estén asegurados mediante escaneos de rangos de IP con herramientas como [QuboScanner](https://github.com/replydev/Quboscanner) para vulnerarlos mediante este fallo.
{: .prompt-info }

¿Podemos llevar esto a otro nivel además de simplemente spoofear la UUID de una cuenta con muchos permisos y buscar formas de elevar nuestro control?, depende mucho de los plugins que tengan instalados y como los tienen configurados, pero dejando de lado eso este fallo es el que se explota con más frecuencia para "grifear" los servidores de la gente debido al desconocimiento general del firewalls y de plugins buenos para protegerse.

Hablando de lo último, lee abajo.

### Plugins 

Los plugins que tiene un servidor muchas veces pueden ser un vector de ataque debido a vulnerabilidades en estos, si has identificado los plugins que tiene un servidor puedes mirar si son open source para irte a analizar el código y buscar vulnerabilidades de las que te puedas aprovechar para darte permisos administrativos o ir más allá de eso, también puedes buscar configuraciones por defecto de estos que te permitan ganar cierto privilegio, como es en el caso de algunos de entrar con el nick del creador del plugin si el servidor permite usuarios no-premium.

En caso de que no encuentres nada de los plugins o sean privados, si tienes la paciencia y sentido común también podrías buscar fallos simplemente... probando

### Malas configuraciones

Este vector es otro de los más utilizados aparte del bypass al IP Forwading; gente que no configura bien sus servidores.

Para ponerte un ejemplo, en las networks hay administradores que configuran un sistema de autenticación para permitir el acceso a jugadores no premium (o piratas) en las networks usando plugins como AuthMe, LockLogin o nLogin, pero hay veces a los que a estos se les pasa y dejan mal configurado el conocido AuthLobby o servidor de autenticación para que puedan ejecutar comandos de los plugins que tiene el Proxy. Si a esto se le suma algún comando para cambiar de servidor un intruso puede saltarse el sistema de autenticación fácilmente.

El ejemplo más típico de una configuración de BungeeCord con la cual eso puede ser abusado es la siguiente si no se utiliza ningún otro plugin que altere los permisos:

```yaml
...[snip]
prevent_proxy_connections: false
groups:
  md_5:
  - admin
connection_throttle: 4000
permissions:
  default:
  - bungeecord.command.server
  - bungeecord.command.list
  admin:
  - bungeecord.command.alert
  - bungeecord.command.end
  - bungeecord.command.ip
  - bungeecord.command.reload
...[snip]
```
{: file='config.yml'}

Entrando con cualquier cuenta no premium simplemente puedo utilizar `/server <servidor>` para saltarme todas las comprobaciones dado el simple hecho de poder ejecutar comandos del proxy sin siquiera autenticarme.

Pero aparte de eso, en esta configuración hay otra cosa que se puede considerar como una vulnerabilidad si se trata de un servidor que permite acceso a usuarios no premium, y es el nick que tiene asignado el grupo de admin. Al no haber ningún tipo de comprobación para verificar si el jugador es premium puedo entrar con ese nick y podría usar los comandos que tiene asignado el grupo admin.

Otra mala configuración es la de los permisos dados innecesariamente a comandos que pueden ser potencialmente peligrosos usando por ejemplo, el nodo de permiso `<plugin-name>.*`, dar esto en plugins como WorldEdit aunque sea solamente para creativo, permitirá al usuario hacer cosas que pueden desde posiblemente crashear el servidor hasta filtrar información.

> Y dadas las circunstancias, no tener firewall o aunque sea un plugin bien hecho que proteja contra los adversarios que intenten entrar con un BungeeCord malicioso y dejar las configuraciones por defecto también puede contar como mala configuración.
{: .prompt-tip }

### OSINT

> OSINT o "Open Source Intelligence" es el uso de técnicas de busqueda en fuentes de información abiertas para obtener información sobre algún individual, corporación o entidad.
{: .prompt-info }

Información por el internet, esto puede servirle a un atacante para identificar y hacerle reconocimiento al servidor, este reconicimiento abarca saber el nombre de los administradores, subdominios existentes, historial de direcciones IPv4, redes sociales, cualquier evento/drama/suceso por el que haya pasado la comunidad de dicho servidor y **cosas que no se deberían poder ver que están expuestas al internet por algún motivo**.

Veamos como se puede usar el OSINT para encontrar cositas interesantes, si hago esta busqueda por Google usando el dork `intitle`

`intitle:"Index of" spigot.yml`

Puedo encontrar unos cuantos resultados de páginas con el listado de directorios activado que contienen un archivo llamado "spigot.yml", normalmente solo hay servidores que lo hacen con consentimiento pero me he encontrado algunos que exponian credenciales sin motivo alguno.

![Files](/assets/posts/minecraft-security/files1.png)

Usando páginas de historial de registros DNS de los dominios podría llegar a obtener las direcciones IPv4 verdaderas de la máquina de tu servidor protegido con algún proxy reverso/honeypot si las tuvistes asignada a tu registro DNS durante un tiempo y no las has cambiado.

![DNS](/assets/posts/minecraft-security/dns.png)

Con buscadores como Shodan o Censys se puede indagar para encontrar servidores con servicios interesantes o que estén protegidos con proxies reversos. Utilizando el dominio del servidor de Minecraft puede que encuentren algo que llame la atención.

![Server search engines](/assets/posts/minecraft-security/censys.png)

Hay muchos otros motores y dorks de google que puedes usar para buscar por información respecto a un servidor, pero hay que idearselas y saber que buscar, sin embargo hay que recordar que no todos los servidores de Minecraft tienen webs o no tienen algo que exponer al internet.

### Servicios externos

No hay que olvidarse de otros servicios que tengan una potencial interacción con un servidor de Minecraft, ya que pueden tener vulnerabilidades que te permitan elevar el control sobre este o ir más allá de eso, y quien sabe si ese servicio expuesto no debería estar ahí.

Por ejemplo, de contexto hemos encontrado una API REST que te permite listar información de los jugadores del servidor, contaría con esta ruta para poder obtener a un jugador:

`/api/user/:name`

El programador de esto, pensando que no se podrían poner carácteres raros en la URI colocó la siguiente pieza de código por flojera:

`cursor.execute("SELECT name,uuid,money,banned FROM users WHERE name = '" + name + "'")`

Poniendo simplemente un nombre la API funcionará normal:

```bash
❯ curl -v http://192.168.250.2:8000/api/user/iVz0n_
*   Trying 192.168.250.2:8000...
* Connected to 192.168.250.2 (192.168.250.2) port 8000 (#0)
> GET /api/user/iVz0n_ HTTP/1.1
> Host: 192.168.250.2:8000
> User-Agent: curl/8.0.1
> Accept: */*
> 
< HTTP/1.1 200 OK
< Server: gunicorn
< Date: Thu, 18 May 2023 19:11:17 GMT
< Connection: close
< Content-Type: application/json
< Content-Length: 56
< 
[["iVz0n_","bf02fe6e-a4ba-4759-92e5-5e91a48fc918",0,0]]
```

Pero el fallo aquí es que puedes colocar carácteres extraños en formato URL y el servidor te los procesará, tal como espacios que el servidor web traduciría sin ningún tipo de fallos:

```
/api/user/'%20OR%201=1%20--%20-
```

```sql
SELECT name,uuid,money FROM users WHERE name = '' OR 1=1 -- -
```

![SQLi](/assets/posts/minecraft-security/sqli.png)

Con esto puedo volcarme las bases de datos a las que el usuario de mysql tenga acceso, y si el driver que utiliza la aplicación por alguna razón permite concatenar sentencias podrías hasta alterar datos y darte privilegios elevados.

Otro ejemplo, pero que sirve más de enumeración es que existe ciertos servidores que dejan el servidor web de [PlayerAnalytics](https://www.playeranalytics.net/) expuesto al internet sin ningún tipo de autenticación, por lo que podrías acceder y filtrar datos que sean de interés

No solo existen páginas web que interactuen con un servidor de Minecraft, si no también Bots de alguna red social como Discord o APIs, como vimos arriba. 

### Ingeniería social

> Ah, la típica

Precisamente, hay griefers que estando frustrados recurren a este método (y muchas veces fallan miserablemente).

Hay muchas formas de efectuar ingeniería social, puedes hacer páginas de Phishing, hacer un servidor de Minecraft señuelo o un proxy que redirija a otro e intercepte los comandos que el usuario hace. Si tu objetivo es el dueño del servidor puedes también decirle que instalen plugins que te den control a tí o la forma más insana de todas; molestarles para que te den un rango con permisos elevados dentro del servidor (Broma, esto solo es funcional en servidores donde el dueño tenga demasiada confianza).

Pero volviendo a lo serio, de ejemplo yo podría montarme una página fake del login de Microsoft, enviársela al objetivo con un mensaje que incite a que pinche el enlace y esperar a que meta sus credenciales. También existen "exploits" que pueden ser letales si los utilizas con ingeniería social, como el clásico de la 1.8 donde puedes crear una URL en los libros que al ser clickeada hará que el usuario ejecute comandos sin consentimiento (BookExploit).

![BookExploit](/assets/posts/minecraft-security/bookexploit.png)
_La ventanita que te da el Wurst para abusar del BookExploit_

### Software desactualizado

Usar una versión muy vieja del software de servidor puede traer vulnerabilidades, y la que puede ser la más peligrosa es el [CVE-2021-44228](https://cve.mitre.org/cgi-bin/cvename.cgi?name=cve-2021-44228), por ejemplo la última build de la versión 1.16.5 de Purpur tiene este fallo sin parchear.

En esto también están incluidos los plugins y mods desactualizados.

## Post explotación

Ya tienen acceso administrativo a tu servidor, ahora te preguntas ¿qué harán?

Los griefers te romperán las construcciones solamente para subir un vídeo de 5 minutos con música chota mostrando como han vulnerado el servidor y como supuestamente "saben hacer cositas", pero hay ciertos de ellos u otras personas que van por cosas distintas; en mi caso, si tienes un dedicado o VPS yo buscaría formas de "pivotar" mi control del servidor de Minecraft hacia tu servidor Linux en si. Hay varias cosas en el servidor que pueden ayudar a lograr esto dependiendo de como esté configurado y que otros servicios externos pueda tener que se comuniquen con él. Aquí dejo unos ejemplos

### Plugins y sus funciones

Normalmente hay plugins que permiten efectuar funciones administrativas como cargar/hacer respaldos, descargar archivos, librerías, recargar/desactivar plugins, cargar/eliminar mundos y más. Lo que te permita administrar depende de las funciones que tenga, pero existen plugins con funciones que si bien no son peligrosas pueden permitirte enumerar el servidor, y hay otros con comandos muy peligrosos que te pueden dar hasta para ejecutar código o leer archivos de la máquina, también pueden existir plugins que tengan vulnerabilidades en estas funciones pero a la final ya esto es cuestión de saber buscar.

Algunos ejemplos de plugins que pueden ser usados para cosas beneficiosas son...

#### Plugins con funciones de respaldos, carga de archivos... etc

Algunos de estos tipos de plugins te pueden permitir hacer cosas interesantes, pero muchos otros solo servirán para enumeración.

Por ejemplo, al exportar los permisos de LuckPerms, este plugin te dice donde guarda el archivo en forma de ruta absoluta. Con esto puedes llegar a saber quien o donde se ejecuta el servidor.

![LuckPerms](/assets/posts/minecraft-security/luckperms.png)

#### BungeeServerManager y derivados

Este plugin te permite modificar los servidores que tiene el BungeeCord en su configuración, suena inofensivo, pero podría hacer esto para aprovecharme: Le digo a todos tus jugadores que entren a un servidor que agregué con el plugin y yo controlo, en este servidor puedo colocar un plugin que simule ser un servidor de autenticación (authlobby) y muchos sin pensar introducirían sus contraseñas, además de que obtendría sus direcciones IPv4.

#### ServerUtils, PlugManX... etc

Con estos lo único que podrías hacer es simplemente desactivar y activar plugins, pero si tuvieras la posiblidad de subir un plugin malicioso, uno de estos te ayudará bastante.

#### Plugins con sistemas para subir dumps, logs... etc

Te permitirán ver cierta información del sistema como la versión del sistema operativo, Java, RAM, núcleos e identificador del procesador, hay algunos como EssentialsX que al hacer un dump te muestran cierta parte de los logs del servidor (consola). En esta categoria también entran plugins como [Spark](https://www.spigotmc.org/resources/spark.57242/)

#### Plugins que descargan o suben recursos

Estos plugins son aquellos que normalmente te permiten descargar configuraciones o recursos de la web que le especifiques, podrías usar esto para filtrar la dirección IPv4 verdadera del servidor si está detrás de un proxy reverso o un servicio como TCPShield/Infinity Filter o para enumerar puertos internos si es que te permite hacer peticiones a la misma máquina. Un ejemplo de estos plugins es el conocido CommandPanels.

#### PlaceholderAPI

Este plugin de placeholders te permite descargar expansiones de un sitio llamado "eCloud", ciertas de sus expansiones como "Server" y "Pinger" pueden ser usadas para enumeración o filtrar información, y una que es muy interesante es la de "JavaScript"

![JS](/assets/posts/minecraft-security/jsexp.png)

Esta extensión tiene un comando que te permite ejecutar expresiones JavaScript a través de un comando que puedes ver claramente cual es, en la imagen de arriba. En sus versiones anteriores a la 2.1.2 no había ningún tipo de sandbox para el motor de JavaScript, esto te permitía hacer referencia a cualquier objeto de Java disponible, por lo que algo como:

`/jsexp parse me var a = Java.type("java.lang.Runtime"); a.getRuntime().exec("{COMMAND}")`

Te dejaba ejecutar comandos del sistema dentro del servidor de Minecraft.

#### Plugins desactualizados y/o con vulnerabilidades

Si un servidor tiene plugins desactualizados, puedes buscar entre sus versiones a ver si la que corre el servidor tiene una vulnerabilidad sin parchar, como el Path Traversal de HolographicDisplays en versiones anteriores a la 2.2.9, el subcomando `sqlexec` de LiteBans que existe en versiones antiguas o el `/promote` y `/demote` de PermissionsEx.

#### Plugins con WebServers

Los plugins de este estilo abren un servicio web que puede ser visto en puertos como el 8080, 8000 o el mismo 80 y 443, pueden tener comandos para agregar archivos a la web, usuarios o configurarla. (como `/plan register` de PlayerAnalytics).

#### BungeeCommands

Si un servidor tiene un plugin de este estilo y solamente tienes el control de una modalidad, te puede ayudar para tomar control de todo el servidor.

#### CloudSystems

Estos sistemas funcionan como una interfaz para manejar varios servidores de Minecraft en una Network, uno de los más conocidos es [CloudNET v3](https://www.spigotmc.org/resources/cloudnet-v3-the-cloud-network-environment-technology.42059/). Es posible abusar de ellos si la cuenta comprometida tiene permisos para ejecutar comandos que permitan alterar la configuración de inicio o tareas de estos sistemas, ya que alguno de esos comandos te puede permitir alterar cosas como el ejecutable de Java o los parámetros de la JVM.

#### Plugins con funciones innecesarias y/o potencialmente peligrosas

Existen plugins que proveen funciones para administrar el servidor desde el juego, ya sea editar las configuraciones de los plugins, manejar los servidores en una Network o directamente ejecutar código. La explotación de estos sencillamente es straightforward.

## Privilegios y entorno

Ahora hablemos de los privilegios que puede tener un servidor de Minecraft y en donde se puede estar ejecutando.

El servidor de Minecraft se ejecuta con Java, y Java se ejecuta como un proceso normal del sistema, y ese proceso es ejecutado por un usuario, usuario que tiene permisos; cualquier comando o cambio que se haga en el sistema de archivos estará a nombre de ese usuario, lo que quiere decir que si ejecutan el servidor como Administrador o root todo lo que haga el servidor se hará con permisos de dicho usuario. 

Te voy a poner de contexto donde hay un tipo de los plugins listados arriba y de alguna forma has ganado permisos administrativos: existe un plugin custom que un desarrollador que trabaja para un servidor llamado "Mailbox Network" creó para ejecutar comandos del sistema ya que por alguna razón le era molesto entrar por SSH y usar comandos de Linux para meterse en el screen o contenedor del servidor.

El comando `/system <command>` que solo puede ser usado por los usuarios con el permiso "mailbox.command.system" le permite a los usuarios con este permiso ejecutar comandos del sistema como el usuario que corre el servidor

```java
package com.mailbox.commands;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;

import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

public class SystemCmd implements CommandExecutor {

    public boolean onCommand(CommandSender sender, Command cmd, String label, String[] args){

        String arg = Arrays.stream(args).reduce("", (prev, next) -> prev + " " + next);

        if(arg.isEmpty()){
            sender.sendMessage("Please provide a value");
            return false;
        }

        try {
            Process proc = Runtime.getRuntime().exec(arg);

            InputStream procStdout = proc.getInputStream();
            String output = new String(procStdout.readAllBytes());

            sender.sendMessage(output);

        } catch (IOException e){
            e.printStackTrace();
        }

        return true;
    }
}
```
{: file='SystemCmd.java'}

Ya que como eres operador o administrador, puedes hacer tranquilamente algo similar:

![Minecraft](/assets/posts/minecraft-security/privesc1.png)
![reverse shell](/assets/posts/minecraft-security/privesc2.png)

Ahora, imagina que el servidor lo está ejecutando root; podrás modificar a tu antojo lo que sea del sistema, desde borrar literalmente todo hasta meter un ransomware. Sin embargo hay que tener en cuenta igual que al llevar a cabo algo como esto dejará al proceso principal del servidor congelado, en espera del proceso de la reverse shell en caso de que no se ejecute de forma asincrona, por lo que el servidor morirá en cuestión de segundos/minutos alertando a la administración, y haciendo que a la vez tu reverse shell muera.

Un permiso como este en sudoers asignado al usuario que ejecuta el servidor te va a llevar al mismo punto:

```bash
user ALL=(ALL:ALL) NOPASSWD: ALL
```

Dejando el contexto, vamos al caso de los contenedores, normalmente se suele usar Docker para mantener los servidores aislados de la máquina real, así no podrán causar perjuicios a esta en caso de que sean vulnerados. Paneles de gameservers como [Pterodactyl](https://github.com/pterodactyl/panel) usan el mismo software para mantener las instancias de los servidores aisladas del sistema real de los nodos que dicho panel maneja, pero aunque esté en un contenedor hay que tener cuidado.

Con ganar acceso a una consola interactiva del modo que sea recuerda que aún tengo la capacidad de tomar tus bases de datos ya sean locales o remotas, ya que para hacer funcionar los plugins con eso o dejan la base de datos en el servidor o dejan las credenciales para que los plugins se comunique con la(s) base(s) de datos. También alguien podría aprovecharse de los contenedores que tengas en la red de Docker, puertos internos o vulnerabilidades de los mismos para poder escaparse del contenedor y saltar a tu sistema real, sin embargo la posibilidad de que escapen de tus contenedores usando alguna vulnerabilidad del motor o utilizando otros contenedores en la red es baja ya que algunos paneles como Pterodactyl normalmente ejecutan los contenedores en una red distinta a la por defecto de Docker sumándole que las imágenes y configuración que usan estos contenedores están bien protegidos contra atacantes, todo depende mayormente de como tengas configurado todo.

En instalaciones de servidores en Windows Server igual hay que tener cuidado, no debe usarse el usuario `Administrador` para correr el servidor y se debe seguir los consejos de seguridad de dicho sistema operativo, y también se deben tomar precauciones con los plugins que cargan archivos ya que existen formas especiales para cargar archivos como lo es el protocolo SMB.

> Aunque esté dando consejos para correr de forma segura un servidor de Minecraft en Windows, deberías evitarlo ya que no está diseñado para correr servidores de videojuegos. Si necesitas tener control total del sistema compra una VPS o Dedicado con Linux.
{: .prompt-tip }

## Logs y detención

Efectuar enumeración y explotación de vulnerabilidades en muchos servicios deja sus trazas, y el servidor de Minecraft no es la excepción.

Cuando una persona abusa del IP Forwading normalmente suele spoofear la IP "127.0.0.1" y no se nota ninguna conexión anterior desde el Proxy hacía la modalidad en la que está, como vimos en las primeras imágenes del post son capaces de colocarse hasta IPv4 inválidas y spoofear la UUID de un administrador.

Ciertas veces explotar vulnerabilidades puede dejar errores en los logs del servidor que a un administrador le puede llamar la atención, más si lo que colocas para explotar la vulnerabilidad tiene un error. Tampoco está demás decir que bastantes servidores tienen habilitado por defecto el log de comandos por lo que cualquier comando que ejecutes se verá reflejado en la consola, los únicos software que vienen con esto deshabilitado por defecto son BungeeCord y Velocity junto a sus forks.

![Logging](/assets/posts/minecraft-security/logging.png)
_Alguien entra para intentar ejecutar un comando, y luego sale_

También pueden haber plugins que te saquen del servidor al hacer un comportamiento extraño y dejen una alerta en la consola o a los mismos administradores, o honeypots en la red del servidor. Es casi imposible que logres un sigilo al 100% cuando vulneres un servicio, pero ciertamente debes intentar ser lo más cauteloso posible para no dar alertas grandes o tumbar accidentalmente el servidor si estás haciendo una prueba de penetración.

## Resumen

Un servidor de Minecraft, como cualquier otro servicio tiene sus formas de ser aprovechado incluso para llegar a tomar control total del sistema que ejecuta el servidor, todo depende bastante de como lo tengas montado, configurado y de como lo administren. Aunque la mayoría de los que se dedican a vulnerar este tipo de servidores solo les gusta grabar un vídeo de 5-10 minutos con música mostrando como rompen los cubos con WorldEdit o `/fill` es importante que mantegas la seguridad de tu servidor de la mejor forma posible, ya que también pueden llegar a filtrar tus archivos y bases de datos para luego proveerlos desde [programitas](https://www.youtube.com/watch?v=SYTFx88qGZo&t=95s&pp=ygUJU2VyTGluazA0) o directamente subirlos a sus canales de Telegram.

