import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

final class AccessProfile {
  const AccessProfile(this.id, this.author, this.revoked);
  final ProfileId id;
  final bool author, revoked;
  factory AccessProfile.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'profile_id', 'author', 'revoked'});
    return AccessProfile(
      ProfileId.parse(f.string('profile_id')),
      f.boolean('author'),
      f.boolean('revoked'),
    );
  }
  String get label =>
      '${author ? 'Approval owner' : 'Contributor'} ${id.value.substring(4, 12)}${revoked ? ' (revoked)' : ''}';
}

final class AccessDirectory {
  AccessDirectory({
    required Iterable<AccessProfile> profiles,
    required Iterable<GrantSpec> grants,
  }) : profiles = List.unmodifiable(profiles),
       grants = List.unmodifiable(grants);
  final List<AccessProfile> profiles;
  final List<GrantSpec> grants;
  factory AccessDirectory.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'profiles', 'grants'});
    return AccessDirectory(
      profiles: f.array('profiles').map(AccessProfile.fromWire),
      grants: f.array('grants').map(GrantSpec.fromWire),
    );
  }
  GrantSpec? grant(ProfileId profile, UniverseId universe) => grants
      .where((g) => g.profileId == profile && g.universeId == universe)
      .firstOrNull;
}

Future<AccessDirectory> readAccessDirectory(AppSession session) async =>
    AccessDirectory.fromWire(await session.call(const ProfilesEngineRequest()));
Future<void> saveAccessGrant(AppSession session, GrantSpec grant) async {
  final f = WireFields(await session.call(GrantEngineRequest(grant: grant)), {
    'granted',
  });
  if (!f.boolean('granted')) {
    throw const FormatException('Grant was not confirmed.');
  }
}

Future<void> withdrawAccessGrant(
  AppSession session,
  ProfileId profile,
  UniverseId universe,
) async {
  final f = WireFields(
    await session.call(
      WithdrawGrantEngineRequest(profileId: profile, universeId: universe),
    ),
    {'withdrawn'},
  );
  if (!f.boolean('withdrawn')) {
    throw const FormatException('Withdrawal was not confirmed.');
  }
}
