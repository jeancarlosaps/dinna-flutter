# Envio de pedido — handoff

Contrato para Gabriel, João e Jean trabalharem em paralelo. O `POST /orders` já está na camada de dados. `/cart` revisa as linhas recebidas. Ainda não há confirmação, persistência nem leitura da mesa.

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
| `CartLines` | `lib/features/client/cart/cart_lines.dart` | Entrada `read` e gravação condicional `replace`. |
| `ProcessCartLines` | o mesmo arquivo | Lista só do processo. João substitui esta classe. |
| `CartViewModel` | `lib/features/client/cart/cart_view_model.dart` | Quantidade, remoção e total estimado. Não envia o pedido. |

`AppRoutes.order` (`/order`) ainda cai em `RoutePlaceholder`. **Pendente:** a tela de confirmação.

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

A inclusão usa o mesmo `CartLines`. Lê a lista, acrescenta o item e grava com `replace`. Se `replace` devolver `false`, lê de novo e tenta outra vez. Não crie outra lista e não grave por cima de uma revisão que aconteceu no meio.

## João — SCRUM-69/70/71

Não há repositório de carrinho nem `sqflite` no projeto. **Pendente:** a persistência e o `lineId`. A revisão grava com `CartLines.replace`: a lista inteira só entra se `expected` ainda for a lista armazenada. A persistência entra no lugar de `ProcessCartLines`, em `main`, e implementa essa mesma regra. O `POST /orders` continua em `toOrderItem()`: `productId`, `quantity` e `note`. O JSON local de hoje ainda não guarda `lineId`; a linha persistida precisa guardar.

`CartItem` ainda não tem `lineId`. A troca de quantidade copia a linha em `CartViewModel._withQuantity` e hoje leva só `productId`, `quantity` e `note`. Quando o campo entrar, essa função precisa repassá-lo, e `==` / `hashCode` também. Sem a cópia, trocar a quantidade perde a identidade. Sem o `==`, `replace` não enxerga a troca de `lineId`. A tela não casa item por `productId` + `note`: a posição na lista é a identidade até o campo existir.

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

## Jean — SCRUM-40

`/cart` abre `CartView`. O `CartViewModel` nasce no `State`, observa com `ListenableBuilder` e morre no `dispose`. Não chama `OrderRepository` nem `submit`. Quem envia é a `CartView`, observando o `OrderSubmissionViewModel` da sessão. Sair da rota não descarta esse envio e não começa outro.

```dart
abstract interface class CartLines {
  List<CartItem> read();
  bool replace(List<CartItem> expected, List<CartItem> next);
}
```

`read` é a lista externa quando a tela abre. Cada aumento, diminuição ou remoção chama `replace` com a lista que a tela leu e a lista inteira nova, na mesma ordem. Se outra gravação ocorreu no meio, `replace` devolve `false` e a tela adota a lista externa. A alteração local dessa tentativa não fica. `ProcessCartLines` guarda a lista só no processo e não é a SCRUM-69. A lista morre com o app.

### Obrigações e testes

Gabriel, na inclusão:

```dart
final current = lines.read();
final stored = lines.replace(current, [...current, item]);
```

Se `stored` for `false`, repetir a partir de um `read` novo. Não gerar `lineId`.

João, na persistência:

- Implementar `replace` de modo que `false` não grave.
- Ao criar `lineId`, copiá-lo em `_withQuantity` e incluí-lo em `==` e `hashCode`.
- Não enviar `lineId` em `toOrderItem()`.
- Testar que mudar a quantidade conserva o `lineId`.
- Testar que `replace` devolve `false` quando a lista armazenada deixou de ser `expected`.
- Testar o round-trip do `lineId` no JSON local e a limpeza `withoutConfirmed` por esse id.

A revisão já cobre, sem `lineId`: quantidade e remoção pela posição, total estimado, estado vazio, e a recusa de gravar quando a lista mudou depois da leitura.

O total da tela é a soma `priceCents * quantity`, com o rótulo "Total estimado". Não é `order.totalCents` e não inclui taxa de serviço. Se o cardápio falhar ou faltar preço, o total estimado fica ausente e as linhas permanecem. Sem itens, a tela mostra o estado vazio e abre `AppRoutes.menu`.

## Confirmação — ainda pendente

`/order` segue em `RoutePlaceholder`. O envio continua no `OrderSubmissionViewModel`. A tela de confirmação, quando existir, nasce no `State`, observa com `ListenableBuilder` e usa o total do servidor. A `CartView` já chama o trecho abaixo. Não abre `/order` e não limpa as linhas. O ViewModel do envio fica na sessão do app: voltar e reabrir `/cart` mostra o mesmo estado, inclusive envio pendente e resultado incerto. Sem linhas, o aviso continua na tela e o botão de enviar sai.

