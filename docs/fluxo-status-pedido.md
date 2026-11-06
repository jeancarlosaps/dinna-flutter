# Fluxo de status do pedido (front)

> **Escopo deste doc:** você fica com **Recebido → Preparando → Pronto → Finalizado** no Flutter — estados de interface e tratamento de erros.
>
> Referências: [README · E6/E7](../README.md), [contrato REST](https://github.com/jeancarlosaps/dinna-api/blob/main/docs/api-contract.md) (rascunho SCRUM-24).

---

## 1. O que é (em uma frase)

O pedido nasce como **Recebido** e só avança nessa ordem até **Finalizado**. O restaurante muda o status; o cliente só acompanha.

```text
Recebido  →  Preparando  →  Pronto  →  Finalizado
received     preparing      ready      finished
```

| Valor na API (`status`) | Label na UI | Quem age |
|---|---|---|
| `received` | Recebido | Sistema (ao criar o pedido) |
| `preparing` | Preparando | Restaurante |
| `ready` | Pronto | Restaurante |
| `finished` | Finalizado | Restaurante |

**Regra de ouro:** só avança **um passo**. Não pula etapa. Não volta.

---

## 2. O que entra / o que não entra

### Entra (seu front)

| Perfil | Tela / pedaço | Ação |
|---|---|---|
| **Restaurante** | Fila + detalhe do pedido | Botão “avançar status” (um passo) |
| **Restaurante** | Feedback visual | Loading, sucesso, erro no avanço |
| **Cliente** | Acompanhamento do pedido | Ler e mostrar o status atual |
| **Ambos** | Erros | Mensagem clara + retry quando fizer sentido |

### Não entra (outro dono / outra issue)

- Montar carrinho e criar pedido (`POST /orders`) — fluxo do cliente (E5)
- CRUD de cardápio (E8)
- Design system completo (SCRUM-28) — reutilizar tema Dinna; componentes novos só se faltar o mínimo
- Definir o contrato definitivo da API (SCRUM-24) — consumir o que estiver no contrato; se faltar campo, abrir issue / alinhar com backend

---

## 3. Máquina de estados (domínio)

```dart
enum OrderStatus {
  received,   // Recebido
  preparing,  // Preparando
  ready,      // Pronto
  finished,   // Finalizado
}
```

Transições válidas:

```text
received  → preparing
preparing → ready
ready     → finished
finished  → (fim; sem botão de avanço)
```

Qualquer outra transição (pular, voltar, repetir) = **inválida**. Tratar no ViewModel **antes** de chamar a API e também se a API responder conflito/validação.

Sugestão de helper:

```dart
OrderStatus? nextStatus(OrderStatus current) => switch (current) {
  OrderStatus.received => OrderStatus.preparing,
  OrderStatus.preparing => OrderStatus.ready,
  OrderStatus.ready => OrderStatus.finished,
  OrderStatus.finished => null,
};
```

Label do botão do restaurante (exemplo):

| Status atual | Texto do botão |
|---|---|
| Recebido | Iniciar preparo |
| Preparando | Marcar como pronto |
| Pronto | Finalizar pedido |
| Finalizado | — (oculto / desabilitado) |

---

## 4. Estados de interface

Espelhe o padrão da Home (`unknown / checking / online / offline`): View só desenha; ViewModel guarda o estado.

### 4.1 Tela de acompanhamento (cliente)

| Estado UI | Quando | O que mostrar |
|---|---|---|
| `loading` | Primeira carga do pedido | Skeleton / spinner |
| `ready` | Pedido carregado | Stepper ou chips: Recebido → Preparando → Pronto → Finalizado (atual destacado) |
| `refreshing` | Pull-to-refresh ou polling | Mantém o último status visível + indicador leve |
| `error` | Falha ao carregar / atualizar | Mensagem + botão **Tentar de novo** |
| `notFound` | Pedido não existe (404) | “Pedido não encontrado” (sem retry infinito) |

Passos visuais:

- etapas **já passadas**: concluídas (check / cor sage)
- etapa **atual**: destaque (terracota ou amber “em andamento”)
- etapas **futuras**: apagadas / outline

### 4.2 Fila / detalhe (restaurante)

| Estado UI | Quando | O que mostrar |
|---|---|---|
| `loading` | Carregando fila ou detalhe | Spinner / skeleton |
| `empty` | Nenhum pedido aberto | Empty state (“Nenhum pedido na fila”) |
| `ready` | Lista/detalhe ok | Cards com mesa, itens, status, CTA de avanço |
| `updating` | Enquanto `PATCH .../status` roda | Botão desabilitado + loading no CTA (não trava a tela inteira se possível) |
| `error` | Falha de lista ou de avanço | Mensagem; na lista → retry; no avanço → snackbar/banner + manter status antigo |
| `conflict` | API recusou a transição (ex.: 409 / validação) | Explicar (“Esse pedido já avançou”) + **recarregar** o pedido |

Após sucesso no avanço: atualizar o status local **e** refletir na lista (ou invalidar e buscar de novo).

---

## 5. Tratamento de erros

Tudo que falha na rede vira `ApiException` (já existe em `lib/core/network/`). A View **nunca** lê HTTP cru.

| Situação | `statusCode` | O que o usuário vê | Ação |
|---|---|---|---|
| Sem rede / timeout / API fora | `null` | “Não foi possível conectar” / “Tempo esgotado” | **Tentar de novo** |
| Pedido ou rota inexistente | `404` | “Pedido não encontrado” | Voltar / ir à fila |
| Body/status inválido | `400` | Mensagem da API (`error.message`) | Corrigir fluxo; se for status, recarregar |
| Conflito de status | `409` (se a API usar) | “Status desatualizado” | Recarregar pedido |
| Erro inesperado | `500` / outros | “Algo deu errado. Tente de novo.” | Retry |

Regras práticas:

1. **Não limpar** o último status bom na tela enquanto um refresh falha — mostre o erro por cima.
2. Em `updating`, se der erro, o status na UI **permanece o anterior** (não “finja” o próximo passo).
3. Botão de avanço: `onPressed: null` enquanto `updating` (igual ao botão da Home em `checking`).
4. Mensagem amigável na View; log técnico só se o time já tiver padrão (hoje: só `ApiException.message`).

---

## 6. API que você consome (planejado)

Fonte: contrato em rascunho. Confirmar nomes na SCRUM-24 antes de fechar o PR.

| Método | Rota | Uso no front |
|---|---|---|
| `GET /orders` | Fila do restaurante | Listar pedidos + status |
| `GET /orders/:id` | *(se existir no contrato final)* | Detalhe / acompanhamento |
| `POST /orders` | Criação | Fora do seu escopo (só depende do status inicial `received`) |
| `PATCH /orders/:id/status` | Avançar status | Body sugerido: `{ "status": "preparing" }` (validar no contrato) |

Pedido (esboço):

```json
{
  "id": "o1",
  "table": "12",
  "status": "received",
  "items": [{ "productId": "p1", "quantity": 2, "note": "sem cebola" }],
  "totalCents": 6580,
  "createdAt": "2026-10-16T18:00:00Z"
}
```

Erro padrão:

```json
{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [] } }
```

---

## 7. Onde plugar no app (MVVM)

Siga o fluxo de referência `home/`:

```text
View  →  ViewModel (ChangeNotifier)  →  Repository  →  ApiClient  →  dinna-api
```

Sugestão de pastas (criar quando for implementar):

```text
lib/
├── shared/models/
│   └── order.dart              # Order + OrderStatus (+ fromJson)
└── features/
    ├── orders/                 # cliente: acompanhamento (E6)
    │   ├── order_tracking_view.dart
    │   ├── order_tracking_view_model.dart
    │   └── order_repository.dart
    └── restaurant/             # restaurante: fila + avanço (E7)
        ├── order_queue_view.dart
        ├── order_queue_view_model.dart
        └── … (pode reusar o mesmo OrderRepository)
```

Dependências montadas em `main.dart` e passadas por construtor — sem service locator.

### Checklist por camada

- [ ] **Model** `OrderStatus` + `Order` com `fromJson` / `toJson` se precisar
- [ ] **Repository** `fetchOrders`, `fetchOrder(id)`, `updateStatus(id, next)`
- [ ] **ViewModel restaurante** estados `loading | ready | empty | updating | error` + `advanceStatus()`
- [ ] **ViewModel cliente** estados `loading | ready | refreshing | error | notFound`
- [ ] **View** só `ListenableBuilder` + widgets; zero HTTP
- [ ] **Testes** ViewModel (transições + erro) e Repository (`MockClient`)

---

## 8. Critérios de pronto (Definition of Done)

- [ ] Status na UI usa sempre os 4 labels em PT; API usa `received|preparing|ready|finished`
- [ ] Restaurante só oferece o **próximo** status válido
- [ ] Cliente vê a etapa atual destacada e as anteriores como feitas
- [ ] Loading não duplica toque no botão de avanço
- [ ] Erro de rede/API mostra mensagem + retry; status anterior não “pula” na UI
- [ ] `flutter analyze --fatal-infos` e `flutter test` verdes
- [ ] Print/vídeo no PR (fila avançando as 4 etapas + um caso de erro)

---

## 9. Ordem sugerida de implementação

1. Model `OrderStatus` / `Order` (+ testes de parse)
2. `OrderRepository` com `MockClient` (lista + patch de status)
3. ViewModel do restaurante (avanço + erros) → depois a View da fila/detalhe
4. ViewModel + View de acompanhamento do cliente (leitura do status)
5. Encaixe nas rotas quando SCRUM-23 estiver pronta (até lá, rota provisória ou navegação mínima)

---

## 10. Dúvidas para alinhar com o time (antes de codar demais)

1. `PATCH /orders/:id/status` recebe o **próximo** status no body ou um comando tipo `advance`?
2. Cliente tem `GET /orders/:id` ou só lista filtrada?
3. Acompanhamento do cliente será **pull-to-refresh**, botão manual ou polling? (R1: manual/refresh costuma bastar)
4. Pedidos `finished` saem da fila ou ficam numa aba “histórico”?

Anote as respostas aqui quando fecharem a SCRUM-24:

| Pergunta | Resposta |
|---|---|
| 1 | |
| 2 | |
| 3 | |
| 4 | |
