# Site de vendas do MapLong — tutorial completo

Este guia mostra **onde colocar o link de pagamento**, **como cadastrar o
MapLong na Kiwify, Cakto ou Kirvano** e **como colocar o site no ar** (GitHub
Pages, Netlify ou Vercel), passo a passo.

## Sumário

1. [O que já está pronto](#1-o-que-já-está-pronto)
2. [Onde colocar o link de pagamento](#2-onde-colocar-o-link-de-pagamento)
3. [Como o cliente recebe o MapLong](#3-como-o-cliente-recebe-o-maplong)
4. [Kiwify](#4-kiwify)
5. [Cakto](#5-cakto)
6. [Kirvano](#6-kirvano)
7. [Colocar o site no ar](#7-colocar-o-site-no-ar)
8. [Domínio próprio (opcional)](#8-domínio-próprio-opcional)
9. [Testar antes de divulgar](#9-testar-antes-de-divulgar)
10. [Checklist final](#10-checklist-final)

---

## 1. O que já está pronto

A pasta **`site/`** do projeto é o site completo:

| Arquivo | Para que serve |
|---|---|
| `index.html` | Página de vendas (recursos, imagens do app, preço, dúvidas, botão **Comprar**) |
| `download.html` | Página entregue **depois da compra**: botão de download e como instalar |
| `privacidade.html` | Política de privacidade e termos de uso (as plataformas costumam pedir) |
| **`config.js`** | **O único arquivo que você edita**: link de pagamento, preço, contato… |
| `style.css`, `script.js`, `img/` | Visual, funcionamento e imagens (não precisa mexer) |

Para ver no seu computador: dê dois cliques em `site\index.html`. Enquanto o
link de pagamento estiver vazio, aparece uma faixa amarela lembrando disso
(ela só aparece no seu computador, nunca para os visitantes).

---

## 2. Onde colocar o link de pagamento

1. Abra a pasta do projeto → **`site`** → clique com o botão direito em
   **`config.js`** → **Abrir com** → **Bloco de Notas** (ou VS Code).
2. Encontre a linha:

   ```js
   linkPagamento: '',
   ```

3. Cole o link do checkout **entre as aspas**, por exemplo:

   ```js
   linkPagamento: 'https://pay.kiwify.com.br/AbCdEfG',
   ```

4. Ajuste também, se quiser:

   | Campo | Exemplo | O que faz |
   |---|---|---|
   | `preco` | `'R$ 69,00'` | Preço mostrado no site |
   | `precoAntigo` | `'R$ 97,00'` | Aparece riscado ao lado do preço (vazio = não mostra) |
   | `parcelamento` | `'ou em até 12x no cartão'` | Texto abaixo do preço |
   | `linkDownloadWindows` | link do instalador | Botão da página `download.html` |
   | `emailSuporte` | `'contato@seudominio.com.br'` | Rodapé e página de download |
   | `whatsapp` | `'5511999999999'` | Botão verde do WhatsApp (só números, com 55 e DDD) |
   | `diasGarantia` | `7` | Prazo de garantia mostrado no site |
   | `linkVersaoWeb` | `''` | Link opcional para usar no navegador |

5. **Salve** (Ctrl+S) e publique o site de novo (seção 7).

Todos os botões "Comprar" passam a abrir o checkout. Se o visitante chegar
por um anúncio com `?utm_source=...`, esses parâmetros são repassados ao
checkout sozinhos, e a plataforma mostra de onde veio cada venda.

> Trocar de plataforma no futuro é só colar o novo link no mesmo lugar.

---

## 3. Como o cliente recebe o MapLong

O caminho mais simples, que funciona nas três plataformas:

1. **Hospede o instalador** `MapLong-Setup-2.1.0.exe` (gerado pelo tutorial
   principal, seção 7) em um lugar com link de download:
   - **Google Drive:** envie o arquivo → botão direito → **Compartilhar** →
     "Qualquer pessoa com o link" → **Copiar link**.
   - ou **GitHub Releases** (seção 9 do tutorial principal).
2. Cole esse link em `linkDownloadWindows` no `config.js`.
3. Na plataforma de pagamento, escolha **entrega por link externo** e informe
   o endereço da página de download do seu site:
   `https://SEU-SITE/download.html`.

O cliente paga → recebe o e-mail da plataforma com o link → abre a página de
download → baixa e instala.

> ⚠️ **Importante:** quem tiver o link do instalador consegue baixar. Não
> divulgue a página `download.html` (ela já fica fora do Google). Lembre
> também que o repositório do GitHub é público: quem souber programar pode
> compilar o MapLong a partir do código. Para vender com mais proteção,
> deixe o repositório **privado** (Settings → General → Danger Zone → Change
> visibility) e guarde o instalador no Google Drive.

---

## 4. Kiwify

**Site:** https://kiwify.com.br · **Link do checkout:** começa com
`https://pay.kiwify.com.br/`

### 4.1 Criar a conta

1. Acesse kiwify.com.br → **Cadastrar agora** e preencha seus dados.
2. Confirme o e-mail e complete o perfil.
3. Em **Financeiro**, cadastre a conta bancária que vai receber as vendas.

### 4.2 Cadastrar o produto

1. No menu lateral, clique em **Produtos** → **Criar produto** (canto
   superior direito).
2. Escolha **Pagamento único**.
3. Formato de entrega: escolha **área externa / link externo** e informe
   `https://SEU-SITE/download.html` (ou use a área de membros da Kiwify e
   coloque lá o link de download).
4. Preencha:
   - **Nome:** MapLong — Mapas mentais para Windows
   - **Descrição:** o que é o programa e o que o cliente recebe
   - **Preço:** 69,00 (o mínimo da plataforma é R$ 5,00)
   - **Página de vendas:** o endereço do seu site (ex.:
     `https://pedrojorell.github.io/mind-map/`). **É obrigatório** — a equipe
     da Kiwify usa esse link para revisar o produto.
   - **E-mail de suporte:** o seu e-mail de atendimento.
5. Clique em **Criar produto** e aguarde a revisão.

### 4.3 Copiar o link do checkout

- **Produtos** → ícone **[...]** → **Ver links**, ou abra o produto → aba
  **Links** → copie o link do checkout.
- Cole em `linkPagamento` no `config.js` (seção 2).

### 4.4 Página de obrigado (opcional)

Abra o produto → aba **Configurações** → campo da URL da página de obrigado
→ cole `https://SEU-SITE/download.html`. Assim, logo após pagar, o cliente
já cai na página de download.

---

## 5. Cakto

**Site:** https://www.cakto.com.br · **Ajuda:** https://ajuda.cakto.com.br ·
**Link do checkout:** começa com `https://pay.cakto.com.br/`

### 5.1 Criar a conta

1. Acesse cakto.com.br, crie a conta e confirme o e-mail.
2. Complete os dados pessoais/empresa e cadastre a conta bancária para saque.

### 5.2 Cadastrar o produto

1. Menu **Produtos** → **Adicionar Produto**.
2. **Etapa 1 – Informações:** imagem (JPG/PNG, 300x250 px), **Nome**,
   **Descrição** (mínimo de 100 caracteres) e **Moeda** (Real) → **Avançar**.
3. **Etapa 2 – Modelo de pagamento:** **Pagamento Único**, valor **69,00**
   (mínimo R$ 5,00), métodos de pagamento (Pix, cartão, boleto) e
   parcelamento → **Avançar**.
4. **Etapa 3 – Configurações:** página de vendas (o endereço do seu site),
   e-mail de suporte e **canal de entrega** — escolha **Acesso por e-mail**
   ou **Área de membros externa** e informe
   `https://SEU-SITE/download.html`.
5. Ao concluir aparece "Produto criado com sucesso!" e o produto fica
   **Ativo**.

### 5.3 Copiar o link do checkout

- **Produtos** → **três pontinhos (...)** ao lado do produto → **Ver links**
  → ícone de copiar ao lado do link de checkout; **ou**
- clique no produto → aba **Links** → copie o link de checkout.

Cole em `linkPagamento` no `config.js`.

---

## 6. Kirvano

**Site:** https://kirvano.com · **Ajuda:** https://help.kirvano.com ·
**Link do checkout:** começa com `https://pay.kirvano.com/`

### 6.1 Criar a conta

1. Acesse kirvano.com, crie a conta e confirme o e-mail.
2. Complete o cadastro e informe a conta bancária para receber.

### 6.2 Cadastrar o produto

1. Menu lateral **Produtos** → **Add Product / Adicionar produto**.
2. Preencha **Nome**, **Descrição**, **Categoria** e **Tipo de produto**:
   escolha **arquivo digital único** (single digital file).
3. **Forma de entrega:** **Entrega externa** (External Delivery) e informe o
   link `https://SEU-SITE/download.html`.
4. **Salve** o produto. A Kirvano faz uma análise de aprovação; se for
   recusado, a central de ajuda explica o motivo ("My Product Was
   Rejected").

### 6.3 Criar a oferta (é ela que gera o checkout)

1. Abra o produto → aba **Ofertas** → **Criar oferta**.
2. **Nome da oferta:** "Licença vitalícia" · **Preço:** 69,00 ·
   **Tipo de cobrança:** **Pagamento único** (One-Time Charge).
3. Escolha os meios de pagamento (cartão, Pix, boleto) e o parcelamento.
4. **Salvar oferta**.

### 6.4 Copiar o link do checkout

Na aba **Ofertas**, copie o link de checkout da oferta (formato
`https://pay.kirvano.com/xxxxxxxx-xxxx-...`) e cole em `linkPagamento`.

---

## 7. Colocar o site no ar

Escolha **uma** das opções. Todas são gratuitas.

### Opção A — GitHub Pages (já configurado no projeto)

1. Junte as mudanças ao `main`: abra
   https://github.com/pedrojorell/mind-map/compare/main...claude/design-variation-3361e6
   → **Create pull request** → **Merge pull request** → **Confirm merge**.
2. No repositório: **Settings** → **Pages** → em **Source** escolha
   **GitHub Actions**.
3. Aba **Actions** → **Publicar site** → **Run workflow**.
4. Em cerca de 2 minutos o site está em
   **https://pedrojorell.github.io/mind-map/**.

Para atualizar (ex.: depois de colar o link no `config.js`): envie a mudança
para o `main` (no GitHub você pode editar o arquivo direto: abra
`site/config.js` → ícone de lápis → edite → **Commit changes**). O site se
atualiza sozinho.

> Com o repositório **privado**, o GitHub Pages exige plano pago. Nesse caso
> use a opção B ou C.

### Opção B — Netlify (arrastar e soltar, o mais fácil)

1. Crie uma conta grátis em https://app.netlify.com/signup.
2. Abra https://app.netlify.com/drop.
3. **Arraste a pasta `site`** (do projeto) para a página.
4. Em segundos o site está no ar com um endereço como
   `https://nome-aleatorio.netlify.app`.
5. Para trocar o nome: **Site configuration** → **Change site name** →
   ex.: `maplong` → `https://maplong.netlify.app`.
6. **Para atualizar:** aba **Deploys** → arraste a pasta `site` de novo.

### Opção C — Vercel (atualiza sozinho pelo GitHub)

1. Crie uma conta em https://vercel.com com o login do GitHub.
2. **Add New** → **Project** → escolha o repositório **mind-map** →
   **Import**.
3. Em **Root Directory** clique em **Edit** e escolha a pasta **`site`**.
4. **Framework Preset:** **Other** → **Deploy**.
5. O site fica em `https://mind-map-xxxx.vercel.app` e se atualiza a cada
   mudança no `main`.

---

## 8. Domínio próprio (opcional)

Um endereço como `www.maplong.com.br` passa mais confiança.

1. Registre o domínio em https://registro.br (cerca de R$ 40 por ano).
2. Ligue o domínio à hospedagem escolhida:
   - **GitHub Pages:** Settings → Pages → **Custom domain** → digite o
     domínio → siga as instruções de DNS.
   - **Netlify:** **Domain management** → **Add a domain**.
   - **Vercel:** projeto → **Settings** → **Domains** → **Add**.
3. No Registro.br, em **DNS**, crie os registros que a hospedagem mostrar.
   Pode levar algumas horas para funcionar.
4. Atualize a **página de vendas** e o link de entrega
   (`https://SEU-DOMINIO/download.html`) na plataforma de pagamento.

---

## 9. Testar antes de divulgar

1. Abra o site publicado e clique em **todos os botões "Comprar"** —
   devem abrir o checkout da plataforma.
2. Confira preço, nome do produto e formas de pagamento no checkout.
3. Faça **uma compra de teste** (o jeito mais seguro em qualquer plataforma é
   comprar você mesmo com Pix e depois pedir o reembolso pelo painel).
4. Confira se chegou o **e-mail** com o link e se a página `download.html`
   baixa o instalador.
5. Instale o MapLong em outro computador seguindo a página de download.
6. Abra o site pelo **celular** e confira o visual.

---

## 10. Checklist final

- [ ] Produto cadastrado e aprovado na plataforma
- [ ] Link do checkout colado em `linkPagamento` (`site/config.js`)
- [ ] Instalador hospedado e link em `linkDownloadWindows`
- [ ] Entrega da plataforma apontando para `https://SEU-SITE/download.html`
- [ ] E-mail de suporte e WhatsApp preenchidos
- [ ] Site publicado (GitHub Pages, Netlify ou Vercel)
- [ ] Compra de teste feita e reembolsada
- [ ] Repositório privado, se quiser proteger o código

**Atualizar as imagens do site** (depois de mudar o visual do app):

```powershell
flutter test tool/capturas/capturas_test.dart --update-goldens
Copy-Item tool\capturas\*.png site\img\
```
