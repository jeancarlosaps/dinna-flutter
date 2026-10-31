# Envio de pedido — handoff

Contrato para Gabriel, João e Jean trabalharem em paralelo. O `POST /orders` já está na camada de dados. Não há tela de carrinho, confirmação, persistência nem leitura da mesa.

O app monta um único `HttpOrderRepository` em `lib/main.dart` e o entrega ao `AppRouter.orderRepository`. Ninguém cria outro cliente HTTP para pedido.

## O que já existe

| Peça | Onde | Uso |
| --- | --- | --- |
| `CartItem` | `lib/core/domain/cart_item.dart` | Linha local: `productId`, `quantity` ≥ 1, `note` opcional (máx. 200). Sem nome, preço ou imagem. |
| `CartItem.toOrderItem()` | o mesmo arquivo | Vira o item do `POST /orders`. O repositório já chama isso. |
| `CartItem.toJson` / `fromJson` | o mesmo arquivo | JSON local. `note` nula é omitida. |
| `Product` e `ProductRepository` | `lib/core/domain/product.dart`, `lib/features/menu/product_repository.dart` | Cardápio. `available == false` ainda é produto encontrado. Id ausente é `DataFailure.notFound`. |
| `ProductDetailViewModel` | `lib/features/menu/product_detail_view_model.dart` | `GET /products/:id`. Não monta carrinho. |
| `OrderRepository.create` | `lib/features/restaurant/order_repository.dart` | `POST /orders`. Devolve `OrderSubmission`. |
| `OrderSubmissionViewModel` | `lib/features/client/order/order_submission_view_model.dart` | Estado do envio. Não guarda o carrinho. |
| `Order` | `lib/core/domain/order.dart` | Resposta da API, com `totalCents` calculado no servidor. |

`AppRoutes.cart` (`/cart`) e `AppRoutes.order` (`/order`) ainda caem em `RoutePlaceholder`. **Pendente:** a tela de cada rota.

## Regras comuns

- O envio recebe uma fotografia. `submit` copia a mesa e os `CartItem` antes da rede.
- `shouldClearCart` só é verdadeiro com pedido confirmado (`status == succeeded` e `order` preenchido).
- Falha confirmada (`isDefiniteFailure`) e resultado incerto (`outcomeUncertain`) não limpam nada.
- `outcomeUncertain` não é falha definitiva. A frase é `OrderSubmission.uncertainOutcomeMessage`: o pedido pode ter sido registrado. Não há retry automático.
- Enquanto `isSubmitting` é verdadeiro, outro `submit` é ignorado.
- A limpeza tira só `confirmedItems`. Linha nova, quantidade maior, observação trocada ou linha recriada depois do `submit` permanece.
- O total confirmado é `order.totalCents`. O body não leva total.

A identidade da linha é um `lineId` local, criado quando a linha entra no carrinho. Ele não vai no `POST /orders`. `productId` + `note` não identifica a linha: o usuário pode apagar a original e adicionar outra igual enquanto o envio está em andamento.

`CartItem` ainda não tem `lineId`. João acrescenta o campo na linha persistida e na lista que entra em `submit`. A fotografia guarda esse id. A limpeza só mexe na linha que ainda tem o mesmo `lineId`.

- Mesma linha e mesma observação: subtrai a quantidade enviada. Abaixo de 1, a linha sai. Quantidade aumentada durante o POST deixa a diferença.
- Mesma linha com observação trocada: a linha fica como o usuário deixou.
- `lineId` ausente no carrinho atual: não faz nada. Não aplica a quantidade numa linha nova com o mesmo produto e a mesma observação.

```dart
List<CartItem> withoutConfirmed(List<CartItem> cart, List<CartItem> confirmed) {
  final next = [...cart];
  for (final sent in confirmed) {
    final index = next.indexWhere((item) => item.lineId == sent.lineId);
    if (index < 0) continue;
    final current = next[index];
    if (current.note != sent.note) continue;
    final remaining = current.quantity - sent.quantity;
    if (remaining < 1) {
      next.removeAt(index);
      continue;
    }
    next[index] = CartItem(
      lineId: current.lineId,
      productId: current.productId,
      quantity: remaining,
      note: current.note,
    );
  }
  return next;
}
```

O construtor com `lineId` ainda não existe. É a forma da linha persistida, não a de `CartItem` hoje.

Exemplo: o envio levou a linha `a` (produto `p1`, observação `sem cebola`, 2 unidades). Durante o POST essa linha sai e entra a linha `b`, com o mesmo produto, a mesma observação e 1 unidade. `confirmedItems` só tem `a`. `b` permanece com 1 unidade.

Essa função não está no app. João a implementa na persistência, junto com o `lineId`. Jean não reconcilia por produto e observação: no sucesso, entrega `confirmedItems` para essa limpeza.

## Gabriel — SCRUM-29/36/37/39

A mesa e os itens ainda não saem da UI.

