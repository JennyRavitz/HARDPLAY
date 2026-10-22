# Проверка локальной сборки

Проверено 19 октября 2026 на этом Mac (Apple Silicon, macOS 27.0.1).

- Release-сборка создана: `build/HARDPLAY.app`, около 708 КБ, без внешних библиотек.
- Проверка Info.plist и `codesign --verify --deep --strict` прошла.
- `--self-test`: название и расширение трека, кодирование и восстановление очереди, форматирование времени — passed.
- `--audio-probe`: WAV и AIFF по 4 секунды — чтение длительности, воспроизведение с нулевой громкостью, перемотка, пауза — passed.
- Через интерфейс macOS: основное окно открылось; мини-плеер открылся; файл добавлен через диалог; длительность 0:04 показана; Play сменился на Pause, позиция воспроизведения увеличилась; тестовый файл затем удалён из очереди.

Ручная проверка звука на реальной музыке, остальных форматов, медиаклавиш, глобального сочетания, перетаскивания и поведения поверх полноэкранных приложений ещё не проведена. Регистрация медиакоманд и горячей клавиши реализована. Доступность форматов определяется системными кодеками; универсальный сторонний декодер не включён.

В ограниченном окружении `open` сообщил ошибку LaunchServices; запуск через интерфейс macOS успешно открыл приложение. Сборка отключает отладочные символы, поскольку системный dsymutil недоступен в этом окружении.

## Версия 0.2.0

Проверка `--playback-test` на двух четырёхсекундных файлах проходит с отдельным временным доменом настроек и нулевой громкостью:

- остановка за секунду до конца, без перехода к следующему файлу;
- продолжение с позиции конкретного трека после переключения;
- явный старт с нуля;
- остановка в самом конце;
- обычный переход очереди при отключённой остановке;
- восстановление позиций и режимов новым экземпляром Player на паузе.

Исправлена ошибка инициализации: сохранение настроек запрещено до завершения их чтения. При разрешении закладок сопоставляются пути `/tmp` и `/private/tmp`. Проверена ad-hoc подпись новой сборки. В интерфейсе видны кнопки «С начала», «Продолжить», меню конца трека и восстановленные три файла с позицией 1:38.

При обновлении произошла потеря сохранённого списка из-за этой ошибки. Восстановлены три WAV-файла из папки на Desktop и известная позиция выбранного трека. Полное совпадение с предыдущим списком не подтверждено. При последней проверке пользователь уже включил воспроизведение; дальнейшие действия в интерфейсе прекращены.

## Версия 0.3.0 — формы кнопок

Все элементы управления получили явные контуры и увеличенные зоны нажатия. Центральная кнопка круглая (64/72 pt); предыдущий/следующий трек — прямоугольники с закруглением; переключатели режима — компактные овальные кнопки с индикацией состояния. «С начала» — широкая капсула, «Продолжить» — отдельная прямоугольная кнопка с зелёным контуром; обе высотой 42 pt и с подписями. Оформлены меню, добавление файлов, кнопки окон и удаление из очереди. Добавлены русские accessibility labels для транспорта и удаления конкретного трека.

Release-сборка, self-test и проверка подписи прошли. Основное окно проверено визуально на Mac: три трека и позиция сохранились после перезапуска, подписи кнопок не обрезаются, очередь видна. При дальнейшей проверке пользователь взаимодействовал с приложением; дополнительных действий с его музыкой не выполнялось. Новые стили общие для основного окна, меню-панели и мини-плеера; отдельная визуальная проверка мини-плеера в этой итерации не завершена.

## Версия 0.4.0 — индивидуальный crossfade и прозрачный интерфейс

Для каждого исходящего трека сохраняется независимый режим: none / short (2 с) / long (6 с). Переход заранее подготавливает второй AVPlayer, затем одновременно воспроизводит оба потока с дополняющими линейными коэффициентами громкости. Исходящий поток освобождается после перехода. Пауза останавливает оба потока, перемотка и замена трека отменяют незавершённые задачи. Режим остановки имеет приоритет для автоматических переходов.

На двух 12-секундных файлах с тишиной прошёл `--playback-test`:

