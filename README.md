<a id="topo"></a>

<p align="center">
  <picture>
    <source media="(prefers-reduced-motion: reduce)" srcset="docs/assets/readme/hero-still.svg" />
    <img src="docs/assets/readme/hero.svg" alt="dinna. — Pedido à mesa, do seu jeito. Ilustração conceitual do app: um prato visto de cima, um celular com cardápio e carrinho, e um cartão de acompanhamento do pedido." width="1600" />
  </picture>
</p>

<h1 align="center">dinna-flutter</h1>

<p align="center">
  <strong>Pedido à mesa, do seu jeito.</strong><br />
  O aplicativo Flutter do Dinna: a experiência do cliente e a operação do restaurante em um único app.
</p>

<p align="center">
  <a href="#comece-aqui"><strong>COMEÇAR →</strong></a>
  &nbsp;·&nbsp;
  <a href="#arquitetura">ARQUITETURA</a>
  &nbsp;·&nbsp;
  <a href="#estado-atual">O QUE JÁ EXISTE</a>
  &nbsp;·&nbsp;
  <a href="#roadmap">ROADMAP</a>
  &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">CONTRIBUIR</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/jeancarlosaps/dinna-api">BACKEND REST DO DINNA</a>
</p>

<p align="center">
  <a href="https://github.com/jeancarlosaps/dinna-flutter/actions/workflows/ci.yml"><img src="https://github.com/jeancarlosaps/dinna-flutter/actions/workflows/ci.yml/badge.svg?branch=main" alt="Status da CI na branch main" /></a>
  <img src="https://img.shields.io/badge/Flutter-3.47.7-B4532A?logo=flutter&amp;logoColor=white" alt="Flutter 3.47.7" />
  <img src="https://img.shields.io/badge/Dart-3.13.5-5E7355?logo=dart&amp;logoColor=white" alt="Dart 3.13.5" />
  <img src="https://img.shields.io/badge/Material-3-2A211C" alt="Material 3" />
  <img src="https://img.shields.io/badge/status-R0%20%C2%B7%20funda%C3%A7%C3%A3o%20em%20andamento-A86B12" alt="Status: R0, fundação em andamento" />
</p>

---

## Ecossistema Dinna

O Dinna é formado por dois repositórios que trabalham juntos:

| Repositório | Papel | Stack |
|---|---|---|
| **dinna-flutter** (este) | App único com dois perfis: **cliente** (mesa, cardápio, carrinho, pedido) e **restaurante** (fila, status, cardápio) | Flutter · Dart · Material 3 |
| [**dinna-api**](https://github.com/jeancarlosaps/dinna-api) | Backend REST do Dinna: produtos, pedidos, status e, depois, recomendações | Node.js · TypeScript · Fastify |

```mermaid
flowchart LR
  subgraph APP["dinna-flutter · um app, dois perfis"]
    C["Perfil cliente"]
    R["Perfil restaurante"]
  end
  C -- "REST · JSON" --> API["dinna-api<br/>Fastify"]
  R -- "REST · JSON" --> API
  classDef app fill:#FBF6F0,stroke:#B4532A,color:#2A211C
  classDef api fill:#2A211C,stroke:#2A211C,color:#FBF6F0
  class C,R app
  class API api
```

Hoje o único endpoint integrado entre os dois é `GET /health`. Os models do app já seguem o [contrato inicial da API](https://github.com/jeancarlosaps/dinna-api/blob/main/docs/api-contract.md). A SCRUM-24, que define esse contrato, está concluída no Jira. Os demais endpoints ainda não são chamados pelo app.

---

## 01 · O produto

O Dinna é um app de pedidos feitos **dentro do restaurante**. **Não é delivery.**

Em restaurantes, pizzarias e bares com atendimento à mesa, boa parte do pedido depende de um atendente estar livre: para trazer o cardápio, tirar dúvidas, anotar o pedido e contar em que etapa ele está. No horário de pico, o tempo entre *“já sei o que quero”* e *“a cozinha recebeu meu pedido”* passa a depender mais da equipe do que do cliente.

O Dinna encurta esse intervalo **sem substituir o atendimento humano**:

- o cliente identifica a mesa, explora o cardápio, monta o carrinho, envia o pedido e acompanha o status;
- o restaurante recebe os pedidos em fila, atualiza o preparo e mantém o cardápio em dia;
- na release R2, o recurso **“Me ajuda a escolher”** vai sugerir pratos com base nas preferências do cliente e no cardápio real.

> As personas e o problema vêm da Atividade 1 de Gestão de Projetos: Marina (cliente) e Ricardo (restaurante). As hipóteses ainda não foram validadas com usuários reais.

<a id="estado-atual"></a>

## 02 · Estado atual

Fundação (R0) **em andamento**. MVVM, models, cliente HTTP e o mapa de rotas da SCRUM-23 já estão na `dev`. A home em `/` continua o fluxo `GET /health`. A `TableView` do PR #3 está em `/table`: o layout e o campo da mesa aparecem, e os botões ainda não navegam. Cardápio, produto, carrinho, pedido e o painel do restaurante seguem como `RoutePlaceholder`.

| Item | Situação | Onde |
|---|---|---|
| Projeto Flutter (Android + iOS) | ✅ Executa no **Android Emulator** (API 36) e no **iOS Simulator** (iPhone 17) | `android/`, `ios/` |
| MVVM com fluxo de referência | ✅ View → ViewModel → Repository → Service (`ApiClient`) → `GET /health` | `lib/features/home/`, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Tema Dinna (Material 3) | ✅ Paleta e componentes base do tema | `lib/app/theme/` |
| URL da API por ambiente | ✅ `--dart-define=API_BASE_URL` com padrão por plataforma | `lib/core/config/` |
| Cliente HTTP + erro uniforme | ✅ `ApiClient` + `ApiException` | `lib/core/network/` |
| Testes, lint, format, CI | ✅ 72 testes · `flutter analyze --fatal-infos` · GitHub Actions | `test/`, `.github/` |
| Models (`Product`, `CartItem`, `Order`, `OrderItem`, `OrderStatus`, `Preference`) | ✅ Implementados em `lib/core/domain/` (SCRUM-22, PR #5 na `dev`) | [`lib/core/domain/`](lib/core/domain/) |
| Rotas do cliente e do restaurante | ✅ SCRUM-23 concluída e mergeada pelo PR #6. Mapa em `AppRoutes`. Rota inicial `/`. `/table` abre `TableView`; as outras rotas da jornada são placeholder | [`lib/app/router/`](lib/app/router/), [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Layout da mesa (`/table`) | Layout mergeado pelo PR #3. O campo da mesa é só visual: nada lê o valor. “Ver cardápio” e “Acessar o painel” usam `onPressed` vazio | [`lib/features/client/table/table_view.dart`](lib/features/client/table/table_view.dart) |
| Dependências base (SCRUM-18) | Em andamento. HTTP pronto (`http` 1.6.0 e `ApiClient`). Armazenamento local ainda sem pacote no `pubspec` | `pubspec.yaml`, [`lib/core/network/`](lib/core/network/) |
| Persistência local | ⬜ SCRUM-27 em andamento com João. A proposta no Jira é `sqflite`; o pacote ainda não entrou neste repositório | — |
| Componentes visuais reutilizáveis | ⬜ SCRUM-28 em análise. O tema já está na `dev`; os componentes seguem na branch `feature/SCRUM-28-tipografia-componentes`, sem merge | `lib/app/theme/` |
| Telas de R1, R2 e R3 | ⬜ Jornada planejada. Na `dev` só o layout da mesa está em `/table`; as outras telas seguem placeholder ou ainda não existem | — |

---

## 03 · Experiência planejada

<p align="center">
  <img src="docs/assets/readme/flow.svg" alt="Jornada planejada para R1. Cliente: mesa, cardápio, produto, carrinho, pedido e acompanhamento. O pedido vai para a fila do restaurante, que vê detalhes, atualiza o preparo e finaliza; o status volta para o cliente. O restaurante também mantém o cardápio." width="1600" loading="lazy" />
</p>

A jornada abaixo é a **R1 planejada**. Na `dev`, a etapa Mesa tem layout em `/table` (`TableView`, PR #3). Esse layout não guarda o número da mesa e os botões não navegam, então a story de informar a mesa continua pendente. Cardápio, produto, carrinho, pedido, acompanhamento e o painel do restaurante ainda não têm View: o router mostra `RoutePlaceholder`. Os nomes de rota já estão no mapa da SCRUM-23, mergeado pelo PR #6.

**Cliente (Marina)**

| Etapa | O que faz | Epic |
|---|---|---|
| Mesa | Informa o número da mesa manualmente (QR Code fica para a R3) | E2 |
| Cardápio | Navega por categorias, busca e vê produtos indisponíveis | E2 |
| Produto | Vê imagem, descrição e preço; escolhe a quantidade | E3 |
| Carrinho | Adiciona, altera quantidade, remove e confere o total | E4 |
| Pedido | Envia o pedido da mesa e recebe a confirmação | E5 |
| Acompanhamento | Segue o status: Recebido → Preparando → Pronto → Finalizado | E6 |

**Restaurante (Ricardo)**

| Etapa | O que faz | Epic |
|---|---|---|
| Fila | Recebe os pedidos das mesas | E7 |
| Detalhes | Vê itens, quantidades e observações | E7 |
| Preparo | Atualiza o status do pedido | E7 |
| Finalização | Marca o pedido como finalizado | E7 |
| Cardápio | Cria, edita, desativa e controla a disponibilidade dos produtos | E8 |

---

## 04 · Stack

| Camada | Escolha | Por quê |
|---|---|---|
| UI | Flutter 3.47.7 (stable), Material 3 | Um código para Android e iOS; Material 3 com tema próprio |
| Linguagem | Dart 3.13.5, null safety | Padrão do Flutter stable |
| Estado | `ChangeNotifier` + `ListenableBuilder` | Nativos do Flutter e suficientes para MVVM; sem dependência extra |
| HTTP | [`http`](https://pub.dev/packages/http) 1.6.0 | Pacote oficial do time Dart, testável com `MockClient` |
| Navegação | `onGenerateRoute` nativo | A SCRUM-23, concluída no PR #6, manteve o `Navigator` do Flutter. O mapa está em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Lint | `flutter_lints` 6.0.0 + regras em `analysis_options.yaml` | Análise estrita (`strict-casts`, `strict-raw-types`) |

Dependências diretas: `http` 1.6.0 e `cupertino_icons`, que veio no template do Flutter. Nenhuma biblioteca de estado, injeção de dependência ou armazenamento foi adicionada. A SCRUM-18 segue em andamento por causa do armazenamento local. A SCRUM-27 propõe `sqflite` no Jira; essa escolha ainda não está no `pubspec`.

<a id="arquitetura"></a>

## 05 · Arquitetura MVVM

```mermaid
flowchart LR
  V["View<br/>HomeView"] -- "ação" --> VM["ViewModel<br/>HomeViewModel"]
  VM -. "estado" .-> V
  VM --> R["Repository<br/>ApiStatusRepository"]
  R --> S["Service<br/>ApiClient (http)"]
  S -- "GET /health" --> API[["dinna-api"]]
  classDef layer fill:#FBF6F0,stroke:#B4532A,color:#2A211C
  classDef ext fill:#2A211C,stroke:#2A211C,color:#FBF6F0
  class V,VM,R,S layer
  class API ext
```

| Camada | Responsabilidade | Não pode |
|---|---|---|
| **View** | Desenhar o estado e repassar ações do usuário | Ter regra de negócio ou chamar HTTP |
| **ViewModel** | Guardar loading, success e error e orquestrar a ação | Conhecer widget, `http` ou `ApiException` |
| **Repository** | Entregar dados ao ViewModel e traduzir payload e falhas do Service | Conhecer UI ou estado visual |
| **Service (`ApiClient`)** | HTTP, serialização, timeout e status code; falhas viram `ApiException` | Conhecer regra de negócio ou estado de tela |

O contrato completo, as dependências permitidas, o passo a passo do `GET /health` e como criar a próxima feature estão em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Regras que o código já segue:

- As dependências são montadas em [`lib/main.dart`](lib/main.dart) e passadas por construtor. Não há service locator.
- O ViewModel nasce no `State` da tela (`createViewModel`) e é descartado no `dispose`.
- O Repository traduz `ApiException` em `ApiAvailability`. O ViewModel só vê online, offline e a mensagem. Outra falha tira a tela de `checking` e a leva a `offline` com um texto genérico, sem o detalhe interno. Depois do `dispose`, o ViewModel não altera estado nem notifica.
- O `ApiClient` lê o formato de erro da API (`{ "error": { "code", "message" } }`) e converte falhas de rede, timeout, HTTP e corpo que não é JSON em `ApiException`.

### Estrutura real

```text
lib/
├── main.dart                         # composição: AppConfig, ApiClient, repositories
├── app/
│   ├── app.dart                      # MaterialApp + tema + rotas
│   ├── router/
│   │   ├── app_router.dart           # nomes de rota e onGenerateRoute
│   │   └── route_placeholder.dart    # página mínima até a View da story
│   └── theme/
│       ├── dinna_colors.dart         # paleta Dinna
│       └── dinna_theme.dart          # ThemeData Material 3
├── core/
│   ├── config/app_config.dart        # API_BASE_URL por ambiente
│   ├── domain/                       # models da SCRUM-22
│   └── network/
│       ├── api_client.dart           # Service HTTP
│       └── api_exception.dart        # erro uniforme
└── features/
    ├── client/
    │   └── table/
    │       └── table_view.dart       # layout da mesa em /table; botões sem navegação
    └── home/                         # fluxo de referência (tela provisória)
        ├── api_status_repository.dart
        ├── http_api_status_repository.dart
        ├── home_view.dart
        └── home_view_model.dart
test/                                 # espelha lib/ (72 testes)
docs/ARCHITECTURE.md                  # contrato das camadas MVVM
docs/assets/readme/                   # ilustrações deste README
```

A pasta `table` já existe com o layout da mesa. `menu`, `product`, `cart`, `orders`, `restaurant` e `recommendation` ainda não. Os models compartilhados ficam em `lib/core/domain/`. Os widgets reutilizáveis entram com a SCRUM-28, ainda sem merge, na branch `feature/SCRUM-28-tipografia-componentes`.

O PR #3 também versionou dois PDFs em `lib/`: `Dinna · App Cliente Marina.pdf` (5,5 MB) e `Dinna · App Restaurante Ricardo.pdf` (8,6 MB). Eles não estão declarados como asset no `pubspec` e não são código da feature. Ficam no clone, ao lado dos fontes, e aumentam o repositório. A retirada fica para outro PR.

<a id="comece-aqui"></a>

## 06 · Comece aqui

### 1. Instale o Flutter

Siga o guia oficial da sua plataforma: <https://docs.flutter.dev/get-started/install>. Use o canal **stable**, versão **3.47.x**.

O SDK pode ficar em qualquer pasta. Uma alternativa portável é clonar o canal stable e adicionar `bin/` ao `PATH`:

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/development/flutter
export PATH="$HOME/development/flutter/bin:$PATH"   # adicione ao seu ~/.zshrc ou ~/.bashrc
flutter --version
```

### 2. Prepare o ambiente

```bash
flutter doctor
```

| Plataforma | O que o `flutter doctor` precisa mostrar |
|---|---|
| iOS (macOS) | `[✓] Xcode` |
| Android | `[✓] Android toolchain`: Android SDK, `cmdline-tools` e licenças aceitas (`flutter doctor --android-licenses`) |

### 3. Clone e instale as dependências

```bash
git clone git@github.com:jeancarlosaps/dinna-flutter.git
cd dinna-flutter
flutter pub get
```

### 4. Suba a API

O app conversa com o [dinna-api](https://github.com/jeancarlosaps/dinna-api) na porta `3333`. Siga o README da API e deixe `npm run dev` rodando.

### 5. Configure a URL da API

Sem configuração, o app escolhe a URL pela plataforma ([`app_config.dart`](lib/core/config/app_config.dart)):

| Onde o app roda | URL padrão | Por quê |
|---|---|---|
| iOS Simulator | `http://localhost:3333` | O simulador usa a rede do Mac |
| Android Emulator | `http://10.0.2.2:3333` | `10.0.2.2` é o alias do computador host dentro do emulador |
| Dispositivo físico | — (obrigatório informar) | Use o IP do computador na rede local |

Para mudar, passe `--dart-define=API_BASE_URL=<url>` no `flutter run`. Nenhuma credencial vai no código nem no `--dart-define`.

> **HTTP sem TLS.** O app usa `package:http`, que abre sockets do próprio Dart (`dart:io`). Desde o Flutter 2.2, esses sockets não seguem a política de cleartext da plataforma ([documentação](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android)), por isso `http://` para a API local não precisa de `networkSecurityConfig` (Android) nem de exceção ATS (iOS). Se algum dia o app passar a usar um cliente HTTP nativo da plataforma, essas configurações passam a ser necessárias. O manifesto principal do Android declara `INTERNET`, porque o release não herda a permissão que o Flutter coloca só em debug e profile. No Android Emulator, com a API fora do ar, o botão “Verificar conexão com a API” mostrou “Não foi possível conectar à API”. Dispositivo físico ainda não foi testado.

### 6. Execute no iOS

```bash
open -a Simulator
flutter run
```

### 7. Execute no Android

```bash
flutter emulators                     # lista os emuladores disponíveis
flutter emulators --launch <id>
flutter run
```

> **Android validado em debug.** Em 24/10/2026 o app foi instalado e aberto no emulador `Dinna_Phone_API_36.1` (API 36, arm64). O `flutter doctor` desta máquina ainda aponta `cmdline-tools` ausente; o Gradle aceitou a licença do NDK que já estava no SDK e concluiu o `assembleDebug`. A CI continua sem compilar Android nem iOS.

### 8. Dispositivo físico

Com o celular e o computador na mesma rede, e a API escutando em `0.0.0.0` (padrão do `.env.example` da API):

```bash
flutter run --dart-define=API_BASE_URL=http://<IP-do-computador>:3333
```

Na tela inicial, toque em **“Verificar conexão com a API”**: com a API no ar, o card mostra **“API online”**.

---

## 07 · Testes e qualidade

| Comando | O que faz |
|---|---|
| `flutter test` | Testes unitários e de widget |
| `flutter analyze --fatal-infos` | Análise estática; qualquer aviso faz o comando falhar |
| `dart format .` | Formata o código (largura 100) |
| `dart format --output=none --set-exit-if-changed .` | Só verifica a formatação, como na CI |

O que os 72 testes cobrem hoje (`flutter test` nesta branch):

| Arquivo | Cobre |
|---|---|
| `test/app_test.dart` | O app inicia com o tema Dinna; o fluxo View → ViewModel → Repository |
| `test/app/app_router_test.dart` | Rota inicial `/`, `/table` com `TableView`, placeholder nas outras rotas do mapa, ida e volta, rota desconhecida e `GET /health` depois do retorno |
| `test/core/domain/` | `fromJson` e `toJson` de `Product`, `Order`, `OrderItem`, `CartItem` e `Preference` |
| `test/core/app_config_test.dart` | URL padrão por plataforma e prioridade do `API_BASE_URL` |
| `test/core/api_client_test.dart` | Montagem da URL, erro da API, falha de rede e corpo que não é JSON |
| `test/features/home/api_status_repository_test.dart` | Tradução de `/health`: ok, payload inesperado, rede e HTTP inválido |
| `test/features/home/home_view_model_test.dart` | `checking` antes da resposta, success, error, exceção inesperada e `dispose` |

### `flutter analyze` em pastas com acento

| | |
|---|---|
| **Sintoma** | `FormatException: Unexpected end of input` ao rodar `flutter analyze` |
| **Quando** | O caminho do projeto tem caractere não ASCII (ex.: `PósMobile-UTFPR`). Reproduzido no Flutter 3.47.7 com um projeto mínimo |
| **Causa** | O `flutter_tools` envia o cabeçalho `Content-Length` do protocolo LSP contando caracteres, quando deveria contar bytes UTF-8. Com acento no caminho, a mensagem chega cortada ao servidor de análise |
| **Workaround** | `dart analyze --fatal-infos`, que não usa esse canal e mostra os mesmos diagnósticos |
| **Correção definitiva** | Depende de uma correção no Flutter. A CI não é afetada (o caminho no runner é ASCII) |

Não renomeie pastas nem altere o SDK para contornar o problema.

---

## 08 · CI

O workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) roda em todo push na `main` e em todo pull request:

```text
checkout → Flutter 3.47.7 (stable) → flutter pub get → dart format (check) → flutter analyze --fatal-infos → flutter test
```

Não há deploy, assinatura nem publicação em loja, e a CI não compila Android nem iOS.

---

## 09 · Integração com o backend

| Contrato | Situação | Usado por |
|---|---|---|
| `GET /health` → `{ "status": "ok" }` | **Implementado** nos dois lados | `ApiStatusRepository` |
| Formato de erro `{ "error": { "code", "message" } }` | **Implementado** nos dois lados | `ApiClient` |
| `/products`, `/orders`, `/orders/:id/status` | **Planejado no app** (R1). O contrato inicial está concluído no Jira (SCRUM-24); o app ainda não chama esses endpoints | — |
| `/ai/recommendation` | **Planejado** (R2) | — |

Fonte do contrato: [`dinna-api/docs/api-contract.md`](https://github.com/jeancarlosaps/dinna-api/blob/main/docs/api-contract.md). A SCRUM-24 está concluída no Jira.

<a id="roadmap"></a>

## 10 · Roadmap

<p align="center">
  <img src="docs/assets/readme/roadmap.svg" alt="Roadmap ilustrado da R0 à R3. A figura ainda marca models, rotas e contrato como pendentes; a tabela abaixo é o estado em 25/10/2026. R1, R2 e R3 seguem planejados." width="1600" loading="lazy" />
</p>

A ilustração acima é o desenho inicial da fundação e ainda mostra models, rotas e contrato em aberto. O arquivo SVG não foi alterado. A tabela abaixo é o estado consultado em 25/10/2026 na `dev` (`79b8156`).

Situação das tasks R0 que tocam este repositório. A coluna **Jira** é o status no board em 25/10/2026; a coluna **Código** é o que existe nesta branch.

| Issue | Task | Jira | Código |
|---|---|---|---|
| SCRUM-16 | Criar e configurar o projeto Flutter | Concluído | Executa no Android e no iOS; estrutura de pastas definida |
| SCRUM-18 | Configurar dependências base (HTTP e armazenamento local) | Em andamento | HTTP pronto: `http` 1.6.0 e `ApiClient` em `lib/core/network/`. Armazenamento local ainda sem dependência |
| SCRUM-19 | Estruturar a arquitetura MVVM | Concluído | Implementada. Contrato em `docs/ARCHITECTURE.md`; `GET /health` é o fluxo de referência |
| SCRUM-22 | Definir os models principais | Concluído | Implementados em `lib/core/domain/` e mergeados na `dev` pelo PR #5 |
| SCRUM-23 | Configurar a navegação base | Concluído | Mergeada na `dev` pelo PR #6. Mapa em `AppRoutes`. Rota inicial `/`. `/table` abre `TableView`; as outras rotas da jornada são placeholder |
| SCRUM-24 | Definir o contrato inicial da API REST | Concluído | Contrato aceito. O app consome `GET /health`. Os outros endpoints do contrato ainda não são chamados daqui |
| SCRUM-26 | Configurar o cliente HTTP | Concluído | `ApiClient` centralizado com erro uniforme, revisado e concluído |
| SCRUM-27 | Definir a persistência local | Em andamento | Sem código neste repositório. O Jira propõe `sqflite` para carrinho, preferências e último pedido; o pacote não está no `pubspec` |
| SCRUM-28 | Estrutura visual base | Em análise | Tema pronto na `dev`. Componentes reutilizáveis ainda sem merge, na branch `feature/SCRUM-28-tipografia-componentes` |

A entrega acadêmica é 14/11/2026. As releases R1, R2 e R3 seguem sem data própria no Jira. A SCRUM-23 está concluída no Jira e na `dev`. A SCRUM-18 está em andamento: HTTP pronto, armazenamento local pendente. A SCRUM-27 está em andamento e ainda não tem persistência neste repositório.

---

## 11 · Como contribuir

O fluxo completo está em [CONTRIBUTING.md](CONTRIBUTING.md). Em resumo:

1. Pegue uma issue no [Jira (SCRUM)](https://jeancarlosaps.atlassian.net/jira/software/projects/SCRUM/boards/1).
2. Crie a branch a partir da `main`: `feature/SCRUM-<n>-descricao`, `fix/SCRUM-<n>-descricao` ou `chore/SCRUM-<n>-descricao`.
3. Valide antes do PR: `dart format . && flutter analyze --fatal-infos && flutter test`.
4. Abra o PR usando o [template](.github/pull_request_template.md), com a CI verde e a revisão de outro integrante.

## 12 · Equipe

| Integrante | Foco planejado no backlog |
|---|---|
| Jean Carlos | Arquitetura e fundação do app, QA de arquitetura |
| Felipe Souza | Contrato REST, cliente HTTP, backend e fluxo do restaurante |
| Gabriel Abreu | Experiência do cliente e estrutura visual |
| João Victor | Persistência local e evoluções |

Os focos vêm da distribuição de issues no backlog (Atividade 2) e não são cargos formais.

## 13 · Próximos passos

1. **SCRUM-18:** declarar a dependência de armazenamento local quando a SCRUM-27 registrar a escolha neste repositório. O HTTP já está pronto. Esquema, tabelas e repositório ficam na SCRUM-27.
2. **SCRUM-27:** João segue com a estratégia de persistência (carrinho, preferências e último pedido). A proposta no Jira é `sqflite`, ainda sem pacote no `pubspec`.
3. **SCRUM-28:** componentes Dinna reutilizáveis, em análise na branch `feature/SCRUM-28-tipografia-componentes`. O tema já está na `dev`.
4. **Mesa:** ligar os botões da `TableView` ao mapa (`/menu` e `/restaurant`) e decidir se a rota inicial deixa de ser `/`. O layout atual não é o fluxo pronto. Se a rota inicial passar a ser `/table`, os testes que esperam a home em `/` precisam ser adaptados.
5. **PDFs em `lib/`:** o PR #3 versionou `Dinna · App Cliente Marina.pdf` (5,5 MB) e `Dinna · App Restaurante Ricardo.pdf` (8,6 MB) ao lado do código. Não são asset do app. A organização fica para outro PR.
6. **Ambiente:** instalar `cmdline-tools` para o `flutter doctor` ficar verde. O debug Android já executa sem esse componente.

## 14 · Links

- Jira (SCRUM): <https://jeancarlosaps.atlassian.net/jira/software/projects/SCRUM/boards/1>
- Figma: <https://www.figma.com/design/xYeeN6UBmj3lF458GF9qwA/Dinna-%C2%B7-App-Cliente?node-id=0-1>
- Backend REST do Dinna: <https://github.com/jeancarlosaps/dinna-api>
- Sistema visual dos READMEs: [docs/assets/readme/DESIGN.md](docs/assets/readme/DESIGN.md)

<p align="center"><sub>Projeto acadêmico · Pós Mobile UTFPR · disciplina de Flutter · <a href="#topo">voltar ao topo ↑</a></sub></p>
