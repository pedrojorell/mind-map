# Licenças e vendas do MapLong

Este guia explica como o MapLong é vendido por **R$ 69,00** (licença vitalícia),
como o cliente recebe o código de ativação e como **só você** tem acesso total
sem pagar.

## Como funciona

```
Cliente clica em "Comprar"  ──►  Mercado Pago (Pix ou cartão)
                                      │ pagamento aprovado
                                      ▼
                          Servidor de vendas (Cloudflare, grátis)
                          • confere o pagamento no Mercado Pago
                          • gera o código com a CHAVE PRIVADA
                          • mostra o código na tela e envia por e-mail
                                      │
                                      ▼
Cliente cola o código no MapLong  ──►  o app confere com a CHAVE PÚBLICA
                                        (sem internet) e libera tudo
```

- **Chave privada**: cria os códigos. Fica só com você, na pasta
  `C:\Users\<você>\MapLong-Licencas\` e como segredo no servidor. **Nunca**
  vai para o GitHub.
- **Chave pública**: está dentro do app (`lib/licensing/license.dart`). Ela só
  confere códigos e não consegue criá-los.
- **Teste grátis**: 7 dias com tudo liberado. Depois, sem licença, o app fica
  em **modo leitura**: abre, apresenta e exporta os mapas, mas não cria nem
  edita. Os dados do cliente nunca ficam presos.
- **Proprietário**: um código especial (plano "dono") que libera tudo, sem
  pagar. Só quem tem a chave privada consegue gerá-lo.

As chaves já foram criadas (veja abaixo). Só se elas ainda não existirem, crie
com o comando a seguir. Criar outras invalida todas as licenças já vendidas.

```bash
node gerador.mjs chaves %USERPROFILE%\MapLong-Licencas
```

Depois coloque a chave pública que aparecer em `kLicensePublicKey`
(`lib/licensing/license.dart`).

## O que já está pronto no seu computador

| Item | Onde |
|---|---|
| Par de chaves (privada e pública) | `%USERPROFILE%\MapLong-Licencas\` |
| Sua licença de proprietário (já ativada no MapLong) | `minha-licenca-de-proprietario.txt` |
| Gerador de licenças | atalho **Gerador de Licenças MapLong** na área de trabalho |
| Valores para o servidor | `segredos-do-servidor.txt` |

> **Faça uma cópia de segurança da pasta `MapLong-Licencas`** (pendrive ou nuvem
> privada). Se a chave privada se perder, não dá para gerar códigos que as
> versões já instaladas aceitem.

## Gerar uma licença à mão (sem servidor)

1. Dois cliques em **Gerador de Licenças MapLong** (área de trabalho).
2. Digite o e-mail do cliente e escolha **1** (Pro) ou **2** (Proprietário).
3. O código aparece e já fica copiado. Envie ao cliente.

O cliente ativa em **MapLong → Configurações → Ativar licença → cole o código
→ Ativar**.

Pelo terminal (dentro da pasta `MapLong-Licencas` ou de `licencas/`):

```bash
node gerador.mjs gerar cliente@email.com
```

```bash
node gerador.mjs gerar voce@email.com --dono
```

```bash
node gerador.mjs conferir MAPLONG-...
```

## Colocar a venda automática no ar

Você vai precisar de: conta no **Mercado Pago** (a que recebe o dinheiro),
conta grátis na **Cloudflare** e, para enviar o código por e-mail, conta grátis
no **Brevo**. O Node.js já está instalado.

### 1. Credencial do Mercado Pago

1. Entre em <https://www.mercadopago.com.br/developers/panel/app> e clique em
   **Criar aplicação** (tipo: *Pagamentos on-line*, produto *Checkout Pro*).
2. Abra a aplicação → **Credenciais de produção** → copie o **Access Token**
   (começa com `APP_USR-`). Ele é secreto.

### 2. Publicar o servidor na Cloudflare

No terminal, dentro da pasta `licencas` do projeto:

```bash
npx wrangler login
```

Uma página abre no navegador; entre (ou crie a conta grátis) e autorize.
Depois publique:

```bash
npx wrangler deploy
```

No fim aparece o endereço da loja, por exemplo
`https://maplong-licencas.SEU-NOME.workers.dev`. Guarde-o.

### 3. Guardar os segredos no servidor

Rode um comando por vez; cada um pede o valor (cole e aperte Enter):

```bash
npx wrangler secret put MP_ACCESS_TOKEN
```

