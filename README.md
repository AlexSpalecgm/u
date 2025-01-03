### Спецификация к Bash-скрипту

**Общее описание:**

Скрипт предназначен для обработки текстовых файлов с определенным форматом, извлечения метрик из имен файлов, формирования пар label и значений, а также отправки этих данных на указанный сервер. Он также осуществляет сохранение логов о результате обработки.

**Основные сложности:**

- Работа с файлами: поиск, чтение и удаление.

- Обработка данных: извлечение метрик и пар label.

- Взаимодействие с сервером: отправка данных и анализ ответа.

### 1. Указание директории для работы

```
directory="/home/exporter/1/"
```

Скрипт начинает с указания директории, в которой будет производиться работа.

### 2. Получение текущего времени

```
current_time_sec=$(date +%s)
```

Определение текущего времени в секундах с начала эпохи, чтобы использовать это для проверки сроков давности файлов.

### 3. Указание целевого URL

```
url="localhost:8428/api/v1/import/prometheus"
```

Скрипт определяет URL для отправки метрик.

### 4. Поиск файлов по маске

```
mask="2[4-6][0-1][0-2][0-9][0-5][0-9][0-9][0-9][0-9]_*.txt"
files=$(ls $mask 2>/dev/null)
```

Осуществляется поиск файлов по указанной маске. Если файлы не найдены, скрипт завершится с соответствующим сообщением.

### 5. Проверка и обработка каждого файла

```
for file in $files; do
```

Цикл проходит по всем найденным файлам и выполняет следующие действия:

- Извлечение даты и времени из имени файла для проверки его валидности.

- Преобразование даты и времени в секунды с начала эпохи.

  

```
year="20${file_date:0:2}"
month="${file_date:2:2}"
day="${file_date:4:2}"
file_time_sec=$(date -d "${year}-${month}-${day} ${hour}:${minute}" +%s 2>/dev/null)
```

### 6. Проверка актуальности файла

```
if (( current_time_sec - file_time_sec > 301 )); then
```

Проверяется, не старше ли файл 5 минут. Если старше, файл удаляется.

### 7. Чтение и обработка данных из файла

```
IFS=$'\t' read -r -a labels < "$file"
```

Считывание заголовка (имен label) из первой строки файла. 

```
tail -n +2 "$file" | while IFS=$'\t' read -r -a values; do
```

Обработка всех строк, кроме первой, извлекая первый столбец значений для data_value и пропуская первый столбец в label_pairs.

### 8. Формирование и отправка данных на сервер

```
data_value="${metric_name}{${labels_string}} ${values[0]}"
response_value=$(curl -s -w "%{http_code}" -o /dev/null -X POST -d "$data_value" "$url")
```

Формирование строки с метриками и отправка её на сервер. Ответ сервера проверяется на успешность.

### 9. Логирование

```
echo "Отправлено: $data_value" >> "$log_file"
echo "Ответ сервера: $response_value" >> "$log_file"
```

Сохранение информации об отправленных данных и ответах в лог-файлы.

### 10. Завершение обработки файла

```
if [[ $all_success == true ]]; then
echo "$file" >> "$log_file"
fi
rm "$file"
```

Если все данные были успешно отправлены, имя обработанного файла записывается в лог, после чего файл удаляется.

**Заключение:**

Скрипт реализует полную обработку метрик, обеспечивает логику валидации и фильтрации данных, а также надежное взаимодействие с сервером для передачи метрик.