- прежние проверки остановки, продолжения, старта с нуля, очереди и восстановления;
- реальное перекрытие двух работающих AVPlayer при коротком переходе;
- коэффициенты громкости, пауза/продолжение обоих потоков и общая громкость;
- отсутствие перехода после последнего трека без повтора;
- длинный переход около 6 секунд, отмена исходящего потока перемоткой;
- приоритет остановки над crossfade;
- ручное переключение с наложением и отмена незавершённого перехода заменой трека;
- обычное переключение при режиме «Без»;
- восстановление разных режимов для разных файлов.

Self-test и проверка подписи прошли. В интерфейсе macOS проверены сохранение очереди из четырёх треков, голубая палитра, NSVisualEffectView вместо сплошного фона, селекторы в строках и синхронизация селектора текущего трека с его строкой. Пользователь продолжает взаимодействовать с воспроизведением. Точность до аудиосэмпла, слуховая оценка громкости на реальной музыке и отдельная визуальная проверка мини-плеера не выполнялись. Crossfade не выполняет синхронизацию темпа или музыкальных долей.

## Версия 0.5.0 — массовое назначение переходов

Под селектором текущего трека добавлена кнопка «Применить ко всем» (в основном окне, мини-плеере и панели строки меню). Она назначает выбранный режим всем трекам текущей очереди одной операцией, сохраняя возможность последующих индивидуальных изменений. Справа отображается общий режим или «Разные переходы». Если режим текущего трека не меняется, массовое назначение не прерывает активное наложение.

Полный `--playback-test` на 12-секундных файлах прошёл, включая новые проверки массового применения всех трёх режимов, сохранения, отдельного переопределения, восстановления и отсутствия смены трека/позиции. Release-сборка и self-test прошли. В интерфейсе видна кнопка с подсказкой «Назначить режим „Короткий“ всем 4 трекам очереди»; сохранены четыре трека, текущая позиция 2:01. Воспроизведение после обновления возобновлено с сохранённой позиции и проверено по движению времени и состоянию Pause. Настройки реальной пользовательской очереди массово не изменялись при проверке.


## Версии 0.6.0 / 0.6.1 — две деки и упрощение

Реализованы две деки с реальными волнами из PCM, стабильный просмотр следующего трека (включая shuffle), номера очереди и отслеживание уходящего/входящего файла и коэффициентов при crossfade. Полный playback-test прошёл с дополнительными проверками идентичности дек, их номеров и продолжения перехода под общим замком. Waveform-test вне sandbox успешно декодировал реальный WAV: 160 отсчётов, 135.48 секунды, нормированный пик 1.0; внутри sandbox системный декодер был недоступен.

После обратной связи пользователя интерфейс уменьшен с 560×760 до 520×620, удалены повторяющиеся строки, отдельные регуляторы в деках, поиск и постоянные второстепенные настройки. Громкость, повтор, shuffle, режим начала и остановки доступны из одного popover. Для индивидуального перехода используется меню в строке, массовая кнопка сохранена.

Первоначальная реализация жеста через SwiftUI заменена NSView с нативными mouseDown/mouseDragged/mouseUp и mouseDownCanMoveWindow=false. Увеличена область захвата, порог свайпа уменьшен до 60 точек; таймер удержания установлен в common run-loop modes.

Финальная release-сборка 0.6.1, self-test модели/очереди/порогов замка и проверка подписи прошли. В отдельной QA-копии через реальный интерфейс Mac проверены блокировка, разблокировка перетаскиванием вверх и удержанием пробела; в обоих случаях управление снова стало доступно. Окно при свайпе осталось на месте. Проверены мини-плеер и popover с громкостью/режимами. QA-копия закрыта и удалена после проверки.

В основном приложении сохранены четыре файла, добавленные пользователем, его позиция и индивидуальный короткий переход. Два добавленных агентом файла с тишиной удалены из очереди отдельно; пользовательские файлы не удалялись. Текущий основной плеер открыт с упрощённым дизайном. Слуховая оценка всех форматов и поведение поверх полноэкранных приложений остаются непроверенными.


## 0.7.1 — English, playlists and optional button hints

App-authored strings and native document dialogs are English. `.hardplay` save/open supports order, selected track, positions, per-track fades, playback options, relative paths, bookmarks and recent playlists. The actual My Set playlist was saved on the Desktop with five entries. Playlist-test passed round-trip, relative paths, missing references, recents, unsupported version and invalid-file preservation.