```bash
npx wrangler secret put LICENSE_PRIVATE_KEY
```

```bash
npx wrangler secret put ADMIN_PASSWORD
```

- `MP_ACCESS_TOKEN`: o Access Token do passo 1.
- `LICENSE_PRIVATE_KEY` e `ADMIN_PASSWORD`: estão em
  `MapLong-Licencas\segredos-do-servidor.txt` (cole a linha inteira).

Abra `https://SEU-ENDERECO/saude`: `mercadoPago`, `chaveDeLicenca` e `gerador`
devem aparecer como `true`.

### 4. (Recomendado) Enviar o código por e-mail

1. Crie a conta em <https://www.brevo.com> e confirme um remetente em
   **Senders, Domains & Dedicated IPs → Senders** (pode ser seu Gmail).
2. Em **SMTP & API → API Keys**, crie uma chave.
3. Guarde a chave no servidor:

   ```bash
   npx wrangler secret put BREVO_API_KEY
   ```

4. Em `licencas/wrangler.toml`, preencha `EMAIL_FROM = "seu-remetente@gmail.com"`
   e publique de novo com `npx wrangler deploy`.

Sem isso, o código aparece na tela logo após o pagamento (o cliente copia de
lá) e você pode reenviar pelo gerador on-line.

### 5. (Recomendado) Registro das vendas

Guarda cada licença emitida e evita e-mails repetidos:

```bash
npx wrangler kv namespace create LICENCAS
```

Copie o `id` que aparece, tire o `#` das três linhas de `[[kv_namespaces]]` no
`wrangler.toml`, cole o id e rode `npx wrangler deploy`.

### 6. (Opcional) Assinatura dos avisos do Mercado Pago

No painel da aplicação → **Webhooks → Configurar notificações**: URL
`https://SEU-ENDERECO/webhook/mercadopago`, evento **Pagamentos**. Salve, copie
a **assinatura secreta** e guarde:

```bash
npx wrangler secret put MP_WEBHOOK_SECRET
```

### 7. Ligar o botão "Comprar" no app

Em `lib/licensing/license.dart`, troque:

```dart
const kStoreUrl = '';
```

por:

```dart
const kStoreUrl = 'https://SEU-ENDERECO/';
```

Gere a nova versão (tutorial, seção 7 ou 9). O botão **Comprar agora** passa a
aparecer na tela da licença e no aviso de fim do teste.

### 8. Testar sem gastar

No Mercado Pago, em **Suas integrações → Contas de teste**, crie um vendedor e
um comprador de teste. Publique com o Access Token do **vendedor de teste**,
compre usando o **comprador de teste** e confira o código. Depois troque para o
token de produção (`npx wrangler secret put MP_ACCESS_TOKEN`).

## Gerador on-line (para você)

`https://SEU-ENDERECO/admin` com a senha `ADMIN_PASSWORD`:

- gera licenças Pro ou de Proprietário de qualquer lugar (até pelo celular);
- **recupera o código de uma venda** pelo número do pagamento do Mercado Pago
  (para quando o cliente perde o e-mail) e pode reenviar por e-mail.

## Testes automáticos

```bash
npm test
```

Simulam o Mercado Pago e o Brevo: compra, Pix pendente, pagamento com valor
errado, aviso repetido, assinatura falsa, gerador on-line e mais. Rodam também
em cada Pull Request no GitHub.

## Segurança e limites (leia)

- **Não compartilhe** `chave-privada.json`, `segredos-do-servidor.txt` nem o
  Access Token. Se vazarem, crie um novo token no Mercado Pago. A chave privada
  só pode ser trocada junto com uma nova versão do app, e os códigos antigos
  deixam de valer.
- O código mostra o e-mail do comprador em **Sobre** e na tela da licença, o
  que desestimula compartilhar o código.
- **Código aberto**: enquanto o repositório for público, quem souber programar
  pode baixar o código e compilar sem a trava. Para vender de verdade, deixe o
  repositório **privado** e distribua só o instalador. Atenção: com o
  repositório privado, o aviso de versão nova (que consulta os *releases*
  públicos) e o GitHub Pages grátis param de funcionar; publique os
  instaladores em outro lugar (por exemplo, um repositório público só com os
  *releases*).
- Reembolsos: a licença funciona sem internet e não é desativada sozinha.
  Pelo Código de Defesa do Consumidor, compras on-line podem ser canceladas em
  até 7 dias.
