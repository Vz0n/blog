---
title: "Bots Bounty 2"
description: "Otra travesía buscando bugs y fallos de seguridad en los bots de Discord"
tags: ["XSS", "Server side request path traversal", "Prototype Pollution", "IDOR", "Information leak"]
categories: ["Posts", "Stories"]
logo: "/assets/posts/bots_bounty2/logo.png"
---

(El logo del post viene de [Flaticon](https://www.flaticon.com/free-icons/bot))

Hace un año que no volví a subir posts acerca de este tema, pero en estos días me dió por volver a intentar hacer una Bots Bounty y... logré encontrar cosas interesantes. Explicaré que cosas encontré y en cuales bots.

Si quieres mirar la primera parte, [haz click acá](/posts/bots_bounty)

## Server side request path traversal - Wick

Creo que esta es la vulnerabilidad más insana que he encontrado en bots de Discord hasta ahora.

[Wick](https://wick.bot) es un bot de seguridad que posee utilidades de moderación y para combatir raids, spam y demás, y tiene para una subscripción premium con incluso más ventajas. El dashboard de este bot se ve bastante atractivo.

![Wick dashboard](/assets/posts/bots_bounty2/wick_dash.png)

Teniendo un plan gratuito, tenemos de por si acceso a varias cosas

![Wick free](/assets/posts/bots_bounty2/wick_free.png)

Buscando por vulnerabilidades, me topé ví que la parte de edicción de las reglas del automod de Discord enviaba esta petición por POST al hacer click en "Save":

```json
{
    "data":
    [
        {
            "id":"<id>",
            "guild_id":"<id>",
            "creator_id":"536991182035746816",
            "name":"<name>",
            "event_type":1,
            "actions":[
                {
                    "type":1,
                    "metadata":{}
                }        
            ],
            "trigger_type":1,
            "enabled":true,
            "...": "snip"
        }
    ]
}
```

Curiosamente, si le colocaba algo como un hashtag (#) al parámetro `id`, la petición seguia funcionado, por lo que se me vino a la idea de que esto podría estar enviando una petición con esta ID a uno de los endpoints de Discord para cosas del automod, especificamente:

`/api/v10/guilds/<id>/auto-moderation/rules/<rule-id>`

Si esto es como funciona y la aplicación simplemente está concatenando el parámetro `id` a la URL final, entonces podriamos utilizar secuencias para retroceder de directorio (../) para ir atrás y poder enviarle peticiones a otros endpoints de la API de Discord. Al probar a enviarle esto en el parámetro id:

`../rules/<rule-id>`

Seguía funcionando, y dejaba de funcionar si le cambiaba algo a la ruta, por lo que básicamente podía controlar a donde esto enviaba la petición. Siguiendo esto entonces yo podría mandar estos datos a otra parte, podría por ejemplo... editar reglas de auto moderación que no estén en mi servidor. Metiendo el Wick en otro servidor y creando una regla de auto moderación con otra cuenta mía distinta probé a enviar:

`../../../<guild-id>/auto-moderation/rules/<rule-id>`

y para mi sorpresa:

![Uh oh](/assets/posts/bots_bounty2/wick_uh.png)

¡Pude editar una regla de moderación en otro servidor!, sin embargo esto no era mucho porque requería del ID de la regla y encima son solo eso, reglas. Asi que me puse a ver la documentación de la API de Discord para las reglas de automoderación y me doy cuenta de que estos mismos campos están especificados en la petición de más arriba... ¿será que la aplicación solamente está re-enviando el JSON extra que le pongas en la petición a Discord? porque de ser así, si yo logro ir a la raíz de la ruta de la API (`https://discord.com/api/vx/`) básicamente **podría enviar peticiones a cualquier endpoint de edición**, ya que la API de Discord ignora los fields que no sean leídos por el endpoint respectivo y el método HTTP de la petición para editar una regla de moderacíon es `PATCH`. Sumándole que Wick requiere permisos de administrador por defecto esto significaría que de ser cierto, **podría raidear cualquier servidor en el que esté Wick.**

Entonces, intenté cambiar la petición a `../../../../guilds/<id>` y colocar en el campo `name` un nombre que sería colocado como nombre del servidor en caso de que todo esto fuese cierto ([ver documentación de la API](https://discord.com/developers/docs/resources/guild)). En un principio al hacerlo no me resultó, pero me di cuenta que si colocaba `../` más de 3 veces seguidas en la URL no funcionaba, entonces simplemente cambié la petición a algo más feo como `../../../id/../../guilds/<guild-id>` y:

![Wick_pwned](/assets/posts/bots_bounty2/wick_pwned.png)

¡Et voila! y para terminar de confirmar le agregué un campo `description` siguiendo la documentación de la API y lo que veía era muy evidente:

![Wick_pwned2](/assets/posts/bots_bounty2/wick_pwned2.png)

Mi hipótesis inicial era cierta, y con esto puedo editar hasta el nombre, descripción y foto de perfil del bot junto a los atributos de aplicación (del Discord developer portal). Es un poder muy grande sabiendo la confianza que le tienen a este bot.

Reportando el fallo, en un principio me dijeron que lo hiciera en un canal público y de ahí lo eliminaban y le notificaban al desarrollador del bot sobre el bug. Se tardaron unas horas pero lo arreglaron.

![Wick fixed](/assets/posts/bots_bounty2/wick_fixed.png)

Sin embargo por pasarme de listo no me dieron una gran parte de la recompensa, porque modifiqué nombres de algunos servidores en los cuales no tenía consentimiento para hacer tal cosa (consejo para cuando estés haciendo estas cosas, no intentes nada raro si no quieres perder la recompensa)

**La recompensa fue de 100$**

## Stored XSS - Lawliet

[Lawliet](https://lawlietbot.xyz) es un bot multipropósito con varios comandos, principalmente de entretenimiento. Varias partes tienen su código fuente publicado en el GitHub del desarrollador.

La página web de este bot está programada enteramente en un plataforma de Java llamada Vaadin.

El bot tiene algunas partes en las que podemos subir un archivo, especificamente una imagen:

![Image upload](/assets/posts/bots_bounty2/lawliet_upload.png)
*Esta es la parte de mensajes de bienvenida/ida*

El único detalle al interceptar peticiones acá es que Vaadin tiene un diseño de software similar a Blazor; nuestro navegador tiene que mantener una conexión activa con el backend ya que cada movimiento que haces en la web como presionar algo y demás, es enviado como un evento a Vaadin, y si existe una reacción (listener) de ese evento, en esa parte especifíca, Vaadin ejecutará el respectivo listener, mutará el DOM de ser necesario y dichas mutaciones serán enviadas a nosotros como respuestas a los eventos. Esto significa que tendremos que ser rápidos al editar la petición porque de lo contrario, el sitio perderá el vínculo y nuestra petición ya no funcionará.

Entonces, mirando la petición que se efectua cuando seleccionamos una imagen veo lo siguiente:

```bash
-----------------------------88073330513477986272418408347
Content-Disposition: form-data; name="file"; filename="uwu.png"
Content-Type: image/png

... [image data]

-----------------------------88073330513477986272418408347--
```

Esto se ve bastante regular, sin embargo, si le cambio la extensión a otra cosa como un `.js` y le coloco texto normal en vez de una imagen al archivo, me lo subirá también, y si vemos el enlace de lo que se ha subido al CDN veremos que en el header `Content-Type`:

```bash
< HTTP/2 200 
< date: Sat, 04 Jan 2025 22:51:21 GMT
< content-type: text/javascript;charset=utf-8 <------
< content-length: 7
< cache-control: max-age=14400
< last-modified: Sat, 04 Jan 2025 22:50:39 GMT
< cf-cache-status: HIT
< age: 31
< accept-ranges: bytes
< report-to: {"endpoints":[{"url":"https:\/\/a.nel.cloudflare.com\/report\/v4?s=NfEkVwYvzuYSx5gXRu2Zmjahc04FCbi44o82UApdfPJ9VN3nk%2B5r7woBCEYm4PcNr%2FomDecX9aZUTjawWpfr9an0BTXtM2IvAVnyFl%2B0r9jbclD3JNp6jGHWaPk04MulMQ%3D%3D"}],"group":"cf-nel","max_age":604800}
< nel: {"success_fraction":0,"report_to":"cf-nel","max_age":604800}
< server: cloudflare
< cf-ray: 8fcecaf55d45d9c1-MIA
< alt-svc: h3=":443"; ma=86400
< server-timing: cfL4;desc="?proto=TCP&rtt=97216&min_rtt=96601&rtt_var=37456&sent=6&recv=6&lost=0&retrans=0&sent_bytes=3435&recv_bytes=765&delivery_rate=41369&cwnd=129&unsent_bytes=0&cid=549b53d098d812ac&ts=135&x=0"
< 
uwuowo
* Connection #0 to host lawlietbot.xyz left intact
```

El CDN le está colocando el `Content-Type` correspondiente a la extensión y tampoco verifica si el contenido del archivo es realmente una imagen... entonces, ¿qué pasaría si subo un archivo HTML? Si logro subirlo, sabiendo que los archivos están en `https://lawlietbot.xyz/cdn/<directorio>/` básicamente tendría un vector de XSS para hacer cosas maliciosas.

Pero al intentar subirlo inicialmente, me percato de que hay un WAF:

![WAF](/assets/posts/bots_bounty2/lawliet_waf.png)

Analizando un poco, ví que filtra por cualquier expresión que llame a una función sospechosa como `alert`, pero si se la asigno a una variable y agrego un CRLF en medio del script ya que también parece que no le gusta contenido entre comillas, ahora obtendré un `200 OK`:

![WAF Bypass](/assets/posts/bots_bounty2/lawliet_waf_bypass.png)

Cambiando la extensión a html y subiendo el archivo, al ir enlace que se ha generado para la "imagen":

![XSS](/assets/posts/bots_bounty2/lawliet_xss.png)

Tenemos un XSS almacenado acá. Y viendo que el fallo reside en como esto guarda los archivos básicamente podemos abusarlo en cualquier parte que permita subir una imagen. También he de notar que esto ha sido posible sin importar la CSP debido a que esta permite colocar JavaScript inline por medio de la etiqueta `<script>`.

Al reportar la vulnerabilidad, me comentaron que la estarían viendo después. Luego verifiqué y parece que en la parte del CDN el dev ha colocado una condición para que el nginx solamente acepte y retorne ficheros con extensión de imagen, de lo contrario tirará un `403 Forbidden`:

![Forbidden](/assets/posts/bots_bounty2/lawliet_xss_fixed.png)

No sé si esto sea temporal, pero lo ideal sería que el backend simplemente verifique si lo que se sube es *realmente* una imagen.

**No hubo recompensa**

## Lack of input validation, server side request path traversal & information leak - Sapphire 

La gravedad de estos fallos es bastante pequeña en comparación a la de Wick, dado que este bot utiliza un caché para acelerar sus operaciones de edición y demás.

[Sapphire](https://sapph.xyz/), al igual que Lawliet es un bot multipropósito mayormente enfocado a temas administrativos de un servidor de Discord como moderación, auto-roles, mensajes de bienvenida... etc.

Al ir a `https://dashboard.sapph.xyz` e iniciar sesión usando Discord tendremos acceso a un dashboard para nuestro servidor bastante bonito e intuitivo

![Sapph Dashboard](/assets/posts/bots_bounty2/sapph_dash.png)

Después de probar y probar, me di cuenta de que esto parecía estar bien asegurado por detrás, pero viendo más a fondo los mensajes de error (por ejemplo, el 404) me di cuenta de que al final de todo, dentro de un tag agregado por Svelte (framework que utiliza la web) para el server side rendering se filtraba el directorio en el que estaba corriendo el servidor... aunque esto no es muy relevante.

Luego de eso, estaba que en algunas rutas como `/api/v1/discord/bots/channelsmsgs-<id>` pasaba lo mismo que en el caso de Wick; esto simplemente colocaba un parámetro de nuestra petición dentro de una petición sin verificación ni nada, por lo que en la ruta que dí arriba por ejemplo, podía leer mensajes de canales privados a los que el bot tuviese acceso utilizando la propia API de Discord:

![Sapph leak 2](/assets/posts/bots_bounty2/sapph_dash_leak2.png)

Ciertamente es un poco inútil pero pensando lo que la gente llega a colocar en los mensajes y que el ID de los mensajes se basan mayormente en timestamps, al mismo tiempo no lo es tanto.

También ví la función que tenía el dashboard para crear un kit de mensajes, que básicamente funciona de forma similar a los archivos de lang que vienen en varios plugins de Spigot (Minecraft): Tu editas los mensajes por defecto del bot, los guardas en el kit y luego con el enlace generado puedes transferirlos a donde quieras, y encontré pequeños errores por falta de validación, por ejemplo en los enlaces de embeds podías colocar cualquier cosa arbitrariamente, incluyendo enlaces de JavaScript como `javascript:alert(1)`, y en la vista previa de los embeds podías hacerle click a eso sin ningún problema.

![Sapph XSS](/assets/posts/bots_bounty2/sapph_xss.png)

Del resto, no logré hallar otra cosa.

Reportando los fallos, el dev de mantenimiento me comentó que le pasaría el problema al leader y este me atendió en una hora. Me dió como recompensa una subscripción del bot que te permitía tener tu propia instancia y otras carácteristicas premium, pero pedí el equivalente a eso que serían 52 dólares.

**La recompensa fue de 52$**

## IDORs - Nekotina

(Si eres angloparlante y estás leyendo esto traducido) [Nekotina](https://nekotina.com) es un bot multipropósito diseñado con el enfoque principal de entretenimiento. Es **prácticamente el bot más utilizado en servidores de habla hispana**, es un must-have en las comunidades hispanas debido a sus comandos de rol y la entretenida economía y minijuegos que posee.

El dashboard del bot es bastante bonito e intenta ser lo más intuitivo posible para el usuario:

![Neko dash](/assets/posts/bots_bounty2/neko_dash.png)

Buscando por vulnerabilidades vi que esto validaba *bastante bien* lo que le pasabas, me la estuvo poniendo muy complicada muchas veces... hasta que me di cuenta de unos detalles.

Habían ciertas partes de la página en las que se usaba las UUID para asignarle un identificador a los objetos... pero en otras usaba [BSON](https://www.mongodb.com/resources/basics/json-and-bson)

![UUID](/assets/posts/bots_bounty2/neko_uuid.png)
![BSON](/assets/posts/bots_bounty2/neko_bson.png)

Me entró la curiosidad y me dió por probar a ver si existía algún IDOR acá, primeramente probé en la sección del constructor de mensajes para ver si podía cargar datos de otros servidores, y copiando el BSON de un mensaje de mi servidor y poniéndolo en la petición de otro pues ví que si podía cargarlos:

![Uhmmm](/assets/posts/bots_bounty2/neko_idor1.png)
![UHMMM](/assets/posts/bots_bounty2/neko_idor2.png)

También podía eliminarlos... ví que pasaba lo mismo para las etiquetas o tags del servidor pero con la diferencia de que aquí si podía editarlos.

![Tag](/assets/posts/bots_bounty2/neko_tags.png)

Me puse a ver y parece que esto estaba presente en otras secciones del panel por igual, y recontandolas obtuve que estaba presente en estas secciones y funciones:

1. Automatización -> Mensajes recurrentes: Presente en la función de eliminar 
2. Tienda del servidor -> Items: Presente al editar, eliminar y visualizar 
3. Miscelanea -> Constructor de mensajes: Presente al eliminar y editar, pero solamente puedes ver y no guardar cambios (Al guardarlo, se creará un mensaje duplicado en tu guild con el mismo contenido del mensaje al que se hizo referencia)
4. Miscelanea -> Tags: Presente al editar, eliminar y visualizar
5. Entretenimiento -> Roleplay con IA: Presente al visualizar y eliminar 

Nuevamente, del resto no logré hayar otra cosa.

Reportando el problema en la respectiva página de Nekotina, tardaron días en responderme pero me contactaron por el propio bot para notificarme que solucionaron el problema.

![Fixed](/assets/posts/bots_bounty2/neko_fixed.png)

**No hubo recompensa**

> Aún me quedan algunas anécdotas de vulnerabilidades por contar, pero todavía no me han confirmado que solucionaron el problema asi que mientras tanto, no las publicaré. Actualizaré el post en cuanto solucionen los bugs.
{: .prompt-info }

## Resumen

El total de dinero recolectado en esto fue de 152$, en un lapso de 4 días contando el tiempo que estuve esperando para que me respondan el reporte y me confirmen que solucionaron las vulnerabilidades.

La verdad, me entretuvo bastante recorrer por estos bots. También recorrí por otros como Circle y Carl bot pero sin encontrar nada interesante en estos. Próximamente estaré haciendo más posts similares a este pero con distintos enfoques (dedicado a cosas de Minecraft, páginas web de uso general y demás).