Main Play/Pause is larger and translucent blue. Settings → Show button hints is persisted and defaults off. In the real app, the toggle was checked and hovering Mini Player visibly displayed “Show or hide the floating player”; descriptions do not intercept clicks. Hover state uses StateObject to survive playback-driven redraws.

User screenshot failure was traced to `an imported zero-byte WAV`: the existing file has zero bytes. The player now validates emptiness/readability, checks duration/playability, cancels stale loading on failure and retries the selected track. Errors leave Play visible. The periodic observer reads current engine time and clears stale time when no item exists. Final GUI confirmed 0:00 / 0:00, slider 0, Play and the exact empty-file message. The source file and five-track queue were preserved.

Release build/self-test and playlist-test passed. Playback-test passed on silent 12-second WAV/AIFF fixtures, including stopping, resume/restart, crossfade, lock continuity, bulk modes, persistence, empty-file retry and recovery to a valid track. Ad-hoc signature verified. The temporary QA app was closed and removed; the final main app was reopened. A complete copy of the empty WAV is still needed for that track to play.


## 0.8.0 — Mini playlist and configurable setup protection

Mini My Set now opens a bounded native popover containing the numbered queue, per-track fade menus, playlist file actions and Full Queue. The separate Tracks menu was replaced by a clear Edit Queue button. The main window has Edit and Lock Setup/Unlock controls; three independently configurable protection groups cover queue edits/fades, selection/skipping, and transport/seeking. Selection defaults protected; playback defaults available. Configuration persists, active lock resets on launch. UI and Player entry points both enforce protection; automatic advancement remains allowed. No user audio or queue entries were removed.

Release build/self-test and playlist round-trip test passed. Full silent-fixture playback-test passed, including the new isolated setup-lock checks: edits, selection and transport cannot change the snapshot; automatic next still loads the next track, and unlocking restores fade edits. Main-window GUI confirmed configurable checkboxes, disabled row/fade/add/skip controls, available Play/Restart/Resume, and restoration through Unlock. Mini GUI confirmed My Set opens the actual five-track list with numbered rows, fade controls and file/full-queue actions. App left in mini mode with queue popover open, playback paused at its restored position.


## 0.9.0 — Attached and independent playlist

A shared PlaylistWindowState persists detached mode. Main My Set → Detach Playlist and mini popover Detach show one independent resizable floating panel with frame autosave. It renders the existing queue component and uses the same Player, SetupLock and full ControlLock. Main embedded queue is hidden in detached mode; mini My Set reopens the independent panel. Closing the panel keeps mode; Attach can return to either main embedded list or mini popover.

Release build and model/lock self-test passed. In the real app, verified mini My Set → Detach opens HARDPLAY Playlist with the same five tracks, transition values and editing/protection controls. Attach to Main Player restored the full embedded queue. Main My Set → Detach Playlist reopened the independent panel. Attach to Mini Player returned focus to Mini; My Set again opened its attached five-track popover. Playback stayed paused at the existing 0:42 position and queue values were preserved. No new playback engine changes were made.


## 0.9.1 — Track aliases and larger titles

Track carries an optional customTitle while identity/path remain unchanged. Aliases persist through session bookmarks and optional playlist entry title, preserving backwards compatibility. Rename does not reload/seek/cancel transitions. Queue has a pencil action and Rename Track menu item, with Save/Cancel/Use Filename. Editing/full lock guards apply. Titles render at 15 pt in queue and 16/13 pt in main/mini decks, with two-line wrapping.

Release/self-test and playlist-test passed, including trimmed alias, unchanged source URL, session restore, document round-trip, reset-to-filename and legacy Track decoding. Full silent-fixture playback-test passed, including protection against renaming while setup is locked. GUI confirmed larger two-line titles and pencil controls; temporarily renamed the first track to AntiHouse Club — Live, verified both queue and deck changed while position remained 0:42 and playback paused, then restored the original using Use Filename. No source file or saved user playlist was modified by this GUI check.


## 0.10.0 — Inline naming, control mapping and master volume

Replaced the modal rename alert with a row-local text field and stable observable edit state. Pencil is visible on hover; menus retain Rename Track / Use Filename. Enter, checkmark or blur save, Esc cancels; edit locks cancel drafts. Real GUI verified Esc preserved the original title and Enter updated both row and deck without seeking; original filename restored after the check. No modal rename remains in sources.