**Pendente na mesa.** `TableView` desenha o campo e não lê o texto. Não existe ViewModel de mesa. A mesa do pedido é um `String`, o mesmo formato de `Order.table` (`"12"`). Quem ficar com o valor é a navegação até o carrinho, não o `OrderSubmissionViewModel`.

**Pendente no detalhe.** `ProductDetailViewModel.load` preenche `product`. Não existe método de adicionar ao carrinho. A UI monta o `CartItem` e entrega a lista a quem persistir (João). Não copie nome, preço nem imagem para o item.

```dart
final product = detailViewModel.product;
if (product == null || !product.available) return;

final item = CartItem(productId: product.id, quantity: quantity, note: note);
```

`quantity` e `note` são estado da tela. **Pendente:** esses campos ainda não existem no detalhe.

A UI continua responsável por ler a mesa, escolher quantidade e observação, navegar (`AppRoutes.menu`, `AppRoutes.product`, `AppRoutes.cart`) e não chamar HTTP. Reutilize `CartItem`, `Product`, `ProductRepository` e `ProductDetailViewModel`. Não crie outro model de item, não escolha `lineId` e não crie outro envio. João gera o id ao persistir a inclusão.

## João — SCRUM-69/70/71

Não há repositório de carrinho nem `sqflite` no projeto. **Pendente:** a persistência e o `lineId`. O `POST /orders` continua em `toOrderItem()`: `productId`, `quantity` e `note`. O JSON local de hoje ainda não guarda `lineId`; a linha persistida precisa guardar.

**Pendente na limpeza.** Gerar um `lineId` novo em cada inclusão, mesmo que produto e observação repitam uma linha apagada. Não reutilizar o id. Implementar `withoutConfirmed` pelo `lineId`, com a regra de observação e quantidade acima. Não casar por `productId` + `note`. Em falha confirmada ou resultado incerto, não rodar essa limpeza.

O round-trip abaixo é o de hoje, sem `lineId`. A persistência não pode parar nele: `fromJson` ignora campo que o model ainda não lê.

```dart
final stored = [for (final item in cart) item.toJson()];
final restored = [for (final json in stored) CartItem.fromJson(json)];
```

Revalidar com o `ProductRepository` que o `main` já cria. Não existe método `revalidate`.

```dart
final detail = await productRepository.findById(item.productId);
final product = detail.product;
final unavailable = product == null || !product.available;
```

`product == null` com `detail.failure == DataFailure.notFound` é produto ausente. `available == false` é produto encontrado e indisponível. Os dois bloqueiam o envio dessa linha. Falha de rede (`DataFailure.unavailable`) não apaga a linha: o cardápio é que não respondeu.

Em falha confirmada ou `outcomeUncertain`, grave o carrinho como estava, inclusive alterações feitas depois que o `submit` começou. Só troque a lista persistida no sucesso:

```dart
if (submission.shouldClearCart) {
  final confirmed = submission.confirmedItems;
  if (confirmed != null) {
    await save(withoutConfirmed(currentCart(), confirmed));
  }
}
```

`confirmedItems` é a fotografia, não o carrinho atual. Não substitua a lista inteira por vazia. Não crie um segundo `OrderSubmissionViewModel` para guardar item.

## Jean — SCRUM-40/44

**Pendente:** `/cart` e `/order` seguem em `RoutePlaceholder`. O ViewModel nasce no `State` da tela, com o `OrderRepository` do router, e morre no `dispose`. A tela observa com `ListenableBuilder`.

```dart
final submission = OrderSubmissionViewModel(orderRepository);

await submission.submit(table: table, items: List<CartItem>.of(cart));
```

| Estado | O que mostrar |
| --- | --- |
| `isSubmitting` | Carregando. O botão não chama `submit` de novo. |
| `isDefiniteFailure` | `errorMessage`. Pode tentar de novo com um toque explícito. O carrinho fica. |
| `outcomeUncertain` | `errorMessage`. Não diga que o pedido falhou. Não limpe. Não dispare outro POST sozinho. |
| `status == succeeded` | `order` é o pedido da API. A confirmação usa `order.id`, `order.table`, `order.items`, `order.totalCents` e `order.createdAt`. |

```dart
if (submission.outcomeUncertain) {
  showMessage(submission.errorMessage);
  return;
}
if (submission.shouldClearCart) {
  final confirmed = submission.confirmedItems!;
  await cartStore.save(withoutConfirmed(await cartStore.load(), confirmed));
  openConfirmation(submission.order!);
}
```

`cartStore` **não existe**. Jean chama a API de persistência do João; não grava o carrinho de novo na tela. O `submit` recebe as linhas persistidas, com o `lineId`. Não monte outra lista só com `productId`, `quantity` e `note`: a fotografia perderia a identidade e a limpeza voltaria a apagar uma linha recriada. `openConfirmation` **não existe**: a rota é `AppRoutes.order` e o argumento ainda não foi definido. O pedido a exibir é o `Order` do ViewModel, sem novo `GET /orders`.
