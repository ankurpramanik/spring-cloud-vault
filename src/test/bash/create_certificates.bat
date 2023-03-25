@echo off
setlocal

set "DIR=%~dp0"
set "CA_DIR=work/ca"
set "KEYSTORE_FILE=work/keystore.jks"
set "CLIENT_CERT_KEYSTORE=work/client-cert.jks"
set "OPENSSL_CONF=D:\OpenSSLConfigPath\openssl.cnf"

if exist "%CA_DIR%" (
    rmdir /S /Q "%CA_DIR%"
)

if exist "%KEYSTORE_FILE%" (
    del /F /Q "%KEYSTORE_FILE%"
)

if exist "%CLIENT_CERT_KEYSTORE%" (
    del /F /Q "%CLIENT_CERT_KEYSTORE%"
)

if exist "%OPENSSL_CONF%" (
    echo [INFO] Config path "%OPENSSL_CONF%" 
) else (
	echo [ERROR] "%OPENSSL_CONF%" file not found
	exit /B 1
)

where openssl >nul 2>nul || (
    echo [ERROR] No openssl in PATH
    exit /B 1
)

set "KEYTOOL=keytool"
where keytool >nul 2>nul || (
    if defined JAVA_HOME (
        set "KEYTOOL=%JAVA_HOME%\bin\keytool"
    ) else (
        echo [ERROR] No keytool in PATH/JAVA_HOME
        exit /B 1
    )
)

mkdir "%CA_DIR%\private" "%CA_DIR%\certs" "%CA_DIR%\crl" "%CA_DIR%\csr" "%CA_DIR%\newcerts" "%CA_DIR%\intermediate"

echo [INFO] Generating CA private key
rem Less bits = less secure = faster to generate
openssl genrsa -passout pass:changeit -aes256 -out "%CA_DIR%\private\ca.key.pem" 2048

attrib +R "%CA_DIR%\private\ca.key.pem"

echo [INFO] Generating CA certificate
openssl req -config "%DIR%\openssl.cnf" ^
      -key "%CA_DIR%\private\ca.key.pem" ^
      -new -x509 -days 7300 -sha256 -extensions v3_ca ^
      -out "%CA_DIR%\certs\ca.cert.pem" ^
      -passin pass:changeit ^
      -subj "/C=NN/ST=Unknown/L=Unknown/O=spring-cloud-vault-config/CN=CA Certificate"

echo [INFO] Prepare CA database
echo 1000 > "%CA_DIR%\serial"
type nul > "%CA_DIR%\index.txt"

echo [INFO] Generating server private key
openssl genrsa -aes256 ^
      -passout pass:changeit ^
      -out "%CA_DIR%\private\localhost.key.pem" 2048

::openssl rsa -in "%CA_DIR%\private\localhost.key.pem" ^
::      -out "%CA_DIR%\private\localhost.decrypted.key.pem" ^
::      -passin pass:changeit


echo [INFO] Generating public and private key
openssl req -nodes -x509 -days 365 -keyout "%CA_DIR%\private\localhost.decrypted.key.pem" -out "%CA_DIR%\certs\localhost.cert.pem" ^
	-subj "/C=IN/ST=WB/L=KOLKATA/O=Student/OU=IT Department/CN=a@a.com"
echo [INFO] SuccessfullygGenerated public and private key

attrib +R "%CA_DIR%\private\localhost.key.pem"
attrib +R "%CA_DIR%\private\localhost.decrypted.key.pem"

echo [INFO] Generating server certificate request
openssl req -config "%DIR%\openssl.cnf" ^
         "\n[SAN]\nsubjectAltName=DNS:localhost,IP:127.0.0.1" ^
      -reqexts SAN ^
      -key "%CA_DIR%\private\localhost.key.pem" ^
      -passin pass:changeit ^
      -new -sha256 -out "%CA_DIR%\csr\localhost.csr.pem" ^
      -subj "/C=NN/ST=Unknown/L=Unknown/O=spring-cloud-vault-config/CN=localhost"

echo [INFO] Signing certificate request
openssl ca -config "%DIR%\openssl.cnf" ^
      -extensions server_cert -days 375 -notext -md sha256 ^
      -passin pass:changeit ^
      -batch ^
      -in "%CA_DIR%\csr\localhost.csr.pem" ^
      -out "%CA_DIR%\cert"
	  

echo [INFO] Generating client auth private key
openssl genrsa -aes256 ^
      -passout pass:changeit ^
      -out "%CA_DIR%"\private\client.key.pem 2048

openssl rsa -in "%CA_DIR%"\private\client.key.pem ^
      -out "%CA_DIR%"\private\client.decrypted.key.pem ^
      -passin pass:changeit

attrib +r "%CA_DIR%"\private\client.key.pem

echo [INFO] Generating client certificate request
openssl req -config %DIR%\openssl.cnf ^
      -key "%CA_DIR%"\private\client.key.pem ^
      -passin pass:changeit ^
      -new -sha256 -out "%CA_DIR%"\csr\client.csr.pem ^
      -subj "/C=NN/ST=Unknown/L=Unknown/O=spring-cloud-vault-config/CN=client"

echo [INFO] Signing certificate request
openssl ca -config %DIR%\openssl.cnf ^
      -extensions usr_cert -days 375 -notext -md sha256 ^
      -passin pass:changeit ^
      -batch ^
      -in "%CA_DIR%"\csr\client.csr.pem ^
      -out "%CA_DIR%"\certs\client.cert.pem

echo [INFO] Creating PKCS12 file with client certificate
openssl pkcs12 -export -clcerts ^
      -in "%CA_DIR%"\certs\client.cert.pem ^
      -inkey "%CA_DIR%"\private\client.decrypted.key.pem ^
      -passout pass:changeit ^
      -out "%CA_DIR%"\client.p12

"%KEYTOOL%" -importcert -keystore %KEYSTORE_FILE% -file "%CA_DIR%"\certs\ca.cert.pem -noprompt -storepass changeit
"%KEYTOOL%" -importkeystore ^
                              -srckeystore "%CA_DIR%"\client.p12 -srcstoretype PKCS12 -srcstorepass changeit ^
                              -destkeystore "%CLIENT_CERT_KEYSTORE%" -deststoretype JKS ^
                              -noprompt -storepass changeit


echo [INFO] Certificate generation completed successfully.

