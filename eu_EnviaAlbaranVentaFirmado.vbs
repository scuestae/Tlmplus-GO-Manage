'--------------------------------------------------------------------------
' Eurotronic 2018 - eu_EnviaDocAdjunto.vbs - ver. 0.3
' -------------------------------------------------------------------------
'
' Envía por email el albarán firmado al cliente
' El documento que se adjunta es VAR\FIR de la gestión documental
' El email lo coge de la dirección de envío de albaranes de la ficha
' del cliente.
' Si no tiene dirección de envío de albarán NO se envía.
' El mensaje lo toma de mensaje adjunto 14 de la empresa-delegación
'
' La script hay que lanzarla desde 32 bits para que use el ODBC de 32
'
' %windir%\syswow64\cscript.exe eu_Envia eu_EnviaDocAdjunto.vbs /dias:1
'
' Se debe ejecutar una vez al día, por ej. al comenzar la jornada
' envía los albaranes firmados desde la fecha de hoy menos los días
' espercificados en el parámetro /dias:
'
'
Option Explicit
CONST SI = TRUE
CONST NO = FALSE
Const adOpenStatic   = 3
Const adLockReadOnly = 1

Dim tlmplus, tlmplus1, tlmplus2, rs, cSql, I
Dim fs, nt, FicheroLog, cAsunto
'------------------------------------------------------------
Const COD_ENT = 1
Const cMensajeAdjunto    = 14
      cAsunto            = "Adjuntamos albarán de entrega {0}" 
Const cDeEmail           = "MIEMPRESA: Dpto. de ventas <remite@miempresa.com>"
Const cServidor          = "smtp.miempresa.com"
Const lHtml              = True
Const cPuerto            = 587
Const cUsuario           = "remite@miempresa.com"
Const cPassword          = "contraseña_smtp"
Const lAutentificacion   = True
Const lSSL               = False
'--------------------------------------------------------------

FicheroLog         = ".\" & LEFT(WScript.ScriptName, INSTRREV(WScript.ScriptName,".")-1) & ".log" 

If WScript.Arguments.Count = 0 Then
	 WScript.echo "(c) Eurotronic Consultores S.L."
    wscript.echo "Sintaxis: %windir%\syswow64\cscript " & WScript.ScriptName & " /dias:<DesdeDiasPrevios>"
    WScript.echo "<DesdeDiasPrevios> Número de días previos a la fecha del día para seleccionar los albaranes"
    WScript.Quit 1
End if

Main()