Keyboard / MIDI panel opens via Settings or Shift-Command-M. Map mode exposes action targets on the transport, volume and main header buttons, plus action/track lists. Keyboard learn uses key codes/modifiers; optional global shortcuts register through Carbon. MIDI input uses CoreMIDI, per-source stream parsers, Note/CC press edges, and continuous CC for Master Volume. Input endpoint list refreshes on MIDI setup changes. JSON sets support save/load with version, bounds and duplicate validation. Local defaults persist assignments. Full lock suppresses triggers without consuming Space needed by the native unlock control. Standard Command shortcuts and the existing Option-Command-Space are reserved; opening the mapping panel remains possible during learning.

Always-visible Master Volume slider and percent were added to both player layouts, using the existing shared two-deck mix gain logic. GUI verified 80 → 90 → 80 percent, with the original level restored. Mapping panel exposes continuous MIDI CC for master volume and button/key Volume Up / Down.

Release build/self-test, playlist-test and silent-fixture playback-test passed. Mapping-test passed MIDI learn, running status, Note/CC release/retrigger, source isolation, continuous-volume messages including zero, duplicate shortcut replacement, persistence, set validation and lock/map suppression. Added direct original-storage MIDIPacketList extraction and verified a two-packet C buffer, avoiding copies of variable-length packet storage. Ad-hoc signature verified.

GUI confirmed Keyboard learn, received assigned command, Map button overlays, choosing Restart without resetting the track, and successful Carbon registration count of one. Temporary bindings cleared; queue, source filenames, saved playlist and original 80 percent level preserved. CoreMIDI enumerated the existing network input “Сеть RTP Session 1”. Cross-application delivery through synthesized Finder input was not confirmed; physical keyboard delivery and an external hardware controller remain live-input validation boundaries. Physical-controller operation is not claimed verified.


## 0.10.1 — Button behavior, symbols and protected settings

Each keyboard/MIDI binding now has optional Trigger/Toggle behavior. Stateful actions read actual player/window/setup state rather than maintaining a separate latch. Added Mute (restores its previous persisted level), Shuffle, Repeat and Stop at End actions. Existing Play/Pause and Mini bindings preserve their historical toggle default; one-shot actions remain Trigger, master volume remains continuous CC, and full control lock keeps its native unlock gesture. Set version 2 stores modes and version 1 still imports. Relearning preserves an existing binding mode. Global shortcuts now handle press/release and suppress repeated presses until release.

Rename, fade, remove, detach and attach use thin symbols in the primary UI; duration remains visible next to the fade symbol. Rename stays inline. Queue removal still only removes a reference. Added Settings & mappings protection to SetupLock. Audio settings and the mapping panel keep an enabled lock/unlock symbol above protected controls. Learn, clear, mode changes and set import/export are also guarded in the model. Existing mappings continue to run subject to the selected playback/queue restrictions.

Release build/self-test, playlist-test, mapping-test and the dedicated button-mode-test passed. Tests cover repeated idempotent Trigger, alternating Toggle, real state changes made outside mappings, persisted mute level restore, note press/release filtering, mode/session persistence, legacy sets, invalid toggle modes, settings protection and unlock. Full silent-fixture playback test passed, including new verification that Trigger starts audio once while Toggle pauses/resumes actual AVPlayer playback.

Real GUI confirmed pencil/waveform/trash row symbols, link attachment and icon-only setup lock. Keyboard / MIDI shows the user's existing Space assignment as Toggle · Off, and its menu contains Trigger/Toggle directly in one level. Settings lock disabled Map, input choice, learning, behavior menus, set menu and refresh while Unlock Settings stayed enabled; unlocking restored them. User Space binding and five-track queue were preserved, no user tracks were renamed/removed and no temporary mappings were left. Panel left open unlocked with Map off for review. Physical MIDI/global-input limitations from 0.10.0 remain unchanged.

## 0.12.0 — независимые копии, Select/Play, меню бар

Release-сборка 17, self-test, `--queue-test`, `--button-mode-test`, `--mapping-test` и проверка ad-hoc подписи проходят. Queue-test проверяет выбор без запуска/смены активного трека, уникальные ID копий одного файла, независимые названия и fade, сохранение/открытие `.hardplay`, сохранение копии при удалении исходного пункта и восстановление очереди.

