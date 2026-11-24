# Preparar una cuenta AWS personal para la PoC

Guía para dejar la cuenta lista y que el asistente pueda ejecutar la PoC (plan 0002) **sin usar llaves de acceso** y con límites de gasto.
No escribas en el repositorio ni pegues en el chat contraseñas, códigos de verificación, llaves ni el identificador de tu cuenta.

Tiempo estimado: 30–45 min (más la espera de un posible aumento de cuota).

## Parte 1 · Comprobar la cuenta y los créditos (consola, usuario raíz)
1. Inicia sesión en https://console.aws.amazon.com con el correo de la cuenta (usuario raíz).
2. Arriba a la derecha, abre el menú de tu cuenta → **Billing and Cost Management**.
3. **Credits** (menú izquierdo): confirma el **monto**, el **saldo restante** y la **fecha de vencimiento**. Anótalos (no los pegues con datos de cuenta).
4. En el mismo lugar, abre las condiciones del crédito y revisa si **excluye servicios** (normalmente cubre EC2, EKS, SQS, Lambda; confirma que no excluye alguno de ellos).
5. **Account** (o *Account settings*): mira el **tipo de plan**. Si dice plan gratuito (*Free plan*) y la consola te impide usar EKS u otros servicios, usa **Upgrade plan** para pasar al plan de pago.
   Los créditos normalmente se conservan al mejorar el plan; verifica en la pantalla de créditos que el saldo sigue ahí después.

## Parte 2 · Proteger el usuario raíz
1. Menú de tu cuenta → **Security credentials**.
2. **Multi-factor authentication (MFA)** → *Assign MFA device* → app autenticadora (Google Authenticator, Authy, 1Password…) o llave de seguridad. Termina el emparejamiento.
3. En la misma página, **no crees Access keys** para el usuario raíz. Si ya existe alguna, bórrala.
4. A partir de aquí, **no vuelvas a usar el usuario raíz** salvo para facturación.

## Parte 3 · Límites de gasto (hazlo antes de crear nada)
1. **Billing and Cost Management → Budgets → Create budget**.
2. Plantilla **Monthly cost budget**, monto **20 USD**, tu correo personal para las alertas.
3. Agrega alertas al **50 %** y al **80 %** del presupuesto real (*Actual*). Guarda.
4. **Cost Explorer** → **Launch Cost Explorer** (actívalo; tarda hasta 24 h en mostrar datos).
5. Opcional pero recomendable: **Billing preferences** → activa *Receive Billing Alerts* y las alertas de uso del plan gratuito.

## Parte 4 · Crear tu acceso con IAM Identity Center (sin llaves)
1. En la consola, escribe **IAM Identity Center** en el buscador y cambia la región a **N. Virginia (us-east-1)**.
2. Pulsa **Enable**. Si pregunta por AWS Organizations, acepta crear la organización (es gratis y solo la cuenta tuya).
3. **Users → Add user**: nombre de usuario, tu correo, nombre y apellido. Envía la invitación y **define la contraseña** desde el correo que recibirás. Activa **MFA** para este usuario cuando te lo pida.
4. **Permission sets → Create permission set → Predefined → AdministratorAccess**. Duración de sesión: 8 horas.
   Es una cuenta personal solo para la PoC: EKS crea roles, redes y balanceadores, así que los permisos finos costarían mucho tiempo. El límite real de gasto lo ponen el presupuesto y la destrucción final.
5. **AWS accounts** → marca tu cuenta → **Assign users or groups** → elige tu usuario → elige el permission set `AdministratorAccess` → **Submit**.
6. En **Dashboard** copia la **AWS access portal URL** (algo como `https://d-xxxxxxxxxx.awsapps.com/start`). La necesitarás en la Parte 5. No es un secreto, pero no la pegues en archivos del repositorio.

## Parte 5 · Conectar la línea de comandos
En la terminal de Claude Code (o en la tuya), escribe con el prefijo `!` si es en la sesión del asistente:
```bash
aws --version                              # AWS CLI v2 (cualquiera >= 2.9 sirve; si es muy antigua, actualiza con: brew upgrade awscli)
aws configure sso --profile poc-asr1
```
Respuestas a las preguntas:

| Pregunta | Qué responder |
|---|---|
| SSO session name | `poc-asr1` |
| SSO start URL | la *AWS access portal URL* de la Parte 4, paso 6 |
| SSO region | `us-east-1` |
| SSO registration scopes | Enter (valor por defecto) |
| Se abre el navegador | inicia sesión con tu **usuario de Identity Center** (no el raíz) y pulsa **Allow** |
| Cuenta y rol | elige tu cuenta y `AdministratorAccess` |
| Default client region | `us-east-1` |
| Default output format | `json` |

Comprueba:
```bash
aws sts get-caller-identity --profile poc-asr1
```
Debe responder con tu usuario y tu cuenta **personal**. Si ves una cuenta de trabajo, detente y avísame: el perfil está mal.

Cuando la sesión caduque (cada ~8 h) basta con:
```bash
aws sso login --profile poc-asr1
```

## Parte 6 · Cuotas (para que no falle al crear nodos)
Las cuentas nuevas pueden tener pocas vCPU permitidas. La PoC necesita unas **20** (4 nodos del MS + nodos extra de la ráfaga + generador de carga).

Revisar (solo lectura):
```bash
aws service-quotas get-service-quota --profile poc-asr1 --region us-east-1 \
  --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value'
```
Si el valor es menor que 32, solicita aumento: consola → **Service Quotas → AWS services → Amazon EC2 → Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances → Request increase at account level → 32**.
La aprobación puede tardar de minutos a un día: hazlo cuanto antes.

## Parte 7 · Avisar al asistente
Cuando termines, escribe en el chat: «**perfil listo**» (no pegues salidas con identificadores). El asistente entonces:
1. Verifica en modo lectura: identidad, cuota de vCPU, presupuesto.
2. Empieza la fase A1 del plan 0002: escribir y planificar el Terraform **sin aplicar**.
3. Pide tu confirmación explícita antes de cada `apply` y antes del `destroy` final.

## Parte 8 · Reglas para no gastar de más
- Al terminar cada sesión de pruebas se ejecuta `terraform destroy` y se verifica que no queden nodos, balanceadores, volúmenes ni IP elásticas.
- Mira **Cost Explorer** al día siguiente de cada corrida.
- Nunca uses este perfil para nada que no sea la PoC y nunca mezcles perfiles de trabajo.
- Si recibes una alerta de presupuesto, avísame y paramos y destruimos.