'-------------------------------
' Inicio aplicación
'-------------------------------
Function Main()
    Dim dFechaIni, cRutaGesDoc,  cFichero, lReturn, cParaEmail, cMensaje, nReturn
    Dim cLineaLog, cAsuntoCorreo

    dFechaIni = DateAdd( "d", - Argumento("dias"), date() ) ' fecha inicio = FechaDeHoy - diasPrevios
    
    wscript.echo dFechaIni

    cRutaGesDoc = ""
    
    lReturn = False
    nReturn = 0
    
    SET fs = Wscript.CreateObject("Scripting.FileSystemObject")
    SET nt = WScript.CreateObject("WScript.Network")

    If Not ConexionBD(False) Then
        WScript.quit 1
    End If
    
    Set rs= CreateObject("ADODB.recordset") 
    
    ' --- albaranes a tratar
    cSql = "SELECT avc.cod_ent, avc.cod_del, avc.tip_alb, avc.num_alb, avc.fec_alb, avc.cli_amb, avc.cod_cli, agd.cod_doc, agd.tip_doc, agd.img_agd"
    cSql = cSql & " FROM PUB.gvalcab avc"
    cSql = cSql & " INNER JOIN PUB.gvalcabGD agd ON avc.cod_ent=agd.cod_ent AND avc.cod_del=agd.cod_del AND avc.tip_alb=agd.tip_alb AND avc.num_alb=agd.num_alb"
    cSql = cSql & " WHERE avc.cod_ent=" & COD_ENT
    cSql = cSql & " AND agd.cod_doc IN ('VAR') AND agd.tip_doc IN ('FIR') "
    cSql = cSql & " AND avc.ema_alb = 0" ' No enviado por email
    cSql = cSql & " AND avc.fec_alb >= '" &  FormatFecha(dFechaIni) & "'"

   'WScript.Echo csql

    rs.Open csql, tlmplus1, adOpenStatic, adLockReadOnly
    
    IF ERR.Number <> 0 Then
        WScript.Echo F2( "Error en recordset {0} - {1}" , "tlmplus1", Err.Description)
    End If
    
    '  Recorrer record set
    While Not rs.Eof

        cRutaGesDoc = RutaGesDoc( rs.Fields.Item("cod_doc"), rs.Fields.Item("tip_doc") )
        cParaEmail = DireccionEmail( rs.Fields.Item("cod_ent"), rs.Fields.Item("cod_del"), rs.Fields.Item("cod_cli") )
        cFichero = cRutaGesDoc & "\" & rs.Fields.Item("img_agd")

        cAsuntoCorreo = F1(cAsunto, rs.Fields.Item("tip_alb") & "-" & rs.Fields.Item("num_alb"))
       
        cMensaje = TextoMensaje( rs.Fields.Item("cod_ent"), rs.Fields.Item("cod_del"), cMensajeAdjunto )

        If cMensaje ="" Then
            cMensaje ="Adjuntamos el albarán firmado por su empleado"
        End If

        cMensaje = Replace("<meta http-equiv='Content-Type' content='text/html; charset=utf-8'><pre style='white-space:pre-wrap'>", "'", CHR(34)) & cMensaje & "</pre>"
        
        ' comprobar si existe el fichero y hay email para enviarlo
        if cParaEmail <> "" And fs.FileExists( cFichero ) THEN
                
            lReturn = EnviarEmail(cServidor, _
                cParaEmail, _
                cDeEmail, _
                cAsuntoCorreo, _
                cMensaje, _
                lHtml, _
                cFichero, _
                cPuerto, _
                cUsuario, _
                cPassword, _
                lAutentificacion, _
                lSSL)
            
            'Wscript.echo lReturn

            if lReturn Then ' enviado
                nReturn =  MarcarEnviado( rs.Fields.Item("cod_ent"), rs.Fields.Item("cod_del"), rs.Fields.Item("tip_alb"), rs.Fields.Item("num_alb") )
                cLineaLog = "Enviado a " & cParaEmail
                if nReturn =0 Then cLineaLog = cLineaLog & " pero NO marcado"
            else
                cLineaLog = "No enviado a "  & cParaEmail
            end if
            
            ' escribir en el log
            cLineaLog = cLineaLog &  " el documento " & rs.Fields.Item("cod_ent") & " " & rs.Fields.Item("cod_del") & " " & _
                                                        rs.Fields.Item("tip_alb") & "-" & rs.Fields.Item("num_alb")
            cLineaLog = cLineaLog & " fichero adjunto " & cFichero
            WriteLog cLineaLog
            
        end if

        rs.MoveNext

    Wend
    
    Set rs = Nothing
    CerrarBD

End Function

'-------------------------------
'  Argumento por nombre o posición
'-------------------------------
Function Argumento( cNombre )

    cNombre = UCASE(cNombre)

    ' si existe el argumento nombrado devolver su valor
    If WScript.Arguments.Named.Exists(cNombre) Then
        Argumento = WScript.Arguments.Named.Item(cNombre) 
    ' si no se ha nombrado devolver valor por defecto
    ElseIf cNombre = "DIAS" Then   
        Argumento = 0
    End If

End Function