На двух сгенерированных 12-секундных WAV с тишиной прошёл полный `--playback-test`: автостоп, restart/resume, автоматическая очередь, реальное перекрытие 3/6 секунд, пауза обоих декодеров, громкость, отсутствие повтора в конце, индивидуальные и массовые режимы, восстановление и защита настроек. Пользовательская музыка для этих тестов не проигрывалась.

В изолированном Mac-экземпляре через интерфейс подтверждены новые кнопки, открытие панели у меню бара, отсоединение в HARDPLAY Mini и повторное открытие основного окна. Для сворачивания используется NSWindow.miniaturize с восстановлением через deminiaturize; длительное поведение поверх полноэкранных приложений и всех Spaces в этой итерации не проверялось. В первом QA-экземпляре пользователь добавил трек; его очередь оставлена на месте.

Web: 21 автоматическая проверка и валидный Worker ESM. Через браузер проверены правый клик → Duplicate Track, отдельный Play, отсутствие запуска при Select, сохранение активного трека при выделении другого, глобальные 3s и Auto Stop. Ранее в этой итерации проверены независимое время пунктов, переход на 5-й секунде и повторная загрузка/дублирование при выключенном локальном сервере.

Дополнительно в нативном интерфейсе проверены: правый клик → Duplicate Track (получены два пункта одного файла), выделение без Play, явный Play второй копии, сохранение звучащей второй копии при выделении первой, назначение 3s всем пунктам. Проверка проводилась только на синтетическом WAV с тишиной. Исправление приёма Finder drop перенесено на корневой PlayerView, включая playlistOnly; веб-окно также получает обработчики на panel и на body отдельного окна, с остановкой всплытия для исключения двойного добавления. Фактический межоконный drag из Finder для этого последнего исправления отдельно не воспроизводился.

## 0.13.0 — wide workspace and installation

Native: resizable main window, width-dependent two-column layout at 840 pt, wide/standard button; explicit playlist placement buttons. Web: persistent wide layout, two-column breakpoint at 850 px, placement controls with pressed state, reattachment returns the original queue DOM. Install on Mac panel delegates installation to the browser and documents Add to Dock; no install is silently performed. Native bundle now displays its Dock icon.

Distribution packages are ad-hoc signed, not notarized. The local build targets Apple Silicon. Clean-Mac installation and real browser installation prompts are not implied by local build tests.

GUI verification for 0.13.0: native wide layout and detached playlist were opened in an isolated QA bundle; web width 1200 showed playback left / queue right and placement round-trip returned the same queue. After stopping the preview server, reloading restored both saved silent WAV tracks and Play advanced from the local cache. This verifies server-unavailable playback, not an installed Safari/Chrome app on a clean Mac.

Distribution: local self/queue/button-mode/mapping/playlist checks passed; code signature verification passed; DMG checksum verified. GitHub release assets uploaded. GitHub Actions returned startup_failure before any jobs ran; no passing CI result is claimed.

## 0.14.0 — front-facing red key identity

Generated front-facing Hard / Play icon is bundled in the Mac app, .icns, web manifest icons and header. The main transport uses a blank red keycap with an actual centered Play/Pause glyph, never a static label pretending to be playback state. Native UI and web preview were exercised with an isolated silent WAV: Play changed to Pause and back; selection, seeking and volume retain their existing controls. The native menu-bar drawing uses a simplified red Hard / Play key with a separate state badge and adaptive label-color state symbols. Installed browser icon refresh and appearance on other Macs remain platform-dependent.

Release build self/queue/button-mode checks and 21 web tests passed; Worker artifact validation passed. New button artwork is listed in the offline shell cache. This update does not claim that the previously failing GitHub Actions startup is repaired.

## 0.15.0 — live themes, drawer, hover time, pocket companion and edit history

Native release build/self/queue checks pass. UI verified independent Settings and Themes, Theatre selection, opacity/colors, Play/text-size slider changes, live theme on the main player, and round Play/Pause. Settings do not hide the main player. Minimize reveals the separate Pocket panel; Command-1 restores the main player. Removing a silent-fixture queue item then Command-Z restored it paused with 0:12 duration. Native queue tests also cover Undo/Redo remove and rename.

