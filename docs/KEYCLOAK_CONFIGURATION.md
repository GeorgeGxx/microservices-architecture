# 🔑 Keycloak Configuration Guide

Este documento explica cómo configurar **Keycloak** para integrarlo con el proyecto **Microservices with Spring Boot**.

---

## 1️⃣ Iniciar Keycloak
Levanta el contenedor de Keycloak con Docker Compose:
```bash
docker-compose up -d keycloak
```

Accede a la consola de administración:  
👉 [http://localhost:8181](http://localhost:8181)

Usuario/contraseña por defecto:
```
admin / admin
```

---

## 2️⃣ Crear un Realm
1. En el menú lateral izquierdo, selecciona **Add Realm**.  
2. Nombre: `microservices-realm`  
3. Guardar.

---

## 3️⃣ Crear un Client
1. Dentro del **Realm `microservices-realm`**, ir a **Clients → Create Client**. 
2. Client ID: `microservices_client` 
3. Name: `Microservices Client` 
4. Tipo de cliente: **OpenID Connect**.  
5. Configuración:  
   - **Client Authentication**: ✅ ON  
   - **Authorization**: ✅ ON  
   - **Standard Flow**: ✅ ON
   - **Direct Access Grants**: ✅ ON
   - **OAuth 2.0 Device Authorization Grant**: ✅ ON
   - **Valid Redirect URIs**:  
     ```
     http://localhost:8080/*
     http://localhost:8080/login/oauth2/code/keycloak
     https://oauth.pstmn.io/v1/browser-callback
     ```
   - **Web Origins**: /*

![keycloak_client_configuration](https://github.com/user-attachments/assets/52cc6dd5-fe94-4bb7-be21-b15de6206d11)

6. Guarda y copia el **Client Secret** generado. Este debe coincidir con la propiedad en el API Gateway:
   
![keycloak_client_secret](https://github.com/user-attachments/assets/3dc545c3-b028-4340-b241-4fe6147c40bb)

```properties
spring.security.oauth2.client.registration.keycloak.client-secret=TU_CLIENT_SECRET
```

---

## 4️⃣ Crear Usuarios
1. Ve a **Users → Add User**.  
   - Username: `admin_user`  
   - Email, nombre, etc. opcionales.  
   - Habilitado: ✅ ON.  
2. En la pestaña **Credentials**, asigna una contraseña y marca **Temporary = OFF**.
3. Hacer el mismo paso para la creación del user `basic_user`.

---

![keycloak_users_configuratio](https://github.com/user-attachments/assets/7baf4751-8e08-4586-8956-efe31823b54d)

## 5️⃣ Crear Roles
1. En el menú de **Roles**, crear roles como `USER`, `ADMIN`.

![keycloak_realm_roles_configuration](https://github.com/user-attachments/assets/72aa97a1-ede8-4cc6-9d4e-c1e0863fc177)
   
2. Asignar los roles a los usuarios creados:
   - `admin_user` → roles: **ADMIN** y **USER**  
   - `basic_user` → roles: **USER**

![keycloak_admin_user_configuration](https://github.com/user-attachments/assets/47b6d3d9-a579-4f34-b439-8521b676b7d7)
![keycloak_basic_user_configuration](https://github.com/user-attachments/assets/8580e13b-a49e-4122-8047-2ef724bbc201)

---

## 6️⃣ Probar el flujo OAuth2 en el Navegador
1. Accede al API Gateway:
   ```
   http://localhost:8080/api/product
   ```
   El Gateway redirigirá automáticamente a Keycloak para autenticación.
2. Ingresa con el usuario `admin_user` (Acceso a todos los endpoints) o `basic_user`.  
3. Keycloak emitirá un **JWT token** y lo reenviará al API Gateway, que a su vez lo propagará a los microservicios gracias a:

```properties
spring.cloud.gateway.server.webflux.default-filters[1]=TokenRelay
```

---

## 7️⃣ Autenticación con Keycloak en Postman y Postman Interceptor

Para consumir los microservicios desde **Postman** mediante **OAuth 2.0 (Authorization Code)** y sincronizar cookies de sesión con el navegador:

### a. Configuración OAuth 2.0 en Postman
1. En Postman, ve a la pestaña **Authorization** de tu request o colección.
2. Configura los siguientes parámetros:
   - **Auth Type**: `OAuth 2.0`
   - **Token Name**: `kc_token`
   - **Grant Type**: `Authorization Code`
   - **Callback URL**: `http://localhost:8080/login/oauth2/code/keycloak`
   - **Auth URL**: `http://localhost:8181/realms/microservices-realm/protocol/openid-connect/auth`
   - **Access Token URL**: `http://localhost:8181/realms/microservices-realm/protocol/openid-connect/token`
   - **Client ID**: `microservices_client`
   - **Client Secret**: `TU_CLIENT_SECRET`
   - **Scope**: `openid`

![postman_auth_config](https://github.com/user-attachments/assets/de4721d5-0fca-46ff-94fa-42c2d5c7a482)

3. Haz clic en **Get New Access Token** → Postman abrirá la ventana de login de Keycloak.
   ![get_new_Access_token](https://github.com/user-attachments/assets/0ace6e04-7257-4224-854f-adf47549308d)

4. Ingresa con el usuario creado (`admin_user` o `basic_user`).
5. Se generará el **token JWT** y se guardará en Postman para autenticar tus requests.
   ![use_token](https://github.com/user-attachments/assets/cfbc8a00-6c8c-4180-80b6-569a7c28640a)

---

### b. Sincronización de Cookies con Postman Interceptor

Para evitar problemas de sesiones cruzadas o expiración de tokens al solicitar el `Authorization Code`:

1. **Instalar Postman Interceptor**:
   - Instala la extensión **Postman Interceptor** desde la Chrome Web Store.
   - En Postman (app de escritorio), activa el icono de satélite/interceptor en la barra superior o en la pestaña **Cookies** y habilita **Sync cookies**.

   ![sync_cookies](https://github.com/user-attachments/assets/595b549e-3fd1-48d2-a767-2f4fc495ddff)

2. **Probar primero en el navegador**:
   - Antes de solicitar el token en Postman, abre [http://localhost:8080/api/product](http://localhost:8080/api/product) en Google Chrome y realiza el login en Keycloak.
   - Postman Interceptor capturará automáticamente las cookies de sesión (`AUTH_SESSION_ID`, `KEYCLOAK_IDENTITY`), garantizando una autenticación fluida sin rechazos de redirect.

   ![Test_api_chrome](https://github.com/user-attachments/assets/b57ce8c0-fd00-44f9-9264-862fede84658)
   ![response_Test_api](https://github.com/user-attachments/assets/d63f26cc-a9cb-49fe-90c6-36c92d642094)

---

✅ Con esto ya tendrás:  
- **Keycloak → emite tokens JWT**  
- **API Gateway → verifica tokens y los pasa a microservicios**  
- **Microservicios → protegidos con Spring Security + OAuth2 Resource Server**  
- **Postman + Interceptor → sincronizado para pruebas directas**