```dart
final submission = OrderSubmissionViewModel(orderRepository);

await submission.submit(table: table, items: List<CartItem>.of(cart));
```

| Estado | O que mostrar |
| --- | --- |
| `isSubmitting` | Carregando. O botão de envio sai. `canRequestSubmit` fica falso e outro toque não chama `submit`. |
| `isDefiniteFailure` | `errorMessage`. "Tentar novamente" chama `submit` com a mesa e as linhas atuais. O carrinho fica. |
| `outcomeUncertain` | `errorMessage` e `OrderSubmissionViewModel.verifyBeforeRetryGuidance`. Não diga que o pedido falhou. Não mostre "Tentar novamente". Não limpe. Não dispare outro POST sozinho. "Reenviar o mesmo pedido" pede confirmação e repete a chave e o body já guardados. |
| `status == succeeded` | Aviso de pedido enviado. O botão de envio sai. As linhas ficam. `order` é o pedido da API; a confirmação, quando existir, usa `order.id`, `order.table`, `order.items`, `order.totalCents` e `order.createdAt`. |

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

## Idempotência — SCRUM-90

O `POST /orders` pode levar `Idempotency-Key`. A API guarda a chave por 24 horas. Sem o header, cada POST cria um pedido. O app gera um UUID v4 por intenção, grava a chave e o body e só então envia. A gravação é um JSON exclusivo dessa intenção (`order-intent.json`, via `path_provider`). Não é o banco da SCRUM-27.

O body guardado é o do primeiro envio: mesa, ordem dos itens, `productId`, `quantity` e `note`. `note` omitida e `note` vazia continuam diferentes. A lista é copiada no início de `submit`, antes da leitura do arquivo, e o mapa do chamador não altera o body já gravado. Uma edição do carrinho nesse intervalo fica de fora da chave. Um segundo toque não cria outra chave. "Enviar pedido" enquanto a leitura inicial ainda não terminou também não reenvia: a intenção achada espera o diálogo. Sair de `/cart` não apaga a intenção. Reiniciar o app lê o arquivo e não envia sozinho. Fase `succeeded` sem o pedido da API é arquivo inválido, não confirmação.

| Situação | O que acontece |
| --- | --- |
| Primeira tentativa | UUID novo, body congelado, grava, POST com o header |
| Timeout, queda, HTTP 5xx sem prova de ausência, crash depois da gravação | Resultado incerto. A mesma chave continua. O reenvio é manual |
| `201`, inclusive a repetição do mesmo body | Sucesso da intenção original. O carrinho fica. `/order` não abre |
| `400` e `404` | A API não ficou com a chave. "Tentar novamente" é uma intenção nova, com o carrinho daquele momento |
| `409 IDEMPOTENCY_KEY_CONFLICT`, `409` sem código depois de enviar a chave, `500 IDEMPOTENCY_STATE_INVALID` | Bloqueia reenvio e chave nova |
| Arquivo corrompido, leitura impossível, recuperação interrompida ou item fora do domínio (como `note` acima de 200 caracteres) | Não libera outro POST |
| Falha ao gravar e a leitura seguinte não acha intenção | Não envia. A tentativa pode ser refeita |
| Idade de 23 horas ou mais, ou instante no futuro | Não reenvia. A proteção da API acaba só às 24 horas |

A folga de 1 hora existe porque o relógio do aparelho pode estar adiantado. Expirar essa proteção, no app ou na API, não significa que o pedido deixou de existir. Relógio atrasado ainda pode fazer o app reenviar depois que o servidor já esqueceu a chave; esse risco fica registrado e não é coberto com uma chave nova automática.

`cartStore` **não existe**. A limpeza depois do sucesso fica na implementação de `CartLines` do João. A revisão não grava nesse momento. O `submit` da tela usa as linhas atuais do `CartViewModel` só quando não há intenção aberta; a intenção incerta repete o body já gravado. Quando `lineId` existir, não monte outra lista só com `productId`, `quantity` e `note`: a fotografia perderia a identidade e a limpeza voltaria a apagar uma linha recriada. A mesa chega em `CartView.table`. A navegação passa um `String` em `RouteSettings.arguments`; outro tipo não é mesa. Sem esse argumento, a tela envia mesa vazia e a validação responde "Informe a mesa". `openConfirmation` **não existe**: a rota é `AppRoutes.order` e o argumento ainda não foi definido. O pedido a exibir é o `Order` do ViewModel, sem novo `GET /orders`.