Web UI verified all six preset controls, simultaneous main/settings/themes panels, live Theatre accent, 78px Play button, 120% text, persisted settings after reload, and the modeless-panel fallback used by embedded browsers. Browser popup detachment is implemented but independent browser-popup interaction was unavailable in IAB. Web tests cover invalid stored appearance bounds and queue history copy/redo behavior, alongside existing audio/model tests.

Web UI imported a 12-second silent test fixture, duplicated it, removed the copy, undid removal, verified both items Saved Offline and played the restored copy. Minimize kept playback in the pocket widget with the track/time and restore control. Native companion is an actual floating panel; the web companion remains inside the browser page.

Earlier in the same update, web UI verified seek tooltip 0:00/0:06/0:12 without changing the seek value, all four drawer sides, My Set show/hide and detach/dock. Native hover and four-side drawer source compiled; native pointer-hover and multi-monitor anchoring have not been fully exercised. GitHub Actions startup failure from the prior release is not claimed repaired.

## 0.15.1 — explicit locks and display-bezel sensor

Web UI: moved the pocket widget, fixed its position, attempted dragging again and verified unchanged x/y; reload restored the same position and fixed state. The left display-bezel sensor opens and closes the panel. Controls Locked and Controls Available are visibly distinct; holding for 1.2 seconds returned to Available and stayed unlocked after mouse release. Position Fixed is independently labelled while buttons remain on. The original relock bug was caused by the release click entering the Lock action after the hold timer unlocked; that click is now consumed.

Native: dedicated AppKit mouse/keyboard hold view avoids competing SwiftUI Button and long-press gestures. Release build/self/queue checks pass; transparent display-bezel hit area, explicit position/control state rows, saved window position, isMovable position protection and regular-mini position lock are implemented. Final native pointer/hold validation is pending because the Mac was locked; no successful native hold test is claimed yet.

Cleanup: closed old localhost preview tabs and Drawer QA, stopped owned preview servers 4190–4194. One preview server remains temporarily for verification. An older real HARDPLAY process was discovered at the same build path; the locked Mac prevented its normal UI quit/relaunch. Do not confuse its old runtime with the rebuilt 0.15.1 files.

Web update entrypoint: added `/app/` aliases for shell assets and cloud proxy, preserving the origin and IndexedDB. This avoids the old root shell's cache hits without clearing user audio. Artifact validation checks root, `/app/`, script/service-worker routes and invalid-cloud-request handling.

## 0.15.2 — desktop placement and plain HARD PLAY heading

Restarted the original native process into the current build, keeping a single app instance. Native UI verified Lock Widget Controls disables play/skip while audio continues; a 1.2-second hold restored Available and stayed unlocked after release. The heading shows HARD PLAY with no slash.

Added a native header drag view with first-mouse acceptance and mouse-event screen coordinates, plus screen-edge constraints based on the visible player face rather than its transparent side-panel margin. Self-test covers left/top/right/bottom clamp geometry. Native drag UI changed the saved frame from 1440,18 to -91,681; position lock prevented a subsequent drag and the same frame was restored on launch. The left-edge Locks overlay stayed reachable. A final refinement reads event CG coordinates to avoid stale global-cursor reads during forwarded input. Subsequent user interaction took over the main window, so further synthetic dragging was stopped; multi-display dragging has not been exhaustively tested.

The web heading was updated and built/validated without changing its existing in-page drag behavior. Native remains the desktop floating player. No new QA app variants or local preview servers were launched for this update.

## 0.17–0.19 — backup preparation and audio editing

Native build/self/queue, playlist, mapping, button-mode and clip checks passed during development. Backup tests exercised real TLS loopback pairing, role and code rejection, heartbeat timeout, source-change invalidation, manifest comparison and portable package integrity. GUI verified the independent backup panel and a two-track local hash/decode check. No physical second-Mac, synchronized playback, LTC/MTC or audio failover validation is claimed; only backup preparation is implemented.

The clip test generates its own stereo ramp WAV. It verifies sample-exact trimming, noncontiguous two-region joining including the boundary samples, output length/channels/rate, preservation of the source, overwrite rejection, cancellation cleanup, copy/replace identities, Undo/Redo and playlist persistence. It also checks clip splitting and selection, zoom/pan bounds, waveform peaks and Option-audition stop conditions. User audio is not played by these tests.

