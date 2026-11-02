# Envio de pedido — handoff

Contrato para Gabriel, João e Jean trabalharem em paralelo. O `POST /orders` já está na camada de dados. `/cart` revisa as linhas recebidas e, quando o sucesso fica gravado, abre `/order`. Ainda não há leitura da mesa.

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

`AppRoutes.order` (`/order`) mostra o `Order` gravado. O argumento é `OrderConfirmationArgs`. `/order/tracking` só identifica o pedido e não atualiza o status.

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

## Confirmação

O envio continua no `OrderSubmissionViewModel`. A confirmação não tem ViewModel: o `Order` é imutável e a tela não envia, não retoma e não lê o carrinho. Ela recebe `OrderConfirmationArgs` em `/order`. Não há outro `POST /orders` nem `GET /orders`. O total é `order.totalCents`.

`OrderItem` não traz nome nem preço. A confirmação mostra `productId`, quantidade e `note`. Não consulta `ProductRepository`, para o cardápio atual não reescrever o pedido já aceito.

A `CartView` observa o envio da sessão. Abre `/order` uma vez por intenção, no frame seguinte ao 201, só quando `canBeginAnotherOrder` é verdadeiro — o sucesso já está no arquivo. Notificação repetida, reconstrução e o 201 da mesma chave não empilham outra rota. Voltar é `pop`: a tela de envio continua atrás e não cria outra intenção. "Ver confirmação" abre de novo o mesmo `Order` sem POST. "Fazer outro pedido" continua sendo o único jeito de apagar a intenção gravada.

Resultado incerto, bloqueio e 201 cuja gravação falhou não abrem `/order` e não mostram o aviso de pedido enviado. Sem linhas, o aviso que restar continua na tela e o botão de enviar sai. O ViewModel do envio fica na sessão: sair e reabrir `/cart` mostra o mesmo estado. Se a intenção gravada for `succeeded`, essa reabertura mostra a confirmação de novo e não envia.

```dart
final submission = OrderSubmissionViewModel(orderRepository);

await submission.submit(table: table, items: List<CartItem>.of(cart));
```

| Estado | O que mostrar |
| --- | --- |
| `isSubmitting` | Carregando. O botão de envio sai. `canRequestSubmit` fica falso e outro toque não chama `submit`. |
| `isDefiniteFailure` | `errorMessage`. "Tentar novamente" chama `submit` com a mesa e as linhas atuais. O carrinho fica. |
| `outcomeUncertain` | `errorMessage` e `OrderSubmissionViewModel.verifyBeforeRetryGuidance`. Não diga que o pedido falhou. Não mostre "Tentar novamente". Não limpe. Não dispare outro POST sozinho. "Reenviar o mesmo pedido" abre o diálogo com o ID da intenção daquele momento. Confirmar chama `resume` com esse ID. Só há POST se ele ainda for a intenção persistida. |
| `status == succeeded` e o arquivo tem o pedido | Aviso de pedido enviado e `/order` com `order.id`, `order.table`, `order.items`, `order.totalCents` e `order.createdAt`. As linhas ficam. O botão de envio sai. |

```dart
if (submission.outcomeUncertain) {
  showMessage(submission.errorMessage);
  return;
}
if (submission.shouldClearCart) {
  final confirmed = submission.confirmedItems!;
  await cartStore.save(withoutConfirmed(await cartStore.load(), confirmed));
}
```

A `CartView` já abre `/order` nesse sucesso. O trecho acima é só a limpeza futura do carrinho. Não dispare outro POST para mostrar a confirmação.

## Idempotência — SCRUM-90

O `POST /orders` aceita o header opcional `Idempotency-Key`. Sem ele, cada POST cria um pedido. Com ele, a chave é um UUID e a API a retém enquanto a linha existir em `idempotency_keys`. Não há prazo, segunda tabela, consulta por intenção nem token. A mesma chave e o mesmo payload respondem **201** com o snapshot original da criação, mesmo depois de mudança de catálogo, preço ou status. A mesma chave com outro payload responde **409** `IDEMPOTENCY_KEY_CONFLICT`. Pedido, itens e chave são gravados juntos. Uma resposta HTTP perdida não significa que o pedido falhou. Estado inconsistente responde **500** `IDEMPOTENCY_STATE_INVALID`.

