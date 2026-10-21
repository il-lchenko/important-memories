# Замена placeholder'ов в privacy.html и offer.html

После оформления самозанятости в приложении «Мой налог» замени в обоих файлах **3 placeholder'а**. Они визуально выделены amber-цветом в браузере и в формате `{{PLACEHOLDER_NAME}}`.

## Где искать

Оба файла:
- `guest-pwa/public/privacy.html`
- `guest-pwa/public/offer.html`

## 3 placeholder'а для замены

### 1. `{{FULL_NAME}}` (5 мест в privacy.html + 4 в offer.html)

**Что заменить:** твоё ФИО как в паспорте / свидетельстве НПД.

**На что заменить:** например, `Ильченко Илья Николаевич`

**Найти в файле** — Ctrl+F по `{{FULL_NAME}}`

### 2. `{{INN}}` (2 места в privacy.html + 3 в offer.html)

**Что заменить:** твой ИНН (12 цифр).

**Где взять:** в приложении «Мой налог» → раздел «Профиль» или в справке о постановке на учёт.

**На что заменить:** например, `771234567890`

### 3. `{{DATE_EFFECTIVE}}` (3 места в privacy.html + 3 в offer.html)

**Что заменить:** дата вступления документа в силу.

**На что заменить:** день, когда ты замещаешь placeholder'ы. Формат — `1 сентября 2026 г.` или `01.09.2026`.

## Как заменить (2 способа)

### Способ A — Notepad++ / VS Code / любой редактор

1. Открыть `privacy.html`
2. Ctrl+H (Найти и заменить)
3. Найти: `{{FULL_NAME}}` → Заменить: `Ильченко Илья Николаевич` → Заменить всё
4. Повторить для `{{INN}}` и `{{DATE_EFFECTIVE}}`
5. Сохранить
6. То же для `offer.html`

### Способ B — sed (командная строка)

```bash
# Из корня проекта
sed -i 's/{{FULL_NAME}}/Ильченко Илья Николаевич/g' guest-pwa/public/privacy.html
sed -i 's/{{INN}}/771234567890/g' guest-pwa/public/privacy.html
sed -i 's/{{DATE_EFFECTIVE}}/1 сентября 2026 г./g' guest-pwa/public/privacy.html

sed -i 's/{{FULL_NAME}}/Ильченко Илья Николаевич/g' guest-pwa/public/offer.html
sed -i 's/{{INN}}/771234567890/g' guest-pwa/public/offer.html
sed -i 's/{{DATE_EFFECTIVE}}/1 сентября 2026 г./g' guest-pwa/public/offer.html
```

## После замены — деплой

```bash
scp guest-pwa/public/privacy.html root@217.149.29.227:/opt/im/guest-pwa/dist/
scp guest-pwa/public/offer.html   root@217.149.29.227:/opt/im/guest-pwa/dist/
```

Или проще — попроси меня, я сделаю в 30 секунд.

## Как проверить что все placeholder'ы заменены

Открыть файл в браузере (`file://.../privacy.html`) → ни одного amber-выделенного `{{PLACEHOLDER}}` быть не должно.

Или через grep:
```bash
grep -c "{{" guest-pwa/public/privacy.html   # должно вернуть 0
grep -c "{{" guest-pwa/public/offer.html     # должно вернуть 0
```

## Также после замены

**Обнови футер файла** (внизу оба документа) — там висит `версия 1.0`. При каждом существенном обновлении — увеличивай (`1.1`, `1.2`, ...) и обновляй дату.

## Опционально — юр.review

За 5-15K₽ можно попросить юриста-специалиста по 152-ФЗ проверить документы перед RuStore submit. Не обязательно, но снижает риск отклонения модерацией.
