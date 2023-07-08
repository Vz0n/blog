---
categories: ["Posts", "Guias"]
title: "Firewall de Windows"
description: "Mira bien que tipo de red seleccionas."
tags: ["Windows", "Firewall", "Seguridad"]
logo: "/assets/posts/wfirewall/logo.png"
---

Seguramente siempre que te conectas a una red con tu computador personal y usas Windows este te pide que selecciones el tipo de red a la que te estás conectando, algunas personas no le suelen dar atención a esto y siempre seleccionan la opción de pública o privada porque piensan que esto es un simple cosmético pero en verdad no es así.

Este post lo escribo porque he visto a personas que eligen estas opciones al azar.

## Un poco de información

![Network schema](/assets/posts/wfirewall/network-schema.png)

*Estructura de la red en la que estaré haciendo pruebas*

Cuando tu seleccionas el tipo de red a la que te conectas ya sea WiFi o cableada en realidad le estás diciendo a tu equipo como se debe "comportar" con las conexiones mientras está dentro de la red.

El comportamiento se determina por perfiles de red del Firewall, estos contienen reglas predefinidas que deciden si bloquear o dejar pasar conexiones entrantes o salientes. Windows viene con 3 perfiles pre-configurados:

- **Perfil público**: Tu equipo no expondrá ningún puerto a la red. En ciertas configuraciones y versiones de Windows también deja a tu equipo casi indetectable bloqueando la entrada de Pings (tramas ICMP). Si una aplicación abre un puerto o intenta comunicarse con la red local el Firewall te saltará para decidir si añadir una regla para esta o no.

- **Perfil privado**: El equipo permitirá conexiones a puertos comunes (Entre ellos el 135 y 139) mientras esté en este perfil, aunque el Firewall igual te saldrá si una aplicación intenta hacer ciertas operaciones de red.