GUI verified the earlier numeric editor's 10–20 second selection. The newer waveform mouse gestures and joins have automated model/export coverage; final pointer-driven GUI verification remains pending while an existing user editor draft is open. The running app has not been restarted over that draft. Native pocket seek/resize geometry and separate-window toggle decisions are covered by self-tests; exhaustive pointer and multi-display testing remains pending.

## 0.20.0 — local Web Viewer and fixed hints

Native build/self/queue, viewer and clip tests pass. The viewer test exercises real local HTTP state and pause updates, session token rotation/rejection, source-path omission, duplicate queue numbers, finite timing, setup-lock enforcement and rejection of control/file routes, cross-origin/invalid-host requests and malformed headers. DMG/ZIP checksums and app signature pass.

Browser UI verified synthetic live updates, a 390px mobile breakpoint, reload with the session link, and explicit Connection lost / Last known state after terminating the fixture. Native UI verified Start / Stop Sharing, QR generation, link copying and revocation. A browser on localhost displayed the real app's two-track My Set and paused position. Direct probes to this Mac's two LAN IPs timed out; the macOS application firewall reports disabled/permitted. The cause is unresolved and no successful phone/second-device LAN connection is claimed. Primary IPv4 service address is preferred over static aliases; users can choose an alternate address.

The native app was restarted into 0.20.0 with one real instance, preserving the paused queue/position. Reserved top hint areas were visually checked in the player and Settings. No popup overlays are used by stageHint; each window has an independent channel. CUA accessibility clicks did not produce a hover entry, so final physical-pointer hover verification remains pending. Sharing was stopped after verification. The hosted offline web player was not redeployed by this update.

## 0.21.0 — clear marker identity and interactive deck waves

The native release build, self/queue/style/waveform, clip, viewer, playlist, mapping and button-mode checks pass. The bundled font registers as BalsamiqSans-Bold; all three tape presets and the approved beam artwork are present. Web source passes 28 tests and builds with its local font/license cached for offline use. The hosted Site has not been redeployed.

The waveform check uses a generated 12-second silent WAV, isolated defaults, and muted AVPlayers. It verifies fraction/time clamps, paused current seek, a NEXT cue without switching playback, cue consumption on automatic next and manual crossfade, outgoing seek during a fade, incoming seek cancelling the fade, explicit play-from-position, invalid input rejection and setup protection. NEXT cues are one-shot session state, not playlist-file metadata. Layout checks cover growing the main window, preserving larger user frames and fitting a short display.

Native GUI checked in the actual app: clearer lettering, both queue rows visible, detached playlist reattached without shrinking, click on NOW waveform changed 0:08 to 1:00 while remaining paused, and the time bubble appeared inside the waveform above its bars. Position was returned to approximately 0:08. Evidence: build/HARDPLAY-0.21-main.png and build/HARDPLAY-0.21-waveform.png (local only). No user audio was started. One real application instance remains running, test previews were closed. Final DMG/ZIP SHA-256 verification passes; app is ad-hoc signed and not notarized. Existing physical LAN/phone viewer limitations from 0.20 remain.

## 0.22.0 — window modes, Auto Nano, Auto Fit and equipment themes

Release build/self/queue/style, waveform/geometry, playlist, mapping and button-mode checks pass. Auto Fit geometry checks cover shrinking to content height, preserving width/top edge, and clamping to the display. Native GUI verified the live height calculation with four real queue items, both embedded and separate playlist states, and the last row fully visible after accounting for the macOS title area. The main window follows the hint strip's visible/hidden height. Auto Fit is optional and saved separately from Auto Nano.

GUI verified Mini opening with all header controls fitting its minimum width; Full Screen enters and exits with the same button; the question button collapses the hint strip. With Auto Nano on, minimizing changed Nano visibility to Open; with it off, minimizing left Nano Hidden. Returning to the main player restores the window. The companion retains its floating window level. User playback was interrupted only after explicit authorization for the update; no test started user audio.

Right-clicking a deck exposes Edit Audio; right-clicking a row exposes Edit Audio and other queue actions. Choosing Edit Audio opened the waveform editor; it was closed without exporting or altering audio. A single changing window icon embeds/detaches the queue; the separate panel includes a direct embed action, and dock directions remain available. The graphic app badge is removed from the header; a shield-shaped text wordmark remains, shifted slightly right. Speaker Grille and Road Case are present in the theme picker, with hardware controls, perforation or case rails; Flightcase also uses the hardware finish. The native update does not redeploy the hosted web player.


