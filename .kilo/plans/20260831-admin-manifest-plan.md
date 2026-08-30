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
