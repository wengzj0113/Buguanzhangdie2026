# Project instructions

## MQL development and builds

- When an implementation changes either canonical strategy source (`NoMatterRiseFall_MT4.mq4` or `NoMatterRiseFall_MT5.mq5`), run the relevant automated tests, then compile both canonical sources with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both` before reporting completion. If only one platform source is affected, compiling both still checks that the shared behavior remains buildable.
- The build script discovers MT4 and MT5 MetaEditor installations automatically. It writes `.ex4` and `.ex5` beside their `.mq4` and `.mq5` source files, and stores compiler logs in the user's temporary `CodexMetaEditorLogs` directory.
- Treat a build as successful only when MetaEditor reports zero errors and the expected compiled output exists and was refreshed. Report warnings and the output paths.
- If automatic discovery fails, use `-MetaEditor4Path` / `-MetaEditor5Path` or set `METAEDITOR_MT4_PATH` / `METAEDITOR_MT5_PATH`; do not silently skip compilation.
- The compiler creates MQL bytecode files (`.ex4` / `.ex5`), not Windows `.exe` applications.
