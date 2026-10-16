# dinna-flutter

Aplicativo Flutter do **Dinna** — _"Pedido à mesa, do seu jeito."_

O Dinna é um aplicativo de pedidos feitos **dentro do restaurante** (não é delivery). O cliente identifica a mesa, navega pelo cardápio, monta o carrinho e acompanha o pedido; o restaurante recebe, atualiza o status e finaliza — sem perder o atendimento humano. Um único app atende os dois perfis (cliente e restaurante).

Projeto acadêmico — disciplina de Flutter, Pós Mobile UTFPR.
Equipe: Jean Carlos, Felipe Souza, Gabriel Abreu, João Victor.

Backend: [`dinna-api`](https://github.com/jeancarlosaps/dinna-api).

## Estado atual (R0 — Fundação)

| Item                                         | Situação                                        |
| -------------------------------------------- | ----------------------------------------------- |
| Projeto Flutter (Android + iOS)              | Pronto                                          |
| MVVM com fluxo de referência                 | Pronto (Home → verificação de `GET /health`)    |
| Tema Dinna (Material 3)                      | Pronto                                          |
| Configuração da URL da API por ambiente      | Pronta (`--dart-define=API_BASE_URL`)           |
| Cliente HTTP centralizado + erros uniformes  | Base pronta (`ApiClient`)                       |
| Lint, format, testes, CI                     | Prontos                                         |
| Models, rotas cliente/restaurante, telas     | Próximas Tasks/Stories (ver Jira)               |
| Persistência local                           | A definir em SCRUM-27 (T1.8)                    |

## Stack

- **Flutter** 3.47 (stable) / **Dart** 3.13 — null safety
- **Material 3** com tema próprio
- **MVVM** com `ChangeNotifier` + `ListenableBuilder` (nativos do Flutter)
- **http** para chamadas REST
- **flutter_lints** + regras extras em `analysis_options.yaml`

## Requisitos

- Flutter stable 3.47.x (`flutter --version`)
- Xcode (iOS) e/ou Android Studio com Android SDK (Android)
- `flutter doctor` sem erros para a plataforma desejada
- [`dinna-api`](https://github.com/jeancarlosaps/dinna-api) rodando localmente para testar integração

## Instalação

```bash
flutter pub get
```

## Execução

Suba a API antes (`npm run dev` no `dinna-api`, porta `3333`).

### iOS Simulator

```bash
open -a Simulator
flutter run
```

O simulador compartilha a rede do Mac: o app usa `http://localhost:3333` por padrão.

### Android Emulator

```bash
flutter emulators --launch <id>
flutter run
```

No emulador, `localhost` é o próprio emulador. O app usa `http://10.0.2.2:3333` por padrão (alias do computador host).

### Dispositivo físico

Celular e computador na mesma rede; a API precisa escutar em `0.0.0.0` (padrão do `.env.example` da API):

```bash
flutter run --dart-define=API_BASE_URL=http://<IP-do-computador>:3333
```

### Resumo da URL da API

| Onde o app roda    | URL padrão               | Como mudar                         |
| ------------------ | ------------------------ | ---------------------------------- |
| iOS Simulator      | `http://localhost:3333`  | `--dart-define=API_BASE_URL=...`   |
| Android Emulator   | `http://10.0.2.2:3333`   | `--dart-define=API_BASE_URL=...`   |
| Dispositivo físico | — (obrigatório definir)  | `--dart-define=API_BASE_URL=...`   |

> Tráfego HTTP sem TLS para a API local: o iOS Simulator permite `localhost`; Android (API 28+) e dispositivos físicos podem bloquear cleartext. A liberação para desenvolvimento entra junto com a integração real (SCRUM-26, T1.7). Nenhuma credencial vai no código ou no `--dart-define`.

## Testes e qualidade

| Comando                                         | O que faz                  |
| ----------------------------------------------- | -------------------------- |
| `dart format .`                                 | Formata (largura 100)      |
| `dart format --output=none --set-exit-if-changed .` | Verifica formatação    |
| `flutter analyze --fatal-infos`                 | Análise estática           |
| `flutter test`                                  | Testes unitários e widget  |

A CI (`.github/workflows/ci.yml`) roda format check, analyze e testes em todo push na `main` e em todo pull request.

> **Nota local:** em pastas com acento no caminho (ex.: `PósMobile-UTFPR`), o `flutter analyze` 3.47 falha com `FormatException: Unexpected end of input` no servidor de análise. Use `dart analyze --fatal-infos`, que produz o mesmo resultado. A CI não é afetada.

## Arquitetura

MVVM simples, sem camadas extras:

```
View (Widget) → ViewModel (ChangeNotifier) → Repository → ApiClient / armazenamento local
```

| Camada     | Responsabilidade                                                      | Não pode                         |
| ---------- | --------------------------------------------------------------------- | -------------------------------- |
| View       | Desenhar estado, repassar ações do usuário                            | Ter regra de negócio, chamar HTTP |
| ViewModel  | Estado da tela, orquestrar ações, `notifyListeners()`                 | Conhecer `BuildContext`/widgets  |
| Repository | Fonte de dados do domínio, converter JSON ↔ model                     | Conhecer UI                      |
| ApiClient  | HTTP, timeout, URL base, conversão de erro em `ApiException`          | Conhecer regra de negócio        |

Fluxo de referência implementado: `HomeView` → `HomeViewModel` → `ApiStatusRepository` → `ApiClient` → `GET /health`.

Dependências são montadas em `main.dart` e passadas por construtor (sem service locator). O ViewModel é criado no `State` da tela e descartado no `dispose`.

## Estrutura

```
lib/
├── main.dart                     # composição: config, ApiClient, repositories
├── app/
│   ├── app.dart                  # MaterialApp + tema + rotas
│   ├── router/app_router.dart    # nomes de rota e onGenerateRoute
│   └── theme/                    # DinnaColors e DinnaTheme (Material 3)
├── core/
│   ├── config/app_config.dart    # API_BASE_URL por ambiente
│   └── network/                  # ApiClient e ApiException
└── features/
    └── home/                     # tela inicial provisória (fluxo de referência)
test/                             # espelha lib/
```

Novas features seguem o mesmo padrão em `lib/features/<feature>/` (ex.: `table`, `menu`, `product`, `cart`, `orders`, `restaurant`, `recommendation`). Models compartilhados entre features vão em `lib/shared/models/`, widgets reutilizáveis em `lib/shared/widgets/` — pastas criadas quando houver o primeiro arquivo.

## Decisões técnicas

| Decisão                                        | Motivo                                                                                   |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `ChangeNotifier` + `ListenableBuilder`         | Nativo, suficiente para MVVM, zero dependência. Provider/Riverpod/Bloc só se houver dor real. |
| `http`                                         | Pacote oficial do time Dart, simples e testável com `MockClient`.                        |
| Navegação nativa (`onGenerateRoute`)           | Rotas ainda poucas; `go_router` pode entrar na Task de navegação (SCRUM-23) se necessário. |
| `--dart-define` para URL da API                | Sem arquivo de configuração versionado, sem segredo no código.                           |
| Sem pacote de armazenamento local ainda        | Mecanismo é decisão da Task SCRUM-27 (T1.8).                                             |
| Sem fontes externas                            | Tipografia do sistema até a definição final no Figma.                                    |

## Contribuição

- Branch a partir da `main`: `feature/SCRUM-<n>-descricao` ou `fix/SCRUM-<n>-descricao`.
- Commits pequenos, em português, no padrão `tipo: descrição` (`feat`, `fix`, `chore`, `ci`, `docs`, `test`, `refactor`).
- Pull Request para a `main` com CI verde e revisão de outro integrante.
- Antes de abrir PR: `dart format . && flutter analyze --fatal-infos && flutter test`.

## Links

- Jira (SCRUM): https://jeancarlosaps.atlassian.net/jira/software/projects/SCRUM/boards/1
- Figma: https://www.figma.com/design/xYeeN6UBmj3lF458GF9qwA/Dinna-%C2%B7-App-Cliente?node-id=0-1
- API: https://github.com/jeancarlosaps/dinna-api