- **Perfil de dominio**: Es parecido al privado solo que este es usado normalmente cuando tu ordenador esté dentro de una red que lleva un entorno de [Active Directory](https://es.wikipedia.org/wiki/Active_Directory).

En esta imagen podemos ver que pasa si intentamos hacerle ping al equipo LAPTOP si tiene el perfil público o privado:

![Public and private](/assets/posts/wfirewall/ping.png)

Estando en público el equipo no recibirá conexiones pero en privado o dominio si lo hará.

¿Puede representar un riesgo de seguridad estar exponiendo ciertos puertos? sí, pero lo que podrán hacer depende de la versión de Windows que tengas, que otros puertos tengas abiertos y como tienes configurados los usuarios en tu equipo. En versiones recientes de Windows 10 el perfil privado solo expone los puertos TCP 139 y 135 pero de una forma limitada.

Digamos que por casualidad yo sé la contraseña de uno de los usuarios del equipo LAPTOP y este tiene el perfil privado activado sin modificar; si me intento autenticar en el 135 ([MS-RPC](https://learn.microsoft.com/es-es/windows/win32/rpc/rpc-start-page)) pues... no hace nada más que sacarnos por timeout:

```bash
> rpcclient -U L##### -I 192.168.0.106 ncacn_np
...
Cannot connect to server.  Error was NT_STATUS_IO_TIMEOUT
```

Esto sucede porque en el perfil privado no están activadas las reglas del puerto 135 que nos permiten llamar procedimientos almacenados en el equipo. Sin embargo los procedimientos que puedes habilitar a traves del Firewall son pocos porque no podremos ni enumerar usuarios.

Dejando de lado eso, intentando enumerar por el puerto 139 ([NetBIOS](https://es.wikipedia.org/wiki/NetBIOS)) no nos da otra cosa más que el nombre del equipo y su MAC:

```bash
> nbtscan 192.168.0.106
Doing NBT name scan for addresses from 192.168.0.106                                                                                                  IP address       NetBIOS Name     Server    User             MAC address
------------------------------------------------------------------------------
192.168.0.106    DESKTOP-UU8990  <server>  <unknown>        c4:d9:**:**:**:**
```

Vale, se ve que en versiones nuevas de Windows 10 el perfil privado tiene sus protecciones pero obviamente sigue siendo bastante recomendable usar el perfil público en redes públicas.

Existe otro puerto para un servicio llamado SMB ([Server Message Block](https://es.wikipedia.org/wiki/Server_Message_Block) - 445); se usa para compartir archivos, impresoras y otras cosas, por lo que ¿algo podría pasar si por alguna razón tengo expuesto este puerto en algún perfil que no sea privado?... Pues en versiones recientes de Windows 10 si activas la regla del Firewall que permite conexiones a este servicio e intentas autenticarte te otorgará acceso pero a básicamente casi nada:

![SMB](/assets/posts/wfirewall/smb1.png)

*En SMB se comparten los archivos a través de Shares/Disks (Traducido al español unidades)*

Solamente podemos ver cosas del IPC pero no se suele encontrar algo interesante ahí.

Extrañamente en versiones viejas de Windows 10 si obtenías las credenciales de un usuario y era administrador... pues el SMB (MS-RPC también) no se negaba a nada:

![XD](/assets/posts/wfirewall/admin.png)

Ya con esto era simplemente usar alguna herramienta como [psexec](https://github.com/fortra/impacket/blob/master/examples/psexec.py) y obtenías acceso completo al computador si este no posee un antivirus fuerte, igualmente sin poder obtener una consola interactiva podrás modificar archivos en las unidades, y mira que el recurso "C$" contiene todos los archivos del ordenador.

Bajando más de versión, en Windows 7 existia un share especial llamado `Users` y ganando acceso con cualquiera de los usuarios que existan en el equipo tendrás permisos de lectura en este ¿y qué tiene? pues todos los directorios personales de los usuarios, vamos a verlo en el equipo de John

![Users](/assets/posts/wfirewall/smb2.png)

Podemos leer cualquiera de los archivos de John entonces...

Recalco que a todas estas cosas solo puedes acceder si tienes una credencial válida, y también debo decir que si el usuario no tiene contraseña Windows (al menos en el 7 y 10) se negará a darte acceso a los recursos con la razón `NT_STATUS_ACCOUNT_RESTRICTION`. También existe el usuario Guest (Invitado) pero con esa cuenta no vas a lograr nada a menos que tenga algún permiso especial asignado, pero aún así existen formas de acceder al equipo sin saber ni una pizca de informacíón acerca de los usuarios, y es a través de vulnerabilidades de Windows. Aquí es cuando entra en juego la versión del sistema operativo y para ponerles un ejemplo:

En mi país las netbooks del gobierno normalmente son llamadas por el nombre de "Canaimitas", son equipos nada potentes que apenas pueden soportar Windows 7 Professional, por esto vienen pre-configuradas con un sistema Linux llamado Canaima (Sí, Venezuela tiene su propia distribución GNU/Linux basada en Debian). Pasa y acontece que este intento de hacer usar a la gente software libre no funcionó como esperaban y usando USBs se podía formatear el equipo e instalarle Windows, pero las versiones que se le instalaban a estas netbooks eran "MiniOS" para que pudieran correr sin problemas en un hardware tan limitado.

La versión MiniOS del 7 tiene un detalle que podría decir casi nadie sabe y es que la versión de Windows que utiliza es vulnerable al MS17-010 o bien conocido como [EternalBlue](https://es.wikipedia.org/wiki/EternalBlue). ¿Qué tan peligroso puede ser? míralo en un vídeo:

<iframe class="video" width="560" height="315" src="https://www.youtube.com/embed/5KczMJGd418" title="YouTube video player" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

*Desconozco si las diferentes versiones MiniOS son vulnerables a este fallo o a otros pero lo más seguro es que las nuevas no lo sean*

Sí, con solo poder conectarse al servicio SMB de un equipo vulnerable ya es posible que te comprometan todo el equipo. Usé la misma versión MiniOS del 7 para el vídeo

¿Es complicado de explotar? Esta vulnerabilidad se trata de una ejecución remota de comandos causada por tres bugs en como Windows trata los mensajes del protocolo SMBv1/SMBv2 lo cual si es complicado de explotar... pero gracias a herramientas como MetaSploit y el script que utilizé en el vídeo se hace más sencillo, y con MetaSploit es aún más sencillo porque solamente tienes que introducir unos 3-4 comandos conociendo poco y ya.

Para protegerte de estos ataques simplemente debes usar el sentido común: mantén tu sistema y aplicaciones actualizados, usa contraseñas robustas, mira las propiedades de la red a la que está conectada tu equipo e intenta no usar versiones no oficiales de Windows. Sé que en los paises de LATAM pocos se pondrían a molestar con esto por desconocimientos de los temas pero es mejor prevenir que lamentar sabiendo que seguramente muchas redes públicas tienen mala seguridad, y recordemos que existen los [Script Kiddies](https://es.wikipedia.org/wiki/Script_kiddie).

### ¿Por qué las IPv4 que muestras en el vídeo son diferentes a las de las imágenes?

El router que utilizo asigna las direcciones por DHCP. Estuve haciendo el vídeo, tomando las imagenes y escribiendo en diferentes lapsos de tiempo, quería hacerlo lo más conciso que pudiera pero fallé en lo de las IP.














