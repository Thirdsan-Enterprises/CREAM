import '../api/api_client.dart';
import 'token_storage.dart';
import 'user.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  Future<User> login({required String phone, required String password}) async {
    final data = await _api.post(
      '/auth/login',
      data: {'phone': phone, 'password': password},
    );

    await _tokenStorage.write(data['token'] as String);

    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<User> me() async {
    final data = await _api.get('/auth/me');
    return User.fromJson(data);
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await _tokenStorage.clear();
    }
  }

  Future<bool> hasStoredSession() async => (await _tokenStorage.read()) != null;
}
