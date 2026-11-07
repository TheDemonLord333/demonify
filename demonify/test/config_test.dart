import 'package:demonify/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Produktive API-Basis ist vorbelegt', () {
    expect(AppConfig.defaultApiBase, 'https://demonify.thedemonlord333.me/api/v1/');
  });

  test('Serveradressen werden auf /api/v1/ normalisiert', () {
    expect(AppConfig.normalizeApiBase('demonify.thedemonlord333.me'), 'https://demonify.thedemonlord333.me/api/v1/');
    expect(AppConfig.normalizeApiBase('https://demonify.thedemonlord333.me/'), 'https://demonify.thedemonlord333.me/api/v1/');
    expect(AppConfig.normalizeApiBase('http://192.168.1.20:1340/api/v1'), 'http://192.168.1.20:1340/api/v1/');
    expect(AppConfig.originOf('http://192.168.1.20:1340/api/v1/'), 'http://192.168.1.20:1340');
  });
}
