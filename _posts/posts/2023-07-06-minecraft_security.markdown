---
categories: ["Posts", "Guias"]
title: "Pentesting en servidores de Minecraft (Java)"
logo: '/assets/posts/minecraft-security/logo.png'
description: "Explorando el tema de la seguridad en los servidores de este videojuego."
tags: ["Seguridad", "Minecraft", "Servidores"]
---

Hace un tiempo, durante 2020, 2021 y 2022 estuve dentro de la comunidad hispana de administradores y desarrolladores de servidores de Minecraft como espectador ya que solamente pasaba a leer los chats en ocasiones porque era bastante tímido para hablar ahí en esas épocas, aunque tuve dos servidores de dicho videojuego nunca me metía ahí ni aunque fuera para pedir ayuda configurando algún plugin o solucionar bugs extraños.

De esta comunidad me llamaba mucho la atención la parte de seguridad; bots, griefing, squads, protecciones... etc, de ahí nacieron mis ganas de hacer una especie de "tutorial" para  hacer y proteger un servidor de Minecraft, estuve haciéndolo durante 2021 en un repositorio privado de GitHub pero hubo un día en el que lo dejé en el olvido y simplemente lo eliminé ya que sentía que no tenía el conocimiento ni las ganas de publicar dicho tutorial al internet, pero a día de hoy teniendo un blog y pasado casi dos años me pareció bien publicar algo respecto a este tema, por lo que en este post estaré explorando los temas en lo que respecta la seguridad y... "pentesting" de servidores de Minecraft.

## Un poco de contexto

Con servidor común o instancia me estaré refiriendo a una simple instancia de un servidor de Minecraft Java Edition, mientras que con "Network" a una red de instancias.