'-------------------------------
'  Recorrer record set
'-------------------------------
Function MostrarRs ( rs )
    Dim I

    While Not rs.Eof

        for I=0 to rs.fields.count - 1
            if i<>0 THEN  WScript.StdOut.Write ";"
            WScript.StdOut.Write rs.fields(I)     
        next
        WScript.StdOut.Write vbCrLf
        rs.MoveNext

    Wend
End Function
'-------------------------------
'  Ruta gestión documental
'-------------------------------
Function RutaGesDoc( cCod_Doc, cTip_Doc ) 
    Dim cSql, rs2
    
    RutaGesDoc =""
    set rs2= CreateObject("ADODB.recordset") 

    cSql = "SELECT cgd_tdoc"
    cSql = cSql & " FROM PUB.gmtipdocGD"
    cSql = cSql & " WHERE cod_enT = " & COD_ENT
    cSql = cSql & " AND cod_del = 0 "  ' < ! GESDOC POR EMPRESA
    cSql = cSql & " AND cod_doc = '" & cCod_Doc & "'"
    cSql = cSql & " AND tip_doc = '"  & cTip_Doc & "'"

    rs2.Open csql, tlmplus, adOpenStatic, adLockReadOnly

    IF NOT rs2.EOF THEN
        RutaGesDoc = rs2.Fields.Item("cgd_tdoc")
    END IF

    Set rs2 = Nothing

End Function
'-------------------------------
'  email del cliente
'-------------------------------
Function DireccionEmail(  nCod_Ent, nCod_Del, nCod_Cli) 
    Dim cSql, rs2
    ' num_cen

    DireccionEmail =""
    set rs2= CreateObject("ADODB.recordset") 

    cSql = "SELECT cle.nom_cen, cle.ema_cen"
    cSql = cSql & " FROM PUB.gmclidel cld"
    cSql = cSql & " INNER JOIN PUB.gmdirenv cle ON cld.cli_amb=cle.cli_amb AND cld.cod_cli=cle.cod_cli AND cld.num_cen=cle.cod_cen"
    cSql = cSql & " WHERE cld.cod_ent = " & nCod_Ent
    cSql = cSql & " AND cld.cod_del = "  & nCod_Del
    cSql = cSql & " AND cld.cod_cli = " & nCod_Cli 

    rs2.Open csql, tlmplus, adOpenStatic, adLockReadOnly

    IF NOT rs2.EOF THEN
        DireccionEmail = rs2.Fields.Item("ema_cen")
        if INSTR( DireccionEmail, "@") = 0 THEN
            DireccionEmail = ""
        End if
    END IF

    Set rs2 = Nothing

End Function

'-------------------------------
'  Marcar albarán como enviado
'-------------------------------
Function MarcarEnviado(  nCod_Ent, nCod_Del, cTip_Alb, nNum_Alb)
    Dim csql
    MarcarEnviado = 0

    csql = "UPDATE PUB.gvalcab SET"
    csql = csql & " ema_alb = 1" 
    csql = csql & " WHERE cod_ent = " & nCod_Ent
    csql = csql & " AND cod_del =" & nCod_Del
    csql = csql & " AND tip_alb = '" & cTip_Alb & "'"
    csql = csql & " AND num_alb = " & nNum_Alb

    'Wscript.Echo csql

    tlmplus1.Execute csql, MarcarEnviado

    'Wscript.Echo MarcarEnviado
    
End Function

'-------------------------------
'  Texto del cuerpo del mensaje
'-------------------------------
Function TextoMensaje(  nCod_Ent, nCod_Del, nCod_Dem)
    Dim csql, rs2
    
    TextoMensaje = ""
    
    Set rs2= CreateObject("ADODB.recordset") 
    
    csql = "SELECT mem.cod_ent, mem.cod_del, mem.cod_dem, eme.men_eme"
    csql = csql & " FROM PUB.gemaadj mem"
    csql = csql & " INNER JOIN PUB.gemensa eme ON mem.cod_eme=eme.cod_eme"
    csql = csql & " WHERE mem.cod_ent = " & nCod_Ent
    csql = csql & " AND mem.cod_del =" & nCod_Del
    csql = csql & " AND mem.cod_dem = " & nCod_Dem' <-! 14 envío albaran de venta
    
    rs2.Open csql, tlmplus, adOpenStatic, adLockReadOnly

    IF NOT rs2.EOF THEN
        TextoMensaje = rs2.Fields.Item("men_eme")
    END IF

    Set rs2 = Nothing
    
