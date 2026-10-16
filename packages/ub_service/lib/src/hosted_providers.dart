import 'package:ub_contracts/ub_contracts.dart';

/// Provider subjects are scoped by issuer, never matched by email or display name.
final class HostedIdentity {
  HostedIdentity({required this.issuer, required this.subject}) {
    if (issuer.isEmpty || subject.isEmpty) {
      throw const FormatException(
        'Hosted identity requires issuer and subject',
      );
    }
  }
  final String issuer;
  final String subject;
  @override
  bool operator ==(Object other) =>
      other is HostedIdentity &&
      issuer == other.issuer &&
      subject == other.subject;
  @override
  int get hashCode => Object.hash(issuer, subject);
}

final class HostedProviderUnavailable implements Exception {
  const HostedProviderUnavailable();
  @override
  String toString() => 'Hosted provider is not configured';
}

abstract interface class HostedSignInProvider {
  /// Verify a provider assertion before returning its stable identity.
  Future<HostedIdentity> authenticate(String assertion);
}

/// Deliberately performs no sign-in until a provider adapter is selected.
final class StubHostedSignInProvider implements HostedSignInProvider {
  const StubHostedSignInProvider();
  @override
  Future<HostedIdentity> authenticate(String assertion) async =>
      throw const HostedProviderUnavailable();
}

enum HostedSubscriptionStatus {
  notConfigured('not_configured'),
  none('none'),
  active('active'),
  inactive('inactive');

  const HostedSubscriptionStatus(this.wireName);
  final String wireName;
}

final class HostedBillingStatus {
  const HostedBillingStatus({required this.provider, required this.status});
  final String provider;
  final HostedSubscriptionStatus status;
}

abstract interface class HostedBillingProvider {
  /// A provider observation only; pricing and admission policy are separate.
  Future<HostedBillingStatus> status(String accountId);
}

/// No checkout, charge, paid entitlement or webhook verification is simulated.
final class StubHostedBillingProvider implements HostedBillingProvider {
  const StubHostedBillingProvider();
  @override
  Future<HostedBillingStatus> status(String accountId) async =>
      const HostedBillingStatus(
        provider: 'stub',
        status: HostedSubscriptionStatus.notConfigured,
      );
}

/// One hosted account maps only to profiles in its own installation. Provisioning
/// supplies these bindings; an assertion cannot select an account or profile.
final class HostedAccountAccess {
  HostedAccountAccess({
    required this.accountId,
    required Map<HostedIdentity, EngineHello> profiles,
    this.signIn = const StubHostedSignInProvider(),
    this.billing = const StubHostedBillingProvider(),
  }) : _profiles = Map.unmodifiable(profiles) {
    if (accountId.isEmpty) throw const FormatException('Account ID required');
  }
  final String accountId;
  final Map<HostedIdentity, EngineHello> _profiles;
  final HostedSignInProvider signIn;
  final HostedBillingProvider billing;

  Future<EngineHello> authenticate(String assertion) async {
    final identity = await signIn.authenticate(assertion);
    final hello = _profiles[identity];
    if (hello == null) throw const FormatException('Hosted access unavailable');
    // The engine must still authenticate this hello on sign-in and every call.
    return hello;
  }

  Future<HostedBillingStatus> billingStatus() => billing.status(accountId);
}
