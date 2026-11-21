// Display helpers only. The native backend remains the authority for every ID,
// password, click-approval, window-open policy and access permission.
String keyplusKnownServiceState(Object? value) => const {
      'portable',
      'compatible',
      'mismatch',
      'stopped',
      'unknown'
    }.contains(value)
        ? value as String
        : 'unknown';

String? keyplusIdError(String requested, String local) {
  if (requested.trim().isEmpty)
    return 'Bağlanmak istediğiniz bilgisayarın kimliğini yazın.';
  final mine = local.replaceAll(' ', '');
  if (mine.isNotEmpty && mine != '-' && requested.replaceAll(' ', '') == mine) {
    return 'Bu bilgisayarın kimliğini girdiniz. Karşı cihazın kimliğini yazın.';
  }
  return null;
}

String keyplusApprovalText(String mode, String verification) {
  if (mode == 'click')
    return 'Her bağlantı isteği için bu bilgisayardan izin vermeniz gerekir.';
  final password = verification == 'use-permanent-password'
      ? 'kalıcı parolanızla'
      : verification == 'use-temporary-password'
          ? 'tek kullanımlık parolayla'
          : 'tek kullanımlık veya kalıcı parolanızla';
  if (mode == 'password-click' || mode.isEmpty)
    return 'Bağlanacak kişi $password veya bu bilgisayardan vereceğiniz onayla erişebilir.';
  if (mode == 'password')
    return 'Bağlanacak kişi $password erişebilir. Diğer erişim kısıtlamalarınız geçerlidir.';
  return 'Geçerli erişim yöntemini Parola ve erişim izinleri bölümünden kontrol edin.';
}
