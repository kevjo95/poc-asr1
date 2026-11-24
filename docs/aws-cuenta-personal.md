# Preparar una cuenta AWS personal para la PoC

Guía para dejar la cuenta lista y que el asistente pueda ejecutar la PoC (plan 0002) **sin usar llaves de acceso** y con límites de gasto.
No escribas en el repositorio ni pegues en el chat contraseñas, códigos de verificación, llaves ni el identificador de tu cuenta.

Tiempo estimado: 30–45 min (más la espera de un posible aumento de cuota).

## Parte 1 · Comprobar la cuenta y los créditos (consola, usuario raíz)
1. Inicia sesión en https://console.aws.amazon.com con el correo de la cuenta (usuario raíz).
2. Arriba a la derecha, abre el menú de tu cuenta → **Billing and Cost Management**.
3. **Credits** (menú izquierdo): confirma el **monto**, el **saldo restante** y la **fecha de vencimiento**. Anótalos (no los pegues con datos de cuenta).
4. En el mismo lugar, abre las condiciones del crédito y revisa si **excluye servicios** (normalmente cubre EC2, EKS, SQS, Lambda; confirma que no excluye alguno de ellos).
5. **Account** (o *Account settings*): mira el **tipo de plan**. Con créditos de bienvenida la cuenta suele estar en **plan gratuito**. **No lo mejores a plan de pago** salvo que lo decidas a conciencia:
   mientras sigas en plan gratuito no se puede cobrar a la tarjeta, y los créditos se consumen primero. Con ese plan solo se permiten ciertos tipos de instancia (ver la Parte 6).
   **No uses AWS Organizations, Control Tower ni IAM Identity Center**: crear la organización pasa la cuenta a plan de pago y los créditos pueden vencer de inmediato.

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

## Parte 4 · Crear un usuario IAM propio con MFA (sin llaves de acceso)
1. Con el usuario raíz: **IAM → Users → Create user** (por ejemplo `poc-asr1-user`). **No marques** el acceso a consola de Identity Center ni crees *access keys*.
2. Permisos: adjunta la política administrada `AdministratorAccess` (es una cuenta personal solo para la PoC: EKS crea roles, redes y balanceadores; el límite real de gasto lo ponen el presupuesto, el plan gratuito y la destrucción final).
3. Activa **MFA** para este usuario (*Security credentials → Assign MFA device*).
4. A partir de aquí trabaja con este usuario, no con el raíz.

## Parte 5 · Conectar la línea de comandos con `aws login`
Requiere AWS CLI 2.32 o superior (`aws --version`; actualiza con `brew upgrade awscli`).
```bash
aws login --profile poc-asr1          # abre el navegador: inicia sesión con el usuario IAM + MFA
aws sts get-caller-identity --profile poc-asr1
```
Debe mostrar tu usuario IAM de la cuenta **personal**. Si ves una cuenta de trabajo, detente: el perfil está mal.

Terraform no siempre toma las credenciales de `aws login`. Si falla con *No valid credential sources found*, añade a `~/.aws/config` un perfil puente:
```ini
[profile poc-asr1-tf]
credential_process = aws configure export-credentials --profile poc-asr1 --format process
region = us-east-1
```
y usa `AWS_PROFILE=poc-asr1-tf` con Terraform, `kubectl` y los scripts del repositorio. Cuando la sesión caduque, repite `aws login --profile poc-asr1`.

## Parte 6 · Tipos de instancia y cuotas
- **Tipos permitidos en plan gratuito** (verifícalo en tu cuenta, cambia con el tiempo): `m7i-flex.large`, `c7i-flex.large` y las familias pequeñas `t3`/`t4g`. La PoC usa `m7i-flex.large` para el MS y `c7i-flex.large` para el generador de carga, ambos x86_64 (las imágenes se construyen para `linux/amd64`).
- **Cuota de vCPU** *Running On-Demand Standard*: una cuenta nueva parte con ~5 vCPU. Revisar (solo lectura):
```bash
aws service-quotas get-service-quota --profile poc-asr1 --region us-east-1 --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value'
```
  Con **5 vCPU** caben 2 nodos (modo «cuota-5»: el generador comparte nodos con el MS y no se puede medir un nodo nuevo). Con **16 vCPU** ya cabe el nodo de carga aislado y hasta 4 nodos del MS (lo que se usó en la PoC).
  Para pedir aumento: consola → **Service Quotas → Amazon EC2 → Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances → Request increase**. Puede tardar de minutos a un día (la aprobación puede ser parcial).

## Parte 7 · Avisar al asistente
Cuando termines, escribe en el chat: «**perfil listo**» (no pegues salidas con identificadores). El asistente entonces:
1. Verifica en modo lectura: identidad, cuota de vCPU, presupuesto.
2. Escribe y planifica el Terraform **sin aplicar**.
3. Pide tu confirmación explícita antes de cada `apply` y antes del `destroy` final.

## Parte 8 · Reglas para no gastar de más
- Al terminar cada sesión de pruebas se ejecuta `terraform destroy` y se verifica que no queden nodos, balanceadores, volúmenes ni IP elásticas.
- Mira **Cost Explorer** al día siguiente de cada corrida.
- Nunca uses este perfil para nada que no sea la PoC y nunca mezcles perfiles de trabajo.
- Si recibes una alerta de presupuesto, avísame y paramos y destruimos.
