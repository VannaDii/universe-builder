/// Local installation authority is separate from universe storage and exports.
library;

export 'src/installation_store.dart';
export 'src/ownership.dart'
    show
        OwnedFileLock,
        privateDirectory,
        privateTemporaryDirectory,
        protectedFile;
export 'src/installation_conversion.dart'
    show
        convertInstallation,
        InstallationConversionException,
        InstallationConversionFailure;
