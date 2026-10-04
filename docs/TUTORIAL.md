# MapLong — Tutorial completo

Guia passo a passo para **configurar o computador, rodar o MapLong, testar,
criar o instalador do Windows e colocar a versão web no ar**. Não é preciso
experiência prévia: cada passo diz o que fazer, o comando exato e o que você
deve ver se deu certo.

> Os comandos são digitados no **PowerShell** (menu Iniciar → digite
> "PowerShell" → Enter). Copie uma linha por vez e pressione Enter.

---

## Sumário

1. [O que você vai conseguir](#1-o-que-você-vai-conseguir)
2. [Preparar o computador (uma vez só)](#2-preparar-o-computador-uma-vez-só)
3. [Baixar o projeto](#3-baixar-o-projeto)
4. [Rodar o MapLong](#4-rodar-o-maplong)
5. [Testar](#5-testar)
6. [Onde ficam os seus mapas](#6-onde-ficam-os-seus-mapas)
7. [Criar o software instalável para Windows](#7-criar-o-software-instalável-para-windows)
8. [Colocar a versão web no ar](#8-colocar-a-versão-web-no-ar)
9. [Lançar uma nova versão](#9-lançar-uma-nova-versão)
10. [Problemas comuns e soluções](#10-problemas-comuns-e-soluções)
11. [Resumo dos comandos](#11-resumo-dos-comandos)

---

## 1. O que você vai conseguir

Ao final deste guia você terá:

- O MapLong **rodando no seu computador** em modo de desenvolvimento
  (as mudanças no código aparecem na hora).
- Os **testes automáticos** passando e um roteiro de **testes manuais**.
- Um **instalador** `MapLong-Setup-2.1.0.exe`, que instala o MapLong como
  qualquer programa: atalho no menu Iniciar e na área de trabalho,
  desinstalação pelo Windows e arquivos `.maplong` abrindo com dois cliques.
- A **versão web** publicada na internet, em
  `https://pedrojorell.github.io/mind-map/`.

---

## 2. Preparar o computador (uma vez só)

Você precisa de 4 programas: **Git**, **Flutter**, **Visual Studio** (para
compilar o app do Windows) e o **Inno Setup** (para gerar o instalador).
O **Chrome** é usado para a versão web.

### 2.1 Git (baixa e envia o código para o GitHub)

```powershell
winget install --id Git.Git -e
```

Feche e abra o PowerShell de novo. Confira:

```powershell
git --version
```

✅ Deve aparecer algo como `git version 2.5x.x`.

### 2.2 Flutter (a ferramenta que o MapLong usa)

1. Baixe o Flutter (versão estável) para `C:\src\flutter`:
   ```powershell
   git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
   ```
   > Evite pastas com espaço ou acento. Outra opção é baixar o ZIP em
   > https://docs.flutter.dev/get-started/install/windows e extrair em
   > `C:\src\flutter`.
2. Adicione o Flutter ao **PATH** (para o comando `flutter` funcionar em
   qualquer pasta):
   ```powershell
   [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';C:\src\flutter\bin', 'User')
   ```
   (Ou pela tela: menu Iniciar → "Editar as variáveis de ambiente" →
   **Variáveis de Ambiente** → em *Variáveis do usuário*, **Path** →
   **Editar** → **Novo** → `C:\src\flutter\bin` → OK em tudo.)
3. Feche e abra o PowerShell. Confira (a primeira vez demora, pois o Flutter
   termina de se preparar):
   ```powershell
   flutter --version
   ```
   ✅ Deve mostrar `Flutter 3.38` ou mais novo.

### 2.3 Visual Studio (para compilar o app do Windows)

> Não confunda com o **VS Code**. É o **Visual Studio Community** (gratuito).

1. Baixe em https://visualstudio.microsoft.com/pt-br/downloads/ →
   *Community* → **Download gratuito**.
2. No instalador, marque a carga de trabalho
   **"Desenvolvimento para desktop com C++"** e clique em **Instalar**.
   (São alguns GB; demora.)

### 2.4 Conferir tudo com o `flutter doctor`

```powershell
flutter doctor
```

✅ Precisam estar com `[√]`:

```
[√] Flutter
[√] Windows Version
[√] Chrome - develop for the web
[√] Visual Studio - develop Windows apps
```

A linha **Android toolchain** pode ficar com `[X]` — o MapLong não usa Android.

### 2.5 Inno Setup (só para gerar o instalador)

```powershell
winget install --id JRSoftware.InnoSetup -e
```

### 2.6 (Opcional) VS Code para editar o código

```powershell
winget install --id Microsoft.VisualStudioCode -e
```

No VS Code, instale a extensão **Flutter** (ela instala a de Dart junto).

---

## 3. Baixar o projeto

1. Escolha uma pasta **sem acentos** (ex.: `C:\projetos`):
   ```powershell
   mkdir C:\projetos
   cd C:\projetos
   ```
2. Baixe o código do GitHub:
   ```powershell
   git clone https://github.com/pedrojorell/mind-map.git
   cd mind-map
   ```
3. **Enquanto o Pull Request não for aceito no `main`**, a versão MapLong
   está no branch `claude/design-variation-3361e6`:
   ```powershell
   git checkout claude/design-variation-3361e6
   ```
   Depois que você fizer o **Merge** no GitHub (veja o passo 8.1), isso não é
   mais necessário: o `main` já terá tudo.
4. Baixe as bibliotecas que o projeto usa:
   ```powershell
   flutter pub get
   ```
   ✅ Deve terminar com `Got dependencies!`.

---

## 4. Rodar o MapLong

### 4.1 No Windows (recomendado)

```powershell
flutter run -d windows
```

A primeira vez demora alguns minutos (compila tudo). Depois abre a janela do
MapLong. Com o app aberto, no PowerShell você pode apertar:

| Tecla | O que faz |
|---|---|
| `r` | *Hot reload*: aplica na hora as mudanças que você fez no código |
| `R` | Reinicia o app do zero |
| `q` | Fecha o app |

### 4.2 No navegador (Chrome)

```powershell
flutter run -d chrome
```

> Na versão web os mapas ficam salvos **no navegador** (limpar os dados do
> site apaga os mapas). Anexar arquivos por caminho e abrir `.maplong` com
> dois cliques só existem no Windows.

### 4.3 Versão final (rápida, sem ferramentas de desenvolvimento)

```powershell
flutter build windows --release
```

✅ O programa fica em `build\windows\x64\runner\Release\maplong.exe`.
Para abrir: dois cliques no `maplong.exe`.
**Importante:** o `.exe` precisa das outras pastas/arquivos que estão ao lado
dele (`data`, DLLs). Para levar para outro computador, use o instalador
(passo 7) ou copie a pasta `Release` inteira.

---

## 5. Testar

### 5.1 Testes automáticos

```powershell
flutter analyze
flutter test
```

✅ Esperado:

```
No issues found!
00:10 +36: All tests passed!
```

Os testes verificam, entre outras coisas: salvar e reabrir mapas, desfazer e
refazer, as 8 estruturas de mapa, que **nenhum tópico fica em cima do outro**,
cliques duplo/triplo, seleção múltipla, lixeira, favoritos, versões,
importação e exportação (Markdown, OPML, FreeMind, CSV, HTML) e as APIs da
internet (com respostas simuladas, para não depender da conexão).

### 5.2 Roteiro de testes manuais (uso real)

Abra o MapLong (`flutter run -d windows` ou o instalado) e siga:

**Tela inicial**
- [ ] Clique em **Novo mapa ▸ Mapa clássico**: abre uma aba com o mapa.
- [ ] Volte ao **Início** (aba à esquerda) e cole no quadro
      *Texto para mapa mental*:
      ```
      Viagem
        Destino
          Praia
        Orçamento
      ```
      Clique em **Gerar mapa**: abre um mapa com esses tópicos.
- [ ] Clique na ⭐ de um mapa na lista: aparece em **Favoritos**.
- [ ] Menu ⋮ → **Mover para a lixeira** → abra **Lixeira** → **Restaurar**.

**Editar o mapa**
- [ ] Selecione um tópico e aperte `Tab` (subtópico) e `Enter` (tópico irmão).
- [ ] **2 cliques** num tópico: edita o nome e abre o painel de informações.
- [ ] **3 cliques** num tópico: cria um tópico ligado a ele.
- [ ] Digite um texto bem comprido num tópico: os vizinhos se afastam sozinhos
      (nenhum fica em cima do outro).
- [ ] `Ctrl+Z` desfaz, `Ctrl+Y` refaz.
- [ ] Aba **Design ▸ Estrutura**: teste Organograma, Linha do tempo e
      Espinha de peixe.

**Conteúdo**
- [ ] Aba **Inserir ▸ Imagem**: escolha uma foto do computador.
- [ ] Arraste um PDF do Explorador de Arquivos para cima de um tópico: vira
      anexo. Clique no 📎 do tópico para abrir.
- [ ] **Inserir ▸ Link ▸ Site** e depois clique no ícone do link no tópico.
- [ ] **Inserir ▸ Tarefa**, depois troque a visão para **Gantt** (topo) e
      arraste a barra da tarefa.

**Internet (precisa estar conectado)**
- [ ] Selecione um tópico, **Inserir ▸ Wikipédia**: pesquise, escolha um
      artigo, marque seções e clique em **Adicionar ao mapa**.
- [ ] **Inserir ▸ Imagens livres**: busque (ex.: `forest`) e clique numa imagem.
- [ ] **Design ▸ Tema por cor**: escolha uma cor e **Aplicar tema**.
- [ ] Na visão **Gantt**, os feriados nacionais aparecem destacados.

**Arquivos**
- [ ] `Ctrl+S`: salve como `teste.maplong` na Área de Trabalho.
- [ ] Botão **Exportar ▸ PDF** e **Exportar ▸ Word**: abra os arquivos gerados.
- [ ] Feche o MapLong e dê **dois cliques** no `teste.maplong`
      (só com o MapLong instalado — passo 7): o mapa abre.
- [ ] Com o MapLong aberto, dê dois cliques em outro `.maplong`: ele abre
      numa **aba nova da mesma janela** (não abre uma segunda janela).

---

## 6. Onde ficam os seus mapas

| Onde | Local |
|---|---|
| Windows | `%APPDATA%\MapLong\MapLong\shared_preferences.json` |
| Navegador | No armazenamento do próprio site (por navegador) |
| Arquivos `.maplong` | Onde você salvou com `Ctrl+S` |

- Para abrir a pasta no Windows: `Win + R` → digite `%APPDATA%\MapLong\MapLong` → Enter.
- **Backup:** copie esse arquivo, ou salve cada mapa como `.maplong` (`Ctrl+S`).
- **Histórico de versões:** Exibir ▸ Versões (uma versão automática a cada
  10 minutos de edição).
- Se você usava o app com o nome antigo (**PinealMap**), os mapas são
  trazidos automaticamente na primeira vez que o MapLong abre.
- **Configurações** (barra lateral da tela inicial, ou o ícone ⚙ no editor):
  tema claro/escuro/igual ao sistema, aviso de versão nova, boas-vindas e
  botões **Abrir pasta dos dados** e **Registro de erros**.
- **Registro de erros:** se algo der errado, o MapLong não fecha. Ele mostra
  um aviso e grava o detalhe em `%APPDATA%\MapLong\MapLong\logs\maplong.log`.
  Envie esse arquivo ao relatar um problema (Sobre ▸ **Relatar problema**).
- A barra de status do editor mostra **Salvando… / Salvo / Erro ao salvar**.
- A janela lembra o tamanho e a posição (e se estava maximizada) de uma vez
  para a outra.

---

## 7. Criar o software instalável para Windows

O resultado é um arquivo `MapLong-Setup-2.1.0.exe`, igual ao instalador de
qualquer programa.

### 7.1 Gerar o instalador (um comando)

Na pasta do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\criar_instalador.ps1
```

O script faz sozinho, em ordem:
1. baixa as dependências (`flutter pub get`);
2. roda os testes (se algum falhar, ele para);
3. compila o app (`flutter build windows --release`);
4. gera o instalador com o Inno Setup.

✅ No final aparece:

```
Pronto! Instalador em: C:\projetos\mind-map\installer\Output\MapLong-Setup-2.1.0.exe
```

### 7.2 Instalar

1. Dê dois cliques em `MapLong-Setup-2.1.0.exe`.
2. Se aparecer **"O Windows protegeu o computador"** (SmartScreen), clique em
   **Mais informações → Executar assim mesmo**. Isso acontece com todo
   programa novo que não tem assinatura digital paga (veja 10.6).
3. Siga o assistente. Você pode marcar:
   - **Criar um atalho na área de trabalho**;
   - **Abrir arquivos .maplong com o MapLong**.
4. Pronto: o MapLong aparece no **menu Iniciar**.

O instalador instala só para o seu usuário (não pede senha de administrador),
em `%LOCALAPPDATA%\Programs\MapLong`.

### 7.3 Desinstalar

Configurações do Windows → **Aplicativos** → **Aplicativos instalados** →
MapLong → **Desinstalar**. Seus mapas **não** são apagados (ficam em `%APPDATA%\MapLong`).

### 7.4 Atualizar para uma versão nova

1. Mude a versão no arquivo `pubspec.yaml`, por exemplo:
   `version: 2.1.0+4` (o número depois do `+` sempre aumenta).
2. Gere de novo o instalador (7.1) e instale por cima. O Windows reconhece
   que é o mesmo programa e atualiza.

### 7.5 Sem instalador (versão portátil)

Compacte a pasta `build\windows\x64\runner\Release` num ZIP. No outro
computador, extraia e abra o `maplong.exe`. (Não cria atalhos nem associa os
arquivos `.maplong`.)

---

## 8. Colocar a versão web no ar

A versão web é publicada **de graça** no **GitHub Pages**, automaticamente,
toda vez que o branch `main` é atualizado.

### 8.1 Juntar o MapLong no `main` (uma vez)

1. Abra
   https://github.com/pedrojorell/mind-map/compare/main...claude/design-variation-3361e6
2. Clique em **Create pull request** → **Create pull request**.
3. Clique em **Merge pull request** → **Confirm merge**.

### 8.2 Ligar o GitHub Pages (uma vez)

1. No repositório, abra **Settings** → **Pages** (menu da esquerda).
2. Em **Build and deployment → Source**, escolha **GitHub Actions**.

### 8.3 Publicar

A publicação roda sozinha a cada atualização do `main`. Para rodar agora:
aba **Actions** → **Publicar versão web** → **Run workflow**.

Ela: baixa o Flutter, analisa o código, roda os testes, compila a versão web
e publica. Se os testes falharem, **nada é publicado** (o site antigo continua).

✅ Depois de uns 5 minutos o site estará em:

**https://pedrojorell.github.io/mind-map/**

### 8.4 Outras hospedagens (opcional)

Compile e envie a pasta `build\web` para qualquer hospedagem de site estático
(Netlify, Vercel, Firebase Hosting, Cloudflare Pages):

```powershell
flutter build web --release --no-tree-shake-icons
```

- **Netlify (sem instalar nada):** entre em https://app.netlify.com/drop e
  arraste a pasta `build\web` para a página. Pronto.
- Se o site ficar numa **subpasta** (ex.: `/mind-map/`), compile com
  `--base-href "/mind-map/"`. Na raiz do domínio, não precisa.

### 8.5 Testar a versão web no seu computador antes de publicar

```powershell
flutter build web --release --no-tree-shake-icons
python -m http.server 8080 --directory build\web
```

(Sem Python? Com o Node.js instalado, use `npx serve build\web -l 8080`.)

Abra http://localhost:8080 no navegador. `Ctrl+C` no PowerShell encerra.

---

## 9. Lançar uma nova versão

Com o instalador disponível para qualquer pessoa baixar no GitHub:

1. Atualize a versão no `pubspec.yaml` (ex.: `version: 2.1.0+4`), faça o
   commit e envie:
   ```powershell
   git add -A
   git commit -m "Versão 2.1.0"
   git push
   ```
2. Crie a *tag* da versão e envie:
   ```powershell
   git tag v2.1.0
   git push origin v2.1.0
   ```
3. O GitHub roda a automação **Instalador Windows**: testa, compila, gera o
   `MapLong-Setup-2.1.0.exe` e cria um **Release** com ele.
4. O link para as pessoas baixarem fica em:
   https://github.com/pedrojorell/mind-map/releases

---

## 10. Problemas comuns e soluções

### 10.1 `flutter` (ou `git`) não é reconhecido

O programa não está no PATH. Feche e abra o PowerShell. Se continuar, refaça
o passo 2.2 (adicionar `C:\src\flutter\bin` ao Path) e reinicie o computador.

### 10.2 "Unable to find suitable Visual Studio toolchain"

Falta a carga **Desenvolvimento para desktop com C++** no Visual Studio.
Abra o **Visual Studio Installer** → **Modificar** → marque essa carga →
**Modificar**.

### 10.3 "Unable to generate build files" / erros do CMake

Sobras de uma compilação antiga. Apague e compile de novo:

```powershell
Remove-Item -Recurse -Force build\windows
flutter build windows --release
```

Se continuar: `flutter clean` e depois `flutter pub get`.

### 10.4 "não pode ser carregado porque a execução de scripts foi desabilitada"

Use exatamente o comando do passo 7.1, com `-ExecutionPolicy Bypass`.

### 10.5 "Inno Setup 6 não encontrado"

Instale com `winget install --id JRSoftware.InnoSetup -e`, feche e abra o
PowerShell e rode o script de novo.

### 10.6 Aviso do SmartScreen ao instalar

Normal para programas sem **assinatura digital de código**. Para o aviso
sumir para todo mundo, é preciso comprar um certificado de assinatura de
código (de empresas como Sectigo, DigiCert ou SSL.com) e assinar o
instalador com `signtool`. Para uso próprio, basta
**Mais informações → Executar assim mesmo**.

### 10.7 A versão web mostra uma versão antiga

O navegador guardou a versão anterior. Pressione `Ctrl + F5`. Se não
resolver: `F12` → **Application** → **Storage** → **Clear site data**.
(Isso também apaga os mapas salvos no navegador: exporte antes.)

### 10.8 Wikipédia / Imagens livres / Tema por cor não funcionam

Esses recursos usam a internet. Confira a conexão; se o serviço estiver fora
do ar, aparece a mensagem com o botão **Tentar de novo**. O resto do MapLong
funciona normalmente offline.

### 10.9 `flutter pub get` falha por conflito de versões

```powershell
flutter pub upgrade
```

Se continuar, confira se o Flutter está atualizado: `flutter upgrade`.

### 10.10 A verificação do Pull Request falhou (X vermelho no GitHub)

A automação **Verificar código** confere formatação, análise e testes. Rode
o mesmo no seu computador e corrija o que aparecer:

```powershell
dart format lib test
flutter analyze
flutter test
```

### 10.11 Como as pessoas ficam sabendo de versões novas

Quando você publica uma versão (passo 9), quem tem o MapLong instalado vê uma
faixa **"MapLong X disponível"** ao abrir o app, com o botão para baixar o
instalador. Dá para desligar em Configurações.

---

## 11. Resumo dos comandos

| Para… | Comando |
|---|---|
| Conferir as ferramentas | `flutter doctor` |
| Baixar dependências | `flutter pub get` |
| Rodar no Windows | `flutter run -d windows` |
| Rodar no navegador | `flutter run -d chrome` |
| Analisar o código | `flutter analyze` |
| Rodar os testes | `flutter test` |
| Compilar para Windows | `flutter build windows --release` |
| Compilar para web | `flutter build web --release --no-tree-shake-icons` |
| **Gerar o instalador** | `powershell -ExecutionPolicy Bypass -File scripts\criar_instalador.ps1` |
| Publicar uma versão | `git tag v2.1.0` e `git push origin v2.1.0` |
| Limpar tudo e recomeçar | `flutter clean` e `flutter pub get` |

---

### Sobre o projeto

- **APIs usadas** (gratuitas, sem chave, do catálogo
  [public-apis](https://github.com/public-apis/public-apis)): Wikipedia,
  Creative Commons Catalog (Openverse), BrasilAPI e The Color API.
- **Skills** para assistentes de IA ficam em `.claude/skills/` (skills
  oficiais do time do Flutter e o *find-skills*). Para procurar outras:
  `npx skills find <assunto>`.
- Estrutura do código e lista de recursos: veja o [README](../README.md).
