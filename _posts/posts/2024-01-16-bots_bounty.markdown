---
title: "Bounty de bots"
description: "Unas experiencias que tuve y bugs que encontré mientras intentaba buscarle vulnerabilidades a bots de Discord."
tags: ["Dyno", "CactusFire", "Web vulnerabilities"]
categories: ["Posts", "Historias"]
logo: "/assets/posts/bots_bounty/logo.png"
---

Hace unas semanas, comenzando el año estuve buscando vulnerabilidades en los paneles de ciertos bots de Discord para mirar que tan asegurados estaban, me topé con dos que la verdad llamaron mi atención al ser bots tan grandes y tener unas fallas que aunque no sean muy nocivas, para el alcance de bot es algo muuy potente.

La semana en la que descubrí estos fallos fue durante la primera semana de Enero de, y ya pasadas unas dos semanas desde que los descubrí vale la pena que hable un poco sobre ellos.

## 1 - Dyno's IDOR

> IDOR (Del inglés, Insecure Direct Object Reference), es una vulnerabilidad en la cual el software no regula o restringe el acceso correctamente a recursos a los que el usuario no debería poder ver ya sea por falta de permisos o propiedad.
{: .prompt-info }

El panel Web de Dyno es uno bastante intuitivo, con colores atractivos que ofrece opciones para configurar el comportamiento del bot dentro de una guild de Discord via web:

![Dyno's panel](/assets/posts/bots_bounty/dyno_panel.png)

Dentro de la parte de módulos podemos encontrar varias partes del bot para configurar como el AFK, auto-purge, moderación, diversión, starboard, comandos personalizados... etc, algunas opciones son premium pero la mayoría son gratis.

Hay una opción que se llama "Auto Responder" que te permite ajustar mensajes a los cuales Dyno deberá responder con un texto de tu preferencia según alguna palabra o frase que tenga dicho mensaje

![Autoresponder](/assets/posts/bots_bounty/autoresponder.png)

Esto es mayormente usado por los administradores para dejar que el Dyno responda preguntas que el staff del servidor ya está casando de responder y es algo que se consulta frecuentemente

![IP](/assets/posts/bots_bounty/ipmc.png)
*Responder a preguntas por la IP del servidor de Minecraft es uno de los casos típicos de uso*

Bien, si bien aquí no hay nada inofensivo; existe una opción del bot que se llama "Wildcard" y básicamente en vez de enviar solo si el mensaje contiene la palabra, el bot buscará por la palabra en todo el mensaje y si la encuentra, responderá. Puedes también en vez de poner palabras solo poner letras como todas las consonantes, y con eso el bot responderá básicamente a casi cualquier mensaje que se envie al servidor.

También puedes agregarle embeds o reacciones al mensaje que coincida con o tenga la palabra, por lo que podrías hacer una especie de "raid improvisado" colocando cosas... indebidas.

Ahora bien, si intercepto la petición HTTP que hacemos cuando le damos a guardar enlace con una herramienta como BurpSuite, veré este JSON:

```json
{
    "command":{
        "id":"<server-uuid>",
        "guildId":"<discord-server-id>",
        "command":"ip",
        "type":"message",
        "response":"La IP del servidor es vzondev.cf.",
        "wildcard":true,
        "ignoredChannels":[],
        "allowedChannels":[],
        "ignoredRoles":[],
        "allowedRoles":[],
        "reactions":[],
        "choices":[]
        }
}
```

Si intentaba poner en los parámetros cosas que no se deberían poder como otros tipos de datos, algunas veces funciona y otras veces no, y si le cambiaba el campo `guildId` a... otra guild externa curiosamente mi respuesta automática que he creado no aparecía o dejaba de aparecer en caso de que estuviese editando, ¿qué significa?

Yendo a la guild cuya ID fue la que pusimos en la petición HTTP alterada, pues me topo con que...

![When](/assets/posts/bots_bounty/when.png)

El mensaje se agregó correctamente a otra guild que no me correspondía, e incluso podía seguir agregando respuestas automáticas sin problemas a otras:

![Discord 1](/assets/posts/bots_bounty/dc1.png)
*Servidor de un YouTuber de RimWorld*

![Discord 2](/assets/posts/bots_bounty/dc2.png)
*Lo chistoso de este servidor es que a día de hoy no han removido ese mensaje*

![Discord 3](/assets/posts/bots_bounty/dc3.png)
*Este es uno grande actualmente Partner de Discord, si reconoces a los miembros y eres de ahí pues, reclamo autoridad del "raid"*

La única desventaja (o lado positivo) que tenía esta falla es que no podías hacer everyone, intenté dentro de mi propio servidor y no funcionaba por algún motivo.

Fuera de esto, la respuesta del staff de Dyno en torno a esta vulnerabilidad fue bastante amigable para ser sincero:

![Dyno's staff response](/assets/posts/bots_bounty/dynoresp.png)

El bug fue parcheado al solamente pasar 12 horas desde que lo reporté, el endpoint vulnerable ahora ignoraba el campo `guildId`, lo que hacía imposible ponerle otra cosa ahora. Algo bastante bueno por parte del equipo de desarrollo del Dyno a mi parecer.

## 2 - CactusConfession

CactusFire es un bot de diversión creado por unos desarrolladores de bots de Discord con la finalidad de dar un bot miltipropósito en entretenimiento para los diversos servidores de Discord hispanos, aunque ahora también se está expandiendo a la norteamericana.

El bot tiene un dashboard... algo limitado:

![Cactus dashboard](/assets/posts/bots_bounty/cactusfire.png)

Pero hay ciertas opciones que nos permite cambiar el dashboard, como el canal al que se van a enviar las confesiones, reviews y sugerencias; si intercepto las peticiones que se hacen cuando guardo uno de estos ajustes veré este JSON:

```json
{
    "data":
    {
        "confessionsChannel":"1003421312036896848","adminConfessionsChannel":"1003421311554564172"
    }
}
```

Si pongo datos inválidos en la petición, podré ver que este servidor no programó bien sus middlewares de [Express](https://es.wikipedia.org/wiki/Express.js) y me filtrará... algo de información.

![Information leak](/assets/posts/bots_bounty/cactusleak.png)

Fuera de eso, intenté colocar la ID de un canal de un servidor ajeno al mio; funciona. Si intento efectuar la función que tiene configurada la ID de ese canal en vez de fallar diciendo que el canal no existe, me envió la confesión al servidor al que pertenezca dicho canal que coloqué:

![XD](/assets/posts/bots_bounty/cactusconfession.png)
*Otra vez, el servidor del YouTuber de RimWorld*

No es una falla del mismo nivel que la del Dyno ya que estabas limitado a solo embeds y no podías siquiera hacer mucho spam, pero si es algo molesto huh.

A las horas de descubrirla, la reporté al equipo de desarrollo del bot y tardaron no menos de 2 horas en resolver el problema. Me pareció bastante extraño que el bot hiciera eso en vez de simplemente decirme que el canal no existia o estaba mal configurado, pero tal vez eso ya sea tema de la librería que usa para comunicarse con la API de Discord.

## Resumen

Las vulnerabilidades que encontré aunque bien no me permitían hacer algo tan letal como darme administrador en los servidores, podían seguir teniendo cierto impacto y más en la reputación de los dos bots, que bien sabemos tienen una bastante buena.

En fin, eso era todo lo que quería comentar acerca de estas dos experiencias. Seguiré indagando entre los bots a ver si encuentro más para contar.