End Function

'-------------------------------
'  conectar las bdatos
'-------------------------------
Function ConexionBD( lSoloLectura)
    Dim cServidorBD, cUsuario, cPassword
    Dim cConexion, cDIL
    
    ConexionBD = False

    Set tlmplus = CreateObject("ADODB.Connection")
    Set tlmplus1 = CreateObject("ADODB.Connection")
    Set tlmplus2 = CreateObject("ADODB.Connection")
    
    cUsuario = "sysprogress"
    cPassword = "249131"
    cServidorBD = nt.ComputerName
    
    IF lSoloLectura Then 
        cDIL = "READ UNCOMMITTED"
    else
        cDIL = "READ COMMITTED"
    End If

    cConexion = "DRIVER={Progress OpenEdge 10.1B driver}" & _
                ";HOST=" & cServidorBD & _
                ";UID=" & cUsuario & _
                ";PWD=" & cPassword & _
                ";DIL=" & cDIL & _
                ";AS=" & 50
                
    On Error Resume Next

    With tlmplus
        .ConnectionString = cConexion & ";DB=" & "tlmplus" & ";PORT=" & "2511"
        .Open
    End With
    
    If Err.Number <> 0 Then
        WScript.Echo F2( "Error conectando BD {0} - {1}" , "tlmplus", Err.Description)
        Err.Clear
        exit function
    End If

    With tlmplus1
        .ConnectionString = cConexion & ";DB=" & "tlmplus1" & ";PORT=" & "2513"
        .Open
    End With

    With tlmplus2
        .ConnectionString = cConexion & ";DB=" & "tlmplus2" & ";PORT=" & "2514"
        .Open
    End With

    ON Error GoTo 0
    ConexionBD = TRUE

End Function
'
' --- CerrarDB
'
Public Function CerrarBD()
    
    On Error Resume Next
    
    tlmplus.Close
    tlmplus1.Close
    tlmplus2.Close
    
    Set tlmplus = Nothing
    Set tlmplus1 = Nothing
    Set tlmplus2 = Nothing
    
    On Error GoTo 0

End Function
'--------------------------------------------------------------------------
' The string formatting functions to avoid string concatenation.
'--------------------------------------------------------------------------
FUNCTION F3(myString, arg0, arg1, arg2) 
	F3 = F2(myString, arg0, arg1)
    F3 = REPLACE(F3, "{2}", arg2)
END FUNCTION

FUNCTION F2(myString, arg0, arg1)
    F2 = F1(myString, arg0)
    F2 = REPLACE(F2, "{1}", arg1)
END FUNCTION

FUNCTION F1(myString, arg0)
    F1 = REPLACE(myString, "{0}", arg0)
END FUNCTION

'--------------------------------------------------------------------------
' Create the console log files.
'--------------------------------------------------------------------------
FUNCTION WriteLog(line)
    DIM fileStream
    
    SET fileStream = fs.OpenTextFile(FicheroLog, 8, True, -1) 
    '     8=ForAppending, True=Crear si no existe, -1 = Unicode,
    line = DATE & " " & TIME & " : " & line
    WScript.Echo line
    fileStream.WriteLine line
    fileStream.Close

    SET fileStream = Nothing
END FUNCTION
'--------------------------------------------------------------------------
' Crear log
'--------------------------------------------------------------------------
SUB CrearLog()
 	DIM fileStream
    'Creamos el fichero de Log
	Set fileStream = fs.CreateTextFile(FicheroLog, True, True)
	fileStream.Close
	Set fileStream = Nothing