O header de resposta `Idempotency-Retention: permanent` anuncia essa política. Não prova que uma operação específica foi persistida e o app não o usa para encurtar nem desligar a proteção local.

A garantia acaba se a linha da chave for apagada, se o banco for substituído ou se o servidor voltar a uma versão que remove chaves. Chave apagada por essa versão antiga não é reconstruída. Perder o UUID neste aparelho também fica fora da garantia: o app não tem como recuperar a intenção.

O app gera um UUID v4 por intenção, grava a chave e o body e só então envia. A gravação é um JSON exclusivo dessa intenção (`order-intent.json`, via `path_provider`). Não é o banco da SCRUM-27. Há um único `OrderSubmissionViewModel` na sessão. A tela não cria outro.

O body guardado é o do primeiro envio: mesa, ordem dos itens, `productId`, `quantity` e `note`. `note` omitida e `note` vazia continuam diferentes. A lista é copiada no início de `submit`, antes da leitura do arquivo, e o mapa do chamador não altera o body já gravado. Uma edição do carrinho nesse intervalo fica de fora da chave. Um segundo toque não cria outra chave. `submit` e `resume` concorrentes também não: o segundo encontra o envio em andamento e não abre outra intenção. "Enviar pedido" enquanto a leitura inicial ainda não terminou também não reenvia: a intenção achada espera o diálogo. Sair de `/cart` não apaga a intenção. Reiniciar o app lê o arquivo e não envia sozinho. Fase `succeeded` sem o pedido da API é arquivo inválido, não confirmação. Falha de leitura ou arquivo corrompido não é ausência da intenção.

O reenvio é manual. O diálogo mostra o ID da intenção daquele momento e `resume` só envia se ele ainda for a intenção persistida, pendente ou incerta, dentro da folga local.

