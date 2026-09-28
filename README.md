<p align="center"><img src="assets/brand/maplong_logo.png" alt="MapLong" width="420"></p>

# MapLong

Aplicativo de **mapas mentais** que roda localmente (Windows, macOS, Linux ou no
navegador), funciona offline e salva seus documentos.

## Como rodar

Pré-requisito: [Flutter](https://docs.flutter.dev/get-started/install) 3.32 ou mais novo.

```bash
flutter pub get

# Desktop (recomendado — salva arquivos .maplong direto no disco)
flutter run -d windows   # ou: -d macos / -d linux

# Navegador
flutter run -d chrome
```

Para gerar um executável:

```bash
flutter build windows    # build/windows/x64/runner/Release/maplong.exe
flutter build macos      # build/macos/Build/Products/Release/
flutter build linux      # build/linux/x64/release/bundle/
flutter build web        # build/web/ (sirva com qualquer servidor estático)
```

> No Linux é preciso ter `clang cmake ninja-build pkg-config libgtk-3-dev`.

## Como seus mapas são salvos

- **Salvamento automático** na biblioteca local do app — nada se perde ao fechar.
- **Histórico de versões**: uma versão é guardada automaticamente a cada 10
  minutos de edição (Exibir → Versões); dá para restaurar qualquer uma.
- **Lixeira**: mapas excluídos ficam 30 dias na lixeira e podem ser restaurados.
- **Arquivos `.maplong`** (JSON legível): `Ctrl+S` salva, `Ctrl+Shift+S` salva como.
  Um `•` no título indica alterações ainda não gravadas no arquivo. Arquivos
  `.pmap` da versão anterior (PinealMap) continuam abrindo normalmente.
- Ao abrir o MapLong pela primeira vez, os mapas salvos com o nome antigo
  (PinealMap) são trazidos automaticamente.

## Recursos

**Tela inicial**
- Abas como no navegador: vários mapas abertos ao mesmo tempo (`Ctrl+T`, `Ctrl+W`, `Ctrl+Tab`)
- Modelos por categoria (Básico, Estudos, Projetos, Reuniões, Pessoal)
- Mapas recentes em lista ou grade, favoritos, lixeira e busca
- **Texto para mapa mental**: cole uma lista com recuo e gere o mapa
- Importa `.maplong`/`.pmap`, Markdown, TXT, OPML e FreeMind (`.mm`)

**Estruturas**: mapa balanceado, à direita, à esquerda, mapa lógico, organograma,
árvore, linha do tempo e espinha de peixe. Os tópicos se reorganizam sozinhos
enquanto você digita e **nunca ficam um em cima do outro** — nem com a posição
livre ou com tópicos flutuantes.

**Tópicos**
- Tópico depois/antes, subtópico, ramo principal, flutuante e vários de uma vez
- 2 cliques editam o nome e abrem as informações; 3 cliques criam um tópico conectado
- Seleção múltipla (`Ctrl`/`Shift` + clique, `Ctrl+A`): estilo e exclusão em grupo
- Formas, cores, fonte, negrito, itálico, sublinhado, tachado, alinhamento e largura
- Pincel de formato (`Ctrl+Alt+C` / `Ctrl+Alt+V`)

**Conteúdo**
- Imagens (reduzidas automaticamente), documentos anexados e **arrastar e soltar**
  arquivos direto no mapa
- Vários links por tópico: sites, e-mail, telefone e pastas
- Marcadores (prioridade, progresso, bandeira, estrela, humor, símbolos, dias)
- Adesivos (emojis) em 18 categorias
- Etiquetas, anotações e comentários
- Balões, limite do ramo, resumo com chave, tabela e fórmula (LaTeX)
- Tarefas com datas, responsável e progresso
- Relações (setas) com rótulo entre quaisquer tópicos
- Numeração automática (1, 1.1, 1.2…)

**Visões e modos**
- Mapa, **Esboço** (lista editável) e **Gantt** (arraste as barras para mudar datas)
- Apresentação ramo a ramo (`F5`), modo Zen (`F11`) e foco num ramo
- Minimapa, grade, zoom, localizar (`Ctrl+F`) e substituir (`Ctrl+H`)
- 8 temas de cores, cor de fundo, estilos de linha e espaçamento
- Tema claro e escuro do aplicativo

**Exportar**: imagem PNG, PDF, Word, Excel (CSV), HTML, Markdown, TXT, OPML e FreeMind.

## Atalhos

| Tecla | Ação |
|---|---|
| `Tab` | Novo subtópico |
| `Enter` / `Shift+Enter` | Tópico depois / antes |
| `Shift+Ins` | Novo ramo principal |
| `Alt+F` | Tópico flutuante |
| `Ctrl+R` | Criar relação (clique no tópico de destino) |
| `F2` / `Espaço` / digitar | Editar texto (`Enter` confirma, `Shift+Enter` quebra linha, `Esc` cancela) |
| 2 cliques / 3 cliques | Editar nome e informações / criar tópico conectado |
| `Ctrl`/`Shift` + clique, `Ctrl+A` | Seleção múltipla / selecionar tudo |
| `Del` / `Backspace` | Excluir |
| Setas, `Alt+↑` / `Alt+↓` | Navegar / reordenar entre irmãos |
| `/` | Recolher/expandir ramo |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copiar / recortar / colar (`Ctrl+Shift+V` cola texto como tópicos) |
| `Ctrl+Alt+C` / `Ctrl+Alt+V` | Copiar / colar estilo |
| `Ctrl+Z` / `Ctrl+Y` | Desfazer / refazer |
| `Ctrl+L` | Organizar mapa |
| `Ctrl+0`, `Ctrl +`, `Ctrl -` | Ajustar à tela, zoom |
| `Ctrl+F` / `Ctrl+H` | Localizar / substituir |
| `Ctrl+S` / `Ctrl+Shift+S` | Salvar / salvar como |
| `Ctrl+E` | Exportar PNG |
| `F5` / `F11` | Apresentação / modo Zen |
| `Ctrl+T` / `Ctrl+W` / `Ctrl+Tab` / `Ctrl+1…9` | Nova aba / fechar / próxima / ir para a aba |

## Estrutura do código

```
lib/
  main.dart               app, tema e migração do nome antigo
  models.dart             MindMapDoc / MindMapNode e elementos (+ JSON)
  library.dart            biblioteca local, favoritos, lixeira e versões
  editor_controller.dart  seleção, histórico e operações do editor
  layout.dart             estruturas automáticas e anti-sobreposição
  templates.dart          modelos e texto → mapa
  file_actions.dart       salvar arquivos .maplong e exportar PNG
  import_export.dart      PDF, Word, CSV, HTML, OPML, FreeMind, Markdown, TXT
  media.dart              imagens, documentos e arrastar e soltar
  io/                     leitura/gravação de arquivos (desktop x web)
  screens/                abas, tela inicial e editor
  widgets/                marca (logo), canvas, tópicos, painéis, faixa de ferramentas,
                          esboço, Gantt, marcadores e mídia
test/                     testes
```

Rodar os testes: `flutter test`
