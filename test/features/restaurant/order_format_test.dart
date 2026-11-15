import 'package:dinna/features/restaurant/order_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formata o número público sem cortar valores maiores', () {
    expect(formatPublicOrderNumber(1), '#0001');
    expect(formatPublicOrderNumber(5), '#0005');
    expect(formatPublicOrderNumber(9999), '#9999');
    expect(formatPublicOrderNumber(10000), '#10000');
    expect(publicOrderLabel(1), 'Pedido #0001');
    expect(publicOrderLabel(5), 'Pedido #0005');
    expect(publicOrderLabel(9999), 'Pedido #9999');
    expect(publicOrderLabel(10000), 'Pedido #10000');
    expect(publicOrderLabel(null), 'Pedido confirmado');
    expect(publicOrderLabel(null), isNot(contains('#')));
    expect(() => formatPublicOrderNumber(0), throwsArgumentError);
  });
}