Esas redes normalmente están conectadas entre si usando un servidor proxy que hace posible una comunicación entre varias instancias de servidores comunes, a este proxy normalmente se le da el nombre de BungeeCord o simplemente "Bungee", ya que uno de los primeros software proxy que se programaron para servidores de Minecraft era exactamente, [BungeeCord](https://github.com/SpigotMC/BungeeCord). 

El servidor de Minecraft actualmente tiene versiones distintas hechas para mejorar la capacidad y posibilidades de este, unas cuantas de ellas conocidas en el mundo hispano son:

- [Spigot](https://spigotmc.org): Creado por md_5, fue hecho como una versión mejorada de CraftBukkit para mejorar la API nativa y rendimiento de este. Este software permite alterar y agregar funciones al servidor a través de los llamados "plugins".

- [Paper](https://papermc.io): Un fork de Spigot hecho por Aikar, con inmensas mejoras en el rendimiento del servidor y bastantes mejoras en la API de Spigot. En versiones recientes también tiene implementado su propia API que es más extensa que la de Spigot.

- [Purpur](https://purpurmc.org): Otro fork, esta vez de Paper que implementa parches y funciones que nunca serían implementados en el upstream de este Fork.

- [Pufferfish](https://pufferfish.host/downloads): Un fork con parches de otros softwares como Paper y Purpur que tiene mejoras de rendimiento y estabilidad. Tiene una versión normal y una "plus".

- [Folia](https://papermc.io/software/folia): Fork de Paper hecho por su misma organización con el fin de hacer gran parte del servidor de Minecraft multi tarea, al ser altamente experimental y requerir de gran potencial solo puede ser obtenido si lo compilas desde su código fuente.

- [Magma](https://magmafoundation.org/): Una versión del servidor de Minecraft hibrída entre la API de Spigot y de Forge que permite usar mods y plugins juntos. Es más usado en los servidores de temática "Pixelmon".

De BungeeCord también existen otras variaciones, unas de paga, y otras gratis y de código abierto. Entre las más conocidas en el mundillo hispano de servidores de Minecraft están:

- [Velocity](https://github.com/PaperMC/Velocity): Un proxy de código abierto creado desde 0 con las intenciones de salir de la "nefasta" API de BungeeCord y prometer una buena escalabilidad y rendimiento. Licenciado bajo la GPLv3 es un proyecto perteneciente a la organización de [PaperMC](https://papermc.io) actualmente.

- [Waterfall](https://github.com/PaperMC/Waterfall): Fork de BungeeCord creado para solucionar fallos de estabilidad y rendimiento que tiene el proyecto original. Licenciado bajo la misma licencia que BungeeCord también pertenece a la organización de [PaperMC](https://papermc.io).

- [FlameCord](https://github.com/arkflame/FlameCord): Otro fork, esta vez de Waterfall y hecho para solucionar los problemas que tiene BungeeCord y sus derivados soportando ataques DDoS L7 y de bots. Perteneciente al estudio ArkFlame Development.

- [NullCordX](https://polymart.org/resource/nullcordx-30-off.1476): Fork de Waterfall hecho con las mismas intenciones que FlameCord pero con muuchas mejoras y carácteristicas adiccionales. Creado por "Shield Community" actualmente el proyecto es de paga y cuesta unos 10$, aunque a fecha de creación de este post está en 30% de descuento.

La mayoría de los servidores hispanos de Minecraft suelen utilizar los softwares que he mencionado para sus necesidades y hacer su infraestructura, el único que no se utiliza casi (por no decir que no se utiliza) es Folia por obvias razones mencionadas arriba.

## Enumeración

El servidor está asignado en la IANA al puerto 25565/tcp, algunos lo suelen colocar en rangos de puertos cercanos a este ya sea para evitar colisiones (Hostings), o para "esconderlo" de atacantes. Sigue un protocolo de estados (STATUS, LOGIN y PLAY) basado en packets para la comunicación cliente-servidor bajo el transporte TCP.

Al enviar un ping de cliente al servidor, te reportará la cantidad de jugadores y el software del servidor; este último es editado por varios servidores para evitar enumeración.

![Status](/assets/posts/minecraft-security/status.png)

*La página web [Minecraft server status](https://mcsrvstat.us) te permite ver el estado de los servidores rápidamente*

### Modificaciones externas

Muchos servidores utilizan software basados en Spigot para agregar plugins que añaden funciones nuevas a sus entornos, ya sean minijuegos, innovaciones o "soluciones" como hacer el servidor multiversión. Normalmente se descargan de páginas como [SpigotMC](https://spigotmc.org/resources/), [Modrinth](https://modrinth.com), [Builtbybit](https://builtbybit.com/) o [Polymart](https://polymart.org), aunque los servidores grandes más que utilizar plugins de terceros cuentan con plugins desarrollados por sus propio equipo de programadores.

También hay unos cuantos que utilizan software híbrido entre mods y plugins como Magma o Mohist para potenciar aún más su capacidad de agregar minijuegos y cosas interesantes, al coste de tener que lidiar con seguros problemas de incompatiblidad entre plugins y mods.

En los servidores Spigot existen comandos que te permiten ver que versión y software ejecutan el servidor junto a sus plugins, cuales puedes ejecutar ya que por defecto el usuario tiene acceso a ellos; estos comandos son `/plugins | /pl`, `/version | /ver`, o `/icanhasbukkit`, muchos configuradores suelen bloquear estos comandos quitando los permisos o simplemente utilizando un plugin que verifique el comando que estás enviando, en caso de ser el último podrías intentar saltártelo agregando el prefix del proveedor del comando que en este caso seria `bukkit`, junto al comando separados por dos puntos (`bukkit:version`, `bukkit:plugins`). También puedes notar si el servidor usa un plugin determinado mediante sus comandos, comportamiento o a simple vista si no editan mucho las configuraciones.

Hablando de los mods (Fabric, Forge); la metodología no cambia mucho además de que para establecer una conexión con este tipo de servidores debes tener los mods cliente-servidor que tenga el servidor.

### Conexión y reverse proxies

Al ser un protocolo de packets que funciona bajo TCP no existe una implementación nativa por parte de Mojang para correr el servidor detrás de un proxy, pero si existen no oficiales como TCPShield e Infinity Guard. Cloudflare Spectrum también puede ser usado ya que es una tecnología que ciertamente permite cualquier transporte TCP; puedes verificar de forma sencilla si haces conexión directa con el servidor o a través de un proxy simplemente efectuando un ping ICMP y comprobando la dirección en servicios como [ipinfo.io](https://ipinfo.io)

Sobre los DNS, los SRV record de este servicio tienen por nombre `_minecraft`:

`_minecraft._tcp.play.buzonmc.com`

*Ejemplo sencillo de uno*

### Estructura del servidor

Los servidores de Minecraft a veces suelen estar compuesto de más que un servidor o, un "Bungee".

A día de hoy, esta parte de la comunidad ha creado softwares para dividir la carga de conexiones a distintas instancias/replicas de un mismo servidor debido al alto coste de rendimiento que tiene correr un servidor con demasiados jugadores, de esta clase de software los más conocidos son MultiPaper y RedisBungee. Uno permite la sincronización de varios servidores para tener los mismos datos de plugins y mundos mientras que el otro sincroniza el número de jugadores y sus estados en multiples instancias de BungeeCord.

No hay una forma especifíca de saber si un servidor utiliza tecnologías y softwares de este tipo, pero viendo la estructura desde afuera y el comportamiento te puede dar ideas respecto a ello.

```bash
❯ dig @1.1.1.1 mc.universocraft.com

; <<>> DiG 9.18.14 <<>> @1.1.1.1 mc.universocraft.com
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 44233
;; flags: qr rd ra; QUERY: 1, ANSWER: 9, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;mc.universocraft.com.		IN	A

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

## Técnicas y vulnerabilidades comunes 

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

Un dato curioso es que mucha gente conocida como "griefers" suele buscar servidores de networks que no estén asegurados mediante escaneos de rangos de IP con herramientas como [QuboScanner](https://github.com/replydev/Quboscanner) para vulnerarlos mediante este fallo.

¿Podemos llevar esto a otro nivel además de simplemente spoofear la UUID de una cuenta con muchos permisos y buscar formas de elevar nuestro control?, depende mucho de los plugins que tengan instalados y como los tienen configurados.

**SOLUCIÓN:** Tienes dos formas de solucionar este problema

- Firewall: Si tienes un dedicado o VPS puedes establecer reglas de Firewall para impedir la entrada directa sin autorización a tus servidores conectados en la network, para ello obviamente debes tener un software de firewall instalado, hay varias guías por internet para poder hacer esto y también existe la [guía oficial de SpigotMC](https://www.spigotmc.org/wiki/firewall-guide/). Es muy recomendable que configures el firewall para que solo permita conexiones que coinciden con una regla que permite el acceso a un puerto especifico, 

*Hablando de IPv6 aségurate de que tu firewall también esté configurado para denegar conexiones que no coincidan con una regla en ese protocolo.*

- Plugins: Usando plugins puedes llegar a replicar algo parecido a un firewall haciendo que las instancias solo acepten conexiones de un BungeeCord que esté en cierta dirección o que presente un token o nonce en el handshake de la conexión. Los plugins más conocidos hasta ahora de este estilo son [BungeeGuard](https://github.com/lucko/BungeeGuard) y [SafeNET](https://github.com/dejvokep/safe-net), el problema con esto es que la instancia sigue aceptando la conexión y solamente deniega la entrada al servidor de Minecraft en sí, por lo que podrían meter bots o... utilizar algún fallo o desconfiguración que tenga el plugin para ganar acceso.

## Plugins 

Los plugins que tiene un servidor muchas veces puede ser un vector de ataque útil asi también como lo puede ser una mala configuración del BungeeCord, Spigot o de los mismos plugins.

Hay pocos casos de vulnerabilidades en plugins que te puedan permitir enumerar o explorar el sistema que corre el servidor ya que los programadores de plugins de Spigot no necesitan mucho de cargar archivos del sistema, hacer peticiones, ejecutar comandos del sistema... etc. Se conocen más casos de vulnerabilidades que permitirían a un adversario ganar permisos elevados solamente en el servidor de Minecraft.

También existen varios errores por parte de los configuradores de servidores y desarrolladores de plugins que puedes usar para obtener permisos de operador o bien enumerar el sistema que utiliza el servidor para correr, y hay funciones propias de los plugins que pueden ser abusadas o usadas para enumerar; aquí mostraré unos cuantos casos y funciones de plugins que te pueden dar una idea.

### Plugins con funciones de respaldos, carga de archivos... etc

Algunos de estos tipos de plugins te pueden permitir hacer cosas interesantes, pero muchos otros solo servirán para enumeración.

Por ejemplo, al exportar los permisos de LuckPerms, este plugin te dice donde guarda el archivo en forma de ruta absoluta. Con esto puedes llegar a saber quien o donde se ejecuta el servidor.

![LuckPerms](/assets/posts/minecraft-security/luckperms.png)

### BungeeServerManager y derivados

Este plugin te permite modificar los servidores que tiene el BungeeCord en su configuración, suena inofensivo, pero podría hacer esto para aprovecharme: Le digo a todos tus jugadores que entren a un servidor que agregué con el plugin y yo controlo, en este servidor puedo colocar un plugin que simule ser un servidor de autenticación (authlobby) y muchos sin pensar introducirían sus contraseñas, además de que obtendría sus direcciones IPv4.

### ServerUtils, PlugManX... etc

Con estos lo único que podrías hacer es simplemente desactivar y activar plugins, pero si tuvieras la posiblidad de subir un plugin malicioso, uno de estos te ayudará bastante.

### Plugins con sistemas para subir dumps, logs... etc

Te permitirán ver cierta información del sistema como la versión del sistema operativo, Java, RAM, núcleos e identificador del procesador, hay algunos como EssentialsX que al hacer un dump te muestran cierta parte de los logs del servidor (consola). En esta categoria también entran plugins como [Spark](https://www.spigotmc.org/resources/spark.57242/)

### Plugins que descargan o suben recursos

Estos plugins son aquellos que normalmente te permiten descargar configuraciones o recursos de la web que le especifiques, podrías usar esto para filtrar la dirección IPv4 verdadera del servidor si está detrás de un proxy reverso o un servicio como TCPShield/Infinity Filter o para enumerar puertos internos si es que te permite hacer peticiones a la misma máquina. Un ejemplo de estos plugins es el conocido CommandPanels.

### PlaceholderAPI

Este plugin de placeholders te permite descargar expansiones de un sitio llamado "eCloud", ciertas de sus expansiones como "Server" y "Pinger" pueden ser usadas para enumeración o filtrar información, y una que es muy interesante es la de "JavaScript"

![JS](/assets/posts/minecraft-security/jsexp.png)

Esta extensión tiene un comando que te permite ejecutar expresiones JavaScript a través de un comando que puedes ver claramente cual es, en la imagen de arriba. En sus versiones anteriores a la 2.1.2 no había ningún tipo de sandbox para el motor de JavaScript, esto te permitía hacer referencia a cualquier objeto de Java disponible, por lo que algo como:

`/jsexp parse me var a = Java.type("java.lang.Runtime"); a.getRuntime().exec("{COMMAND}")`

Te dejaba ejecutar comandos del sistema dentro del servidor de Minecraft.

### Plugins desactualizados

Si un servidor tiene plugins desactualizados, puedes buscar entre sus versiones a ver si la que corre el servidor tiene una vulnerabilidad sin parchar, como el Path Traversal de HolographicDisplays en versiones anteriores a la 2.2.9, el subcomando `sqlexec` de LiteBans que existe en versiones antiguas o el `/promote` y `/demote` de PermissionsEx.

### Módulos de BungeeCord por defecto

En la configuración por defecto, siempre está esta sección que le asigna un permiso especial al usuario md_5

```yaml
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
```
{: file='config.yml'}

Si un servidor tiene esto sin modificar puesto junto al módulo cmd_server, usa el sistema de permisos por defecto y su autenticación de usuarios es débil, podrías usar el comando /server para saltarte el sistema de autenticación del servidor. También puedes probar a entrar con el nick "md_5" e intentar saltarte la autenticación o enviar a otra cuenta fuera del servidor de autenticación.

### Plugins con WebServers

Los plugins de este estilo abren un servicio web que puede ser visto en puertos como el 8080, 8000 o el mismo 80 y 443, pueden tener comandos para agregar archivos a la web, usuarios o configurarla. (como `/plan register` de PlayerAnalytics).

### BungeeCommands

Si un servidor tiene un plugin de este estilo y solamente tienes el control de una modalidad, te puede ayudar para tomar control de todo el servidor.

### Software desactualizado

Usar una versión muy vieja del software de servidor puede traer vulnerabilidades, y la que puede ser la más peligrosa es el [CVE-2021-44228](https://cve.mitre.org/cgi-bin/cvename.cgi?name=cve-2021-44228). Por ejemplo la última build de la versión 1.16.5 de Purpur tiene este fallo sin parchear.

### CloudSystems

Estos sistemas funcionan como una interfaz para manejar varios servidores de Minecraft en una Network, uno de los más conocidos es [CloudNET v3](https://www.spigotmc.org/resources/cloudnet-v3-the-cloud-network-environment-technology.42059/). Es posible abusar de ellos si la cuenta comprometida tiene permisos para ejecutar comandos que permitan alterar la configuración de inicio o tareas de estos sistemas, ya que alguno de esos comandos te puede permitir alterar cosas como el ejecutable de Java o los parámetros de la JVM.

### Plugins custom

Contra plugins privados que tenga el servidor puedes probar los ataques típicos que intentarías ante algo, dependiendo de los comandos y funciones de este.

### Nota extra

Varios configuradores o dueños de servidores de Minecraft, por molestia se suelen dar el permiso "*" que en plugins como LuckPerms significa tener absoluto acceso a todos los comandos del servidor, incluyendo a esos de los cuales ni ellos mismos saben de su existencia. Lo mismo ocurre con el OP de Minecraft Vanilla que es conocido por usarse mucho en escenarios de elevar el control ya que varios configuradores siempre lo tienen habilitado a pesar de tener plugins de permisos como LuckPerms.

A pesar de que la mayoría de los plugins que se mostraron aquí son de utilidades o configuración, eso no excluye a los plugins de minijuegos, skills, parkours, SkyWars, BedWars, levels, economía... etc de ser propensos a vulnerabilidades, hay que mantenerlos actualizados o... ponerlos a prueba.

**RECOMENDACIÓN:** Intenta configurar bien tu servidor y mantén actualizados los plugins/mods, y da permisos a solamente lo que necesiten para administrar correctamente el servidor.

## Ataque encadenado

El servidor de Minecraft estará muy protegido pero no hay que olvidarse de los otros servicios que tenga expuestos. (Sitios web, APIs, Tienda, Foros... etc). Los otros servicios pueden tener vulnerabilidades como una SQLi/NoSQLi, XXE, LFI/Path Traversal, RCE o directamente un CVE con las cuales un atacante se podría hacer facilmente con tu servidor de Minecraft.

Vamos a tomar de ejemplo una API REST que te permite listar información de los jugadores del servidor, contaría con esta ruta, estoy basándome en una vulnerabilidad que encontré en la API de un servidor de Minecraft con una media de 100-130 jugadores; no diré nombre ya que los dueños aún no parchan el error:

`/api/user/:name`

El programador, pensando que no se podrían poner chars raros en la URI colocó la siguiente pieza de código por flojera:

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

Pero que pasa si te digo que puedes colocar carácteres raros en formato urlencoded... tal como espacios que el servidor web traduciría sin ningún tipo de fallos:

```
/api/user/'%20OR%201=1%20--%20-
```

{% highlight sql %}
SELECT name,uuid,money FROM users WHERE name = '' OR 1=1 -- -
{% endhighlight %}

![SQLi](/assets/posts/minecraft-security/sqli.png)

De aquí puedo volcarme toda la base de datos y, si el usuario que se usa para efecutar las peticiones SQL tiene acceso a otras bases de datos como puede ser la de AuthMe o tus otros plugins me las puedo volcar también. Dependiendo de las bases de datos y el contenido en estas podría llegar a obtener permisos administrativos en el servidor de Minecraft, y si la SQLi está en una query que altera valores más probabilidades tendrás de darte dichos permisos.

**RECOMENDACIÓN:** Simplemente usa el sentido común y sigue los consejos y recomendaciones de seguridad a la hora de hacer sitios web u otro tipo de servicios externos que se van a comunicar con tu servidor de Minecraft. Si te da miedo tener un servicio que crees que puede ser abusado al público exponlo solo a la red interna, crea una VPN o utiliza una tecnología como [Cloudflare Zero Trust](https://www.cloudflare.com/es-es/products/zero-trust/access/)

## Privilegios y entorno

Los privilegios que tiene el proceso del servidor pueden ser bastante aprovechables para los atacantes si encuentran una vulnerabilidad dentro del mismo que permitan interactuar con el sistema que lo corre.

El servidor de Minecraft se ejecuta con Java, y Java se ejecuta como un proceso normal del sistema, y ese proceso es ejecutado por un usuario, usuario que tiene permisos; cualquier comando o cambio que se haga en el sistema de archivos estará a nombre de ese usuario, lo que quiere decir que si ejecutan el servidor como Administrador o root todo lo que haga el servidor se hará con permisos de dicho usuario. 

Vamos a ponerte un contexto de ejemplo de un plugin custom que un desarrollador que trabaja para un servidor llamado "Mailbox Network" creó para ejecutar comandos del sistema ya que por alguna razón le era molesto entrar por SSH y usar comandos de Linux para meterse en el screen o contenedor del servidor.

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

Si yo obtengo acceso a una de las cuentas que puede ejecutar este comando o a la consola, puedo aumentar mi control como atacante sobre el sistema:

![Minecraft](/assets/posts/minecraft-security/privesc1.png)
![reverse shell](/assets/posts/minecraft-security/privesc2.png)

Ahora, imagina que el servidor lo está ejecutando root; puedo modificar a mi antojo lo que sea del sistema, desde borrar literalmente todo hasta meter un ransomware. Hay que tener en cuenta igual que al llevar a cabo algo como esto dejará al proceso principal del servidor congelado, en espera del proceso de la reverse shell en caso de que no se ejecute de forma asincrona, por lo que si es un servidor Spigot o uno de sus forks el servidor morirá en cuestión de segundos/minutos haciendo que a la vez tu reverse shell muera.

Ejecutar el servidor como otro usuario tampoco tiene caso al asunto si tiene asignado un permiso muy especial, como de este estilo en sudoers (sistemas Linux):

```bash
user ALL=(ALL:ALL) NOPASSWD: ALL
```

Vamos al caso de los contenedores, normalmente se suele usar Docker para mantener los servidores aislados de la máquina real, así no podrán causar perjuicios a esta en caso de que sean vulnerados. Paneles de gameservers como [Pterodactyl](https://github.com/pterodactyl/panel) usan el mismo software para mantener las instancias de los servidores aisladas del sistema real de los nodos que dicho panel maneja, pero aunque esté en un contenedor hay que tener cuidado.

Con ganar acceso a una consola interactiva del modo que sea recuerda que aún tengo la capacidad de tomar tus bases de datos ya sean locales o remotas, ya que para hacer funcionar los plugins con eso o dejan la base de datos en el servidor o dejan las credenciales para que los plugins se comunique con la(s) base(s) de datos. También alguien podría aprovecharse de los contenedores que tengas en la red de Docker, puertos internos o vulnerabilidades de los mismos para poder escaparme del contenedor y saltar a tu sistema real, sin embargo la posibilidad de que escapen de tus contenedores usando alguna vulnerabilidad del motor o utilizando otros contenedores en la red es baja ya que algunos paneles como Pterodactyl normalmente ejecutan los contenedores en una red distinta a la por defecto de Docker; las imágenes y configuración que usan estos contenedores están bien protegidos contra atacantes, todo depende mayormente de como tengas configurado todo.

Recuerda mantener actualizado el software, ya que por ejemplo una semana antes de la publicación de este post se descubrió que las versiones del controlador de contenedores de Pterodactyl ([Wings](https://github.com/pterodactyl/wings)) anteriores a la 1.11.6 instalaban los servidores en contenedores privilegiados, por lo que un atacante que pudiese modificar los scripts de instalación (conocidos como Eggs) podía hacerse con todo el sistema fácilmente.

En instalaciones de servidores en Windows Server igual hay que tener cuidado, hay que evitar usar el usuario `Administrador` para correr el servidor y seguir los consejos de seguridad de dicho sistema operativo, si es que por alguna razón usan dicho sistema para correr el proyecto de Minecraft.

**RECOMENDACIÓN:** Corre los servidores en contenedores bien protegidos o bajo un usuario que no tenga ningún tipo de permiso especial.

## Ingeniería social y OSINT

Que una administración tenga contraseñas fuertes y cuentas premium no sirve de mucho si la misma se deja engañar fácilmente por atacantes.

Hay muchos tipos de ataques de phishing que pueden tener éxito a la hora de comprometer un servidor, pueden ir desde enviarle correos de publicidad, cambios de contraseña falsos hasta hacer un servidor de Minecraft señuelo para que la víctima entre y coloque su contraseña con la suerte de que sea la misma que utiliza en el servidor objetivo, o incluso podrían decirle a los configuradores del servidor que implementen un plugin que "mejorará increíblemente la experiencia de los jugadores" pero dicho plugin en verdad es una puerta trasera o malware de los atacantes. Estos mismos señores que quieren comprometer tu servidor también pueden recurrir a bases de datos filtradas en las que se encuentran el nombre de usuario o correo de algún miembro de la administración.

Pero además de hacer Phishing o para llegar a hacerlo, los atacantes suelen usar [OSINT](https://es.wikipedia.org/wiki/Inteligencia_de_fuentes_abiertas) para poder identificar el servidor y verificar si existen datos sensibles de este publicados a lo largo de internet.

Veamos como se puede usar el OSINT para encontrar cositas interesantes, si hago esta busqueda por Google usando el dork `intitle`

`intitle:"Index of" spigot.yml`

Puedo encontrar unos cuantos resultados de páginas con el listado de directorios activado que contienen un archivo llamado "spigot.yml"

![Files](/assets/posts/minecraft-security/files1.png)

Usando páginas de historial de records DNS de los dominios podría llegar a obtener las direcciones IPv4 verdaderas de la máquina de tu servidor protegido con algún proxy reverso/honeypot si las tuvistes asignada a tu registro DNS durante un tiempo y no las has cambiado.

![DNS](/assets/posts/minecraft-security/dns.png)

Con buscadores como Shodan o Censys se puede indagar para encontrar servidores con servicios interesantes. Utilizando el dominio del servidor de Minecraft puede que encuentres algo que te llame la atención y podrías hasta encontrar la IPv4 real de un servidor que está bajo un reverse proxy.

![Server search engines](/assets/posts/minecraft-security/censys.png)

Con esta forma de búsqueda obviamente alguien podría obtener una dirección de correo personal o nombre real para poder intentar hacerse con las cuentas mediante Phishing.

**RECOMENDACIÓN:** Se bastante precavido con la información que publicas a internet y los enlaces, correos y formularios de autenticación que te llegan o a los que entras.

## Logs y detención

Efectuar enumeración y explotación de vulnerabilidades en muchos servicios deja sus trazas, y el servidor de Minecraft no es la excepción.

Cuando una persona abusa del IP Forwading normalmente suele spoofear la IP "127.0.0.1" y no se nota ninguna conexión anterior desde el Proxy hacía la modalidad en la que está, como vimos en las primeras imágenes del post son capaces de colocarse hasta IPv4 inválidas y spoofear la UUID de un administrador.

Ciertas veces explotar vulnerabilidades puede dejar errores en los logs del servidor que a un administrador le puede llamar la atención, más si lo que colocas para explotar la vulnerabilidad tiene un error. Tampoco está demás decir que bastantes servidores tienen habilitado por defecto el log de comandos por lo que cualquier comando que ejecutes se verá reflejado en la consola, los únicos software que vienen con esto deshabilitado por defecto son BungeeCord y Velocity junto a sus forks.

![Logging](/assets/posts/minecraft-security/logging.png)

*Alguien entra para intentar ejecutar un comando, y luego sale*

También pueden haber plugins que te saquen del servidor al hacer un comportamiento extraño y dejen una alerta en la consola o a los mismos administradores, o honeypots en la red del servidor. Es casi imposible que logres un sigilo al 100% cuando vulneres un servicio, pero ciertamente debes intentar ser lo más cauteloso posible para no dar alertas grandes o tumbar accidentalmente el servidor si estás haciendo una prueba de penetración.

## Resumen

Un servidor de Minecraft, como cualquier otro servicio tiene sus formas de ser aprovechado incluso para llegar a tomar control total del sistema que ejecuta el servidor, todo depende bastante de como lo tengas montado, configurado y de como lo administren. Aunque la mayoría de los que se dedican a vulnerar este tipo de servidores solo les gusta grabar un vídeo de 5-10 minutos con música mala mostrando como rompen los cubos con WorldEdit o `/fill` es importante que mantegas la seguridad de tu servidor de la mejor forma posible, ya que también pueden llegar a filtrar tus archivos y bases de datos para luego proveerlos desde [programitas](https://www.youtube.com/watch?v=SYTFx88qGZo&t=95s&pp=ygUJU2VyTGluazA0) o directamente subirlos a sus canales de Telegram.

Si sientes que falta información aquí o algo está mal, puedes hacérmelo saber por mis redes sociales.

## ¿Y en cuanto a Bedrock Edition?

No me apetece hacer una sección dedicada a dicha edición del videojuego dado que no tengo mucho conocimiento respecto a esos servidores.
