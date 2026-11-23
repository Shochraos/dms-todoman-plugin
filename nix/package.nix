{
  lib,
  runCommand,
  runtimeShell,
  writeShellScript,
  todoman,
  backendPython,
}:
let
  manifest = lib.importJSON ../plugin.json;
  payload = [
    ../plugin.json
    ../UNLICENSE
    ../TodomanAgenda.qml
    ../TodomanCombo.qml
    ../TodomanController.qml
    ../TodomanDatePicker.qml
    ../TodomanField.qml
    ../TodomanRecurrenceEditor.qml
    ../TodomanSettings.qml
    ../TodomanTaskEditor.qml
    ../TodomanTaskRow.qml
    ../TodomanWidget.qml
    ../todoman_backend.py
  ];
  patchedTodoman = todoman.overridePythonAttrs (previousAttrs: {
    patches = (previousAttrs.patches or [ ]) ++ [ ./todoman-list-file-path.patch ];
  });
  launcher = writeShellScript "dank-todoman-backend" ''
    export PATH="${patchedTodoman}/bin''${PATH:+:$PATH}"
    export DANK_TODOMAN_LIST_FILE_PATHS=1
    unset TODOMAN_AUTO_PYTHON TODOMAN_WRAPPED_SCRIPT TODOMAN_WRAPPER_SCRIPT

    backend="$1"
    case "''${2:-}" in
      ""|python3) exec ${backendPython}/bin/python3 "$backend" ;;
      *) exec -- "$2" "$backend" ;;
    esac
  '';
in
runCommand "dank-todoman-${manifest.version}"
  {
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions payload;
    };
    meta = {
      inherit (manifest) description;
      license = lib.getLicenseFromSpdxId manifest.license;
    };
  }
  ''
    install -dm755 "$out"
    cd "$src"
    install -m644 ${lib.escapeShellArgs (map (file: baseNameOf file) payload)} "$out/"
    substituteInPlace "$out/TodomanController.qml" --replace-fail '"/bin/sh"' '"${runtimeShell}"'
    install -m755 ${launcher} "$out/run_backend.sh"
  ''
