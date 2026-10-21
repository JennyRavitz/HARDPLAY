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
