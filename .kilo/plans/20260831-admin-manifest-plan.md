# План: встраивание admin-манифеста в I_trust_the_signer_of_this.exe

## Контекст

В `pinguin` права администратора запрашиваются через манифест Windows:
- `app.manifest` содержит `requestedExecutionLevel level="requireAdministrator"`.
- Манифест (вместе с иконкой/версией) компилируется `goversioninfo` в `.syso`, который кладётся рядом с main-пакетом и подхватывается `go build` автоматически (см. `/home/koka/src/pinguin/Makefile:95-98,120-121`).

Есть два места сборки:
1. Локально: `/home/koka/src/I_trust_the_signer_of_this/Makefile` (цель `trust`) — кросс-сборка `GOOS=windows`, подпись `osslsigncode`.
2. CI: `.github/workflows/build.yml` — чекаутит `abakum/crocson` в `crocson/`, собирает `go build ./cmd/I_trust_the_signer_of_this/` на `windows-latest`, подписывает `signtool`, публикует release. Workflow НЕ использует Makefile, поэтому обновить нужно оба места.

Манифест встраивается на этапе сборки (до подписи) в обоих местах.

## Изменения

1. **Создать `app.manifest`** в `/home/koka/src/I_trust_the_signer_of_this/` — копия `pinguin/app.manifest` с `name="I_trust_the_signer_of_this"` и `level="requireAdministrator"`.

2. **Добавить go tool в модуль crocson**: в `/home/koka/src/crocson` выполнить
   `go get -tool github.com/josephspurrier/goversioninfo/cmd/goversioninfo`
   (аналог строки `tool ...` в `pinguin/go.mod:30`).

3. **Обновить Makefile** (`/home/koka/src/I_trust_the_signer_of_this/Makefile`):
   - Добавить переменные: `MAIN_PKG=../crocson/cmd/I_trust_the_signer_of_this/`, `SYSO=$(MAIN_PKG)resource_windows_amd64.syso`, `MANIFEST=app.manifest`, минимальный `versioninfo.json` (только `"ManifestPath": "app.manifest"`, без иконки/версии).
   - В цели `trust` перед сборкой:
     - сгенерировать JSON с `"ManifestPath": "$(MANIFEST)"` (в /tmp, чтобы не мусорить в репо),
     - `cd ../crocson && go tool github.com/josephspurrier/goversioninfo/cmd/goversioninfo -o $(SYSO) <json>`,
     - после `go build` удалить `$(SYSO)`.
   - Порядок в `trust`: syso → go build → rm syso → osslsigncode (подпись уже после, манифест сохраняется).
   - Обновить `.PHONY`/help при необходимости.

4. **Обновить `.github/workflows/build.yml`** — в шаге «Build I_trust_the_signer_of_this.exe» перед `go build`:
   - записать минимальный `versioninfo.json` (только `"ManifestPath"`) во временный файл, `"ManifestPath"` — абсолютный путь к `${{ github.workspace }}\app.manifest` (app.manifest уже в корне этого репо после чекаута);
   - `cd crocson && go tool github.com/josephspurrier/goversioninfo/cmd/goversioninfo -o cmd/I_trust_the_signer_of_this/resource_windows_amd64.syso <json>` (работает благодаря пункту 2; модуль crocson в CI чекаутится fresh, tool-директива подтянется);
   - после `go build` удалить `.syso`.
   - Проверить, что setup-go кэширует модульный кэш — tool скачается автоматически.

## Риски / примечания

- `.syso` кладётся именно в каталог main-пакета (`cmd/I_trust_the_signer_of_this/`) — иначе `go build` его не подхватит.
- `resource_windows_amd64.syso` добавить в `/home/koka/src/crocson/.gitignore`, чтобы не попал в коммит.
- Подпись не влияет на манифест; UAC-запрос работает как у pinguin.

## Проверка

- `make trust` собирает и подписывает без ошибок.
- CI-запуск workflow (workflow_dispatch, snapshot) проходит; в артифакте exe.
- На Windows запуск exe вызывает UAC-запрос (проверка пользователем) в обоих вариантах сборки.
- Опционально: `osslsigncode verify` / `signtool verify`, или просмотр манифеста в exe.

## Итог внедрения (2026-08-31)

### Сделано

- `app.manifest` создан (requireAdministrator, name=`I_trust_the_signer_of_this`).
- `crocson/go.mod` — добавлена tool-директива goversioninfo v1.7.0 (только в локальной копии!).
- `Makefile` переписан: цель `trust` генерирует syso с манифестом (JSON только с `ManifestPath`), сборка выполняется из каталога crocson (корень этого репо — не Go-модуль), после сборки syso удаляется, затем подпись `osslsigncode`.
- `.github/workflows/build.yml`:
  - Build-шаг генерирует тот же syso перед `go build`, удаляет после.
  - Sign-шаг переписан: PFX импортируется через `Import-PfxCertificate` в `Cert:\CurrentUser\My`, подпись по `/sha1 <Thumbprint>`, после подписи PFX и сертификат удаляются. Пустой пароль обрабатывается через `[System.Security.SecureString]::new()`.
- `crocson/.gitignore` — добавлен `cmd/I_trust_the_signer_of_this/*.syso`.

### История CI-запусков и фиксов

1. **Run #1** — падение Build: `go: no such tool "goversioninfo"`. Причина: в CI чекаутится `abakum/crocson` с GitHub без tool-директивы (добавлялась только локально). Фикс: в workflow заменено на `go run github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.7.0` — не зависит от go.mod crocson.
2. **Run #2** — Build прошёл; падение Sign: `SignTool Error: Store::ImportCertObject() failed`. Фикс: предварительный `Import-PfxCertificate` + подпись по thumbprint вместо `/f pfx /p`.
3. **Run #3** — падение Sign: `ConvertTo-SecureString: Cannot bind argument to parameter 'String' because it is an empty string` — секрет `P12_PASSWORD` пуст. Фикс: пустой пароль → пустой SecureString.
4. **Run #4** — падение Sign: `Import-PfxCertificate: The data is invalid (0x8007000D)` — импорт с пустым паролем не удался. Вывод: PFX **имеет пароль**, а секрет `P12_PASSWORD` в репозитории не задан/пуст.

### Статус и остаток

- Build с admin-манифестом в CI работает (успешно в runs #2–#4).
- **Заблокировано на пользователе**: задать секрет `P12_PASSWORD` (Settings → Secrets and variables → Actions), либо перегнать `croc.p12` в P12 без пароля и обновить `P12_BASE64`. Код workflow менять не нужно.
- Финальная проверка UAC-запроса — вручную на Windows после успешного release.