END SUB

''
'
'
Function FormatFecha(dFecha)    
    FormatFecha = Year(dFecha) & "/" & Right("0" & Month(dFecha),2)  & "/" & Right("0" & Day(dFecha),2) 
End Function

'--------------------------------------------------------------------------
'  Enviar correo electronico
'--------------------------------------------------------------------------
FUNCTION EnviarEmail(Servidor_SMTP , _
			Para , _
			De , _
			Asunto , _
			Mensaje , _
			Html , _
			Path_Adjunto , _
			Puerto , _
			Usuario , _
			Password , _
			Usar_Autentificacion, _
			Usar_SSL) 
    ' Variable de objeto Cdo.Message
    DIM Obj_Email 
    
    EnviarEmail = False

    ' Crea un Nuevo objeto CDO.Message
    SET Obj_Email = CreateObject ("cdo.Message")
    
    Obj_Email.BodyPart.Charset = "utf-8" 

    ' Indica el servidor Smtp para poder enviar el Mail ( puede ser el nombre del servidor o su direcci?n IP )
    Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/smtpserver") = Servidor_SMTP
    
    Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/sendusing") = 2
    
    ' Puerto. Por defecto se usa el puerto 25, en el caso de Gmail se usan los puertos 465 o  el puerto 587 ( este ?ltimo me dio error )
    
    Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/smtpserverport") = CLNG(Puerto)
    
    ' Indica el tipo de autentificaci?n con el servidor de correo El valor 0 no requiere autentificarse, el valor 1 es con autentificaci?n
    Obj_Email.Configuration.Fields.Item("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate") = ABS(Usar_Autentificacion)
    
        ' Tiempo m?ximo de espera en segundos para la conexi?n
    Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/smtpconnectiontimeout") = 30

    ' Configura las opciones para el login en el SMTP
    IF Usar_Autentificacion THEN

        ' Id de usuario del servidor Smtp ( en el caso de gmail, debe ser la direcci?n de correro mas el @gmail.com )
        Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/sendusername") = Usuario

        ' Password de la cuenta
        Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/sendpassword") = Password

        ' Indica si se usa SSL para el env?o. En el caso de Gmail requiere que est? en True
        Obj_Email.Configuration.Fields.Item ("http://schemas.microsoft.com/cdo/configuration/smtpusessl") = Usar_SSL
    
    END IF
    
    ' DirecciOn del Destinatario
    Obj_Email.To = Para
    
    ' Copia oculta a
    Obj_Email.Bcc = "" 

    ' DirecciOn del remitente
    Obj_Email.From = De
    
    ' Asunto del mensaje
    Obj_Email.Subject = Asunto
    
    ' Cuerpo del mensaje
    If Html Then 
        Obj_Email.HTMLBody = Mensaje
        Obj_Email.HTMLBodyPart.Charset = "utf-8"
    Else
        Obj_Email.TextBody = Mensaje
    End If

    'Ruta del archivo adjunto   
    IF Path_Adjunto <> vbNullString THEN
        Obj_Email.AddAttachment (Path_Adjunto)
    END IF
 
    ' Actualiza los datos antes de enviar
    Obj_Email.Configuration.Fields.Update
      
    ' EnvIa el email
    Obj_Email.Send

    IF ERR.Number = 0 THEN
       EnviarEmail = TRUE
    '   WriteLog F2("Notificado por correo a {0} mediante el servidor {1}", Para, Servidor_SMTP)
    'ELSE
    '   CALL NERROR("Error en la notificaci?n por correo a {0}", Para)
    '   Enviar_Mail_CDO = FALSE	
    END IF
    
    ' Descarga la referencia
    IF Not Obj_Email Is Nothing THEN
        SET Obj_Email = Nothing
    END IF

END FUNCTION