The final 0.22 build also adds raised control surfaces, 16.5-point fixed hints and two workspace presentations. Build/self/queue/style, clip, waveform/layout, playlist, mapping and button-mode checks pass. Layout tests verify adjacent free-space placement without overlap where space permits, and in-bounds cascading on a small display. The clip test verifies that repeating prepare preserves the current range. Native GUI verified Single Window mode, Settings and Themes tabs in the main Hard Play window, the persistent bottom transport, enlarged hints, and raised buttons. Speaker Grille and Road Case were both visually inspected. Full physical multi-monitor placement and a long-running export while switching workspace modes have not been hardware-validated. No synchronized playback or failover capability is implied.

GUI additionally verified migration of an already-open separate Settings panel into Single Window, returning to Nearby Windows and opening separate Settings, and the Audio Edit tab loading the selected track with preview disabled while the main player was playing. The mobile project was started in a separate user-requested chat/directory; this repository does not claim an App Store or Google Play release.


## 0.23.0 personal controls preview

Build/self/queue/style, isolated workspace/quick-button/circular-gesture, mapping and button-mode checks pass. The workspace check covers destination persistence/unknown fallback, quick action assignment and mode validity, the four-button limit, protected mutations, circle direction/backtracking/invalid jumps and a three-second hold threshold. Circular pointer movement is checked by the shared geometry model; an actual circular mouse drag has not been automated.

Native GUI verified the clockwise ring and hints, refusal to unlock after a one-second Space hold, successful unlock after a 3.2-second hold, absence of Main/Mini header wordmarks, expanded window preferences, Ask Each Time dialog, opening Themes inside the player while global workspace remained Nearby, creation of a Control Hints quick button, two-click Toggle operation and its context menu/removal. Temporary theme destination and quick button were restored/removed after the test. User audio was left paused at its saved position after the authorized restart. No physical MIDI or multi-display validation is implied.


## 0.23.1 PATCH rear panel

Build/self/queue/style, workspace/quick-action/circular-unlock, mapping and button-mode checks pass. The blanket lock on the playback layout was replaced with explicit locks on decks, seek, transport, volume, transition controls and playlist, leaving the PATCH edge and corner entry available. The large automatic unlock panel was removed; the circular unlock view is now in PATCH.

Native GUI verified the two-row Main toolbar, the corner PATCH button, PATCH open/close state, Controls Available status, Lock Controls / Lock Setup / Open PATCH Settings entries, and the full Hard Play PATCH settings window. Screenshot: local build/HARDPLAY-0.23.1-patch.png (not exported). A timed physical edge hold and the Mini layout were not fully GUI-validated in this pass: input was interrupted by window changes, then the computer-use service reported no available windows. Source and existing protection tests pass; no claim of complete gesture/hardware validation.


## 0.24.0 crew sets

Build/self/queue/style, playlist lifecycle and playlist round-trip checks pass. Lifecycle checks use isolated defaults and a temporary directory: named/empty creation, prior saved-file bytes unchanged, Undo restoring document binding and fades, protection guards, deletion failure leaving the set intact, simulated trash move of the document only, recent-list cleanup, audio bytes unchanged and Undo after deletion restoring an unsaved queue. OS Trash integration uses FileManager.trashItem; the lifecycle test injects a temporary move instead of touching the user's Trash.

Native GUI verified New Playlist through Command-N, creating FOH Test Set, and Undo restoring the user's previous name/empty queue. The FOH, Stage Crew and Stagehand presets are present in Themes. FOH was applied and visually inspected in Main: marker mini hardplay button, spaced controls, touring case rim/corner hardware and quiet FOH/PLAYBACK labelling. FOH is left active; playback is stopped. Local screenshot build/HARDPLAY-0.24-foh.png is excluded from the public source export.

No new raster artwork or animated backgrounds are added. The existing licensed Permanent Marker font is now bundled for the dedicated Mini label (74,632 uncompressed bytes); other UI text keeps Balsamiq for readability. The other two crew palettes have not received full physical-display inspection.
