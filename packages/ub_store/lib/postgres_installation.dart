/// PostgreSQL installation authority primitives for the service's owned
/// transaction. Connection lifecycle and credentials remain backend-owned.
library;

export 'src/postgres_authority.dart'
    show PostgresInstallationAuthority, PostgresCatalogEntry;
export 'src/postgres_installation_store.dart'
    show PostgresInstallationStore, PostgresInstallationSession;