| Situação | O que acontece |
| --- | --- |
| Primeira tentativa | UUID novo, body congelado, grava, POST com o header |
| Timeout antes dos headers, queda de conexão, corpo ilegível que não seja 409 ou 500 com chave, `502`, `503`, `500 INTERNAL_ERROR` e outro 4xx/5xx não reconhecido como falha sem efeito | Resultado incerto. A mesma chave e o mesmo body continuam. O reenvio é manual. O contrato da API não emite `502` nem `503` |
| `201`, inclusive a repetição do mesmo body | Sucesso da intenção original. O carrinho fica. `/order` abre uma vez com o pedido gravado. A repetição não abre outra rota e não cria outra chave. "Fazer outro pedido" apaga essa intenção só depois que o sucesso ficou gravado e só então libera um envio novo, com o carrinho daquele momento. Se a limpeza falha, a confirmação permanece e outro POST não sai |
| `201` ou bloqueio cuja gravação falha | Nesta execução a confirmação ou a causa do bloqueio permanece. Não há reenvio nem chave nova. O arquivo pode continuar `pending` ou `uncertain`. Reiniciar não recupera esse desfecho: a próxima abertura trata o arquivo como incerto e o reenvio manual, se houver, repete a mesma chave e o mesmo body |
| Reinício com intenção pendente ou incerta | Mostra o resultado incerto e não envia. O POST seguinte espera o diálogo |
| Reinício com sucesso gravado | Mostra a confirmação e não envia. O pedido seguinte espera "Fazer outro pedido" |
| `400 VALIDATION_ERROR` e `404 PRODUCT_NOT_FOUND` | A API recusou antes de gravar a chave. "Tentar novamente" é uma intenção nova, com o carrinho daquele momento. O carrinho não é limpo |
| `404 NOT_FOUND` | Não é falha sem efeito. Pode ser rota, proxy ou contrato incompatível. A chave fica e o reenvio é manual |
| `409 IDEMPOTENCY_KEY_CONFLICT`, `409` sem código depois de enviar a chave, `500 IDEMPOTENCY_STATE_INVALID` | Bloqueia reenvio e chave nova. Não há POST automático |
| `409` com outro código, depois de enviar a chave | Resultado incerto. A mesma chave continua para reenvio manual. Não nasce outro UUID |
| `500` com chave enviada e sem `error.code` utilizável (corpo vazio, JSON inválido ou leitura interrompida) | Bloqueia reenvio e chave nova. A intenção e os bytes ficam. O app não inventa o código e não afirma que o pedido existe ou que a chave está órfã: os dois são possíveis, porque `INTERNAL_ERROR` e `IDEMPOTENCY_STATE_INVALID` compartilham o HTTP 500. A tela mostra "Confira o pedido" e omite "Tentar novamente", "Reenviar o mesmo pedido" e "Fazer outro pedido". A recuperação neste aparelho só volta se o arquivo da intenção for removido fora do app. Um `500` transitório cujo corpo se perdeu fica preso do mesmo jeito |
| Arquivo corrompido, leitura impossível, diretório inacessível, recuperação interrompida ou item fora do domínio (como `note` acima de 200 caracteres) | Não libera outro POST. Ausência só vale quando o diretório pai pôde ser listado e o nome não estava lá |
| Falha ao preparar o diretório no arranque | O app abre. O envio fica bloqueado. Não há store em memória no lugar do arquivo |
| Falha ao gravar e a leitura seguinte não acha intenção | Não envia. A tentativa pode ser refeita |
| Falha ao gravar sucesso ou bloqueio | Nesta execução não nasce outro UUID |
| Idade de 23 horas ou mais, ou instante no futuro | Não reenvia, mesmo se o diálogo de confirmação já estava aberto |

A folga local continua nesta entrega. Ela é `24 horas` menos `1 hora`. O motivo é conservador: podem existir intenções criadas antes da retenção permanente, uma chave eliminada pelo servidor antigo não volta, uma resposta perdida não diz qual versão atendeu o POST, e o relógio do aparelho pode estar adiantado. Isso não é garantia absoluta contra relógio incorreto. Relógio atrasado ainda pode autorizar um reenvio quando o aparelho acredita estar dentro das 23 horas. Não há migração de intenção baseada só nesse relógio, e o header `Idempotency-Retention` não autoriza desligar a folga. Expirar a proteção não significa que o pedido deixou de existir.

`cartStore` **não existe**. A limpeza depois do sucesso fica na implementação de `CartLines` do João, quando `lineId` existir. A revisão não grava nesse momento e a confirmação também não limpa o carrinho. Falha confirmada, conflito, bloqueio e resultado incerto não limpam o carrinho. O `submit` da tela usa as linhas atuais do `CartViewModel` só quando não há intenção aberta; a intenção incerta repete o body já gravado. Quando `lineId` existir, não monte outra lista só com `productId`, `quantity` e `note`: a fotografia perderia a identidade e a limpeza voltaria a apagar uma linha recriada. A mesa chega em `CartView.table`. A navegação passa um `String` em `RouteSettings.arguments`; outro tipo não é mesa. Sem esse argumento, a tela envia mesa vazia e a validação responde "Informe a mesa".

`/order` recebe `OrderConfirmationArgs`. O `Order` é o da intenção `succeeded`, o mesmo do ViewModel, sem novo `GET /orders`. "Acompanhar pedido" abre `/order/tracking` com `AppRouteId` desse pedido. Essa rota não faz polling, não chama endpoint e não acompanha status: a SCRUM-46 continua pendente. Mesa, cardápio e a persistência do carrinho também continuam pendentes, nas stories do Gabriel e do João. Sem o argumento esperado, as duas rotas explicam a ausência e não chamam a API.
