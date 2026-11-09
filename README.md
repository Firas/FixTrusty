<p align="center">
  <img src="assets/icon.png" alt="FixTrusty" width="160">
</p>

# FixTrusty

[![Windows](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.10.7+-02569B.svg?logo=flutter)](https://flutter.dev)

**FixTrusty** — десктопный клиент для VPN-протокола [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel)
под Windows. Это доработанная версия [Trusty](https://github.com/Meddelin/trusty), которую автор перестал
поддерживать.

> Код переделан с помощью [Claude](https://claude.com/claude-code) (Anthropic).

Сайт: [fixic.net](https://fixic.net)

## Что добавлено по сравнению с Trusty

- **Импорт ссылки `tt://`.** Servers → Add server → вставить ссылку, которую выдаёт сервер
  (`trusttunnel_endpoint ... -a <адрес>`). Заполняются все поля, включая **самоподписанный
  сертификат сервера**: его оригинальный Trusty не поддерживал. Если адрес в ссылке указан
  доменом, он автоматически переводится в IP. Если ссылка уже лежит в буфере обмена, она
  подставится сама.
- **Автозапуск с Windows и автоподключение.** Кнопка ⏻ внизу навигации:
  - «Start with Windows» создаёт задачу в Планировщике с повышенными правами, поэтому UAC при
    входе в систему не появляется. Программа стартует свёрнутой в трей.
  - «Connect on launch» подключает VPN сразу после запуска. Если сеть ещё не поднялась,
    программа пробует ещё несколько раз.
- **Списки исключений, которые обновляются сами.** Списки по URL (вкладка Split Tunnel)
  обновляются раз в 30 минут и при каждом подключении (в Trusty было раз в сутки). Если
  список изменился во время работы VPN, программа на секунду переподключается, чтобы
  применить его. Свой список можно держать на сервере и дописывать туда домены, а все
  клиенты подтянут их сами. Как это сделать, описано ниже в разделе
  [«Свой список исключений»](#свой-список-исключений).
- **Другое название (FixTrusty)** и отдельное хранилище настроек, поэтому программа может стоять
  рядом с оригинальным Trusty.

Остальное (несколько серверов, split tunneling, списки маршрутизации, SOCKS5-режим, установка
сервера по SSH) работает как в Trusty. Его описание лежит в
[docs/README-trusty-original.md](docs/README-trusty-original.md) и
[CONFIGURATION.md](CONFIGURATION.md).

## Установка

1. Скачайте архив из [Releases](../../releases) и распакуйте его, например в `C:\FixTrusty`.
2. Запустите `FixTrusty.exe` и подтвердите запрос прав администратора. Права нужны драйверу
   Wintun для TUN-режима.
3. Servers → Add server → вставьте ссылку `tt://...` → Import → Add → Connect.

## Свой список исключений

Типичная задача: весь трафик идёт через VPN, а российские сайты (банки, госуслуги, Яндекс)
открываются напрямую. Для этого нужен режим **General** и список исключений.

### Вариант 1. Вписать вручную

Split Tunnel → режим **General** → добавьте домены по одному или кнопкой вставки списка
(по одному на строку). Пример:

```
*.ru
*.рф
*.su
*.yandex.net
*.yastatic.net
```

`*.ru` означает все поддомены `.ru`, а `example.com` означает сам домен и `www`. Также можно
указывать IP-адреса и подсети (`1.2.3.0/24`) и программы (`chrome.exe`).

### Вариант 2. Держать список на своём сервере (обновляется сам)

1. Положите на любой HTTPS-сервер обычный текстовый файл, например
   `https://example.com/bypass.txt`, в кодировке UTF-8: по одной записи на строку, строки
   с `#` считаются комментариями. Подойдёт любой веб-сервер, GitHub Gist (ссылка Raw) или
   папка static/media вашей панели.
2. В FixTrusty: Split Tunnel → **Add list** → вставьте ссылку → добавьте. Затем в настройках
   списка (значок ⚙ у списка) выберите **General mode**: новые списки по умолчанию работают
   в режиме Selective.
3. Дальше просто редактируйте файл на сервере. FixTrusty проверяет его раз в 30 минут и при
   каждом подключении.

### Вариант 3. Вшить список в свою сборку

Чтобы список появлялся сам при первом запуске, без ручного добавления, укажите его адрес
при сборке:

```powershell
flutter build windows --release --dart-define=FIXTRUSTY_BYPASS_URL=https://example.com/bypass.txt
```

Список добавится один раз, в режиме General. Если пользователь удалит его в интерфейсе,
он больше не вернётся.

## Сборка из исходников

Нужны Flutter 3.10.7+ и Visual Studio 2022 (или Build Tools) с компонентами
**Desktop development with C++** и **C++ ATL**.

```powershell
flutter pub get
flutter test
flutter build windows --release
```

Результат появится в `build\windows\x64\runner\Release\`. Рядом с `FixTrusty.exe` положите папку
`client\` с `trusttunnel_client.exe` (проверено на 1.0.49) и `wintun.dll`. Подробности в
[BUILDING.md](BUILDING.md).

## Ссылки

- Оригинал: [Meddelin/trusty](https://github.com/Meddelin/trusty)
- Протокол и сервер: [TrustTunnel/TrustTunnel](https://github.com/TrustTunnel/TrustTunnel)
- CLI-клиент: [TrustTunnel/TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient)
- Формат ссылок `tt://`: [DEEP_LINK.md](https://github.com/TrustTunnel/TrustTunnel/blob/master/DEEP_LINK.md)

## Лицензия

[Apache License 2.0](LICENSE), как и у оригинала. Изменения перечислены в [NOTICE](NOTICE) и
[CHANGELOG.md](CHANGELOG.md).

---

**English.** FixTrusty is a Windows GUI client for the [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel)
VPN protocol, forked from the unmaintained [Trusty](https://github.com/Meddelin/trusty) and reworked with
the help of Claude (Anthropic). It adds the following:
- `tt://` deep-link import, including self-signed server certificates;
- start with Windows (an elevated logon task with no UAC prompt) and connect on launch;
- URL routing lists that refresh every 30 minutes and reconnect on change. A bypass list can
  also be baked into a build with `--dart-define=FIXTRUSTY_BYPASS_URL=...`.

Licensed under Apache 2.0.
