#!/usr/bin/env bash

# Указываем директорию для работы
directory="/home/exporter/1/"

# Текущая дата и время в секундах с начала эпохи
current_time_sec=$(date +%s)

# Указываем URL для отправки данных
url="localhost:8428/api/v1/import/prometheus"

# Переходим в указанную директорию
cd "$directory" || { echo "Ошибка: не удалось перейти в директорию $directory"; exit 1; }

# Проверяем, существуют ли лог-файлы, если нет - создаем
log_file="log.txt"
log_bad_file="log_bad.txt"

if [ ! -f "$log_file" ]; then
    touch "$log_file"
fi

if [ ! -f "$log_bad_file" ]; then
    touch "$log_bad_file"
fi

# Формируем маску для поиска файлов
mask="2[4-6][0-1][0-2][0-9][0-5][0-9][0-9][0-9][0-9]_*.txt"

# Находим файлы по маске
files=$(ls $mask 2>/dev/null)

# Проверяем, найдены ли файлы
if [ -z "$files" ]; then
    echo "Файлы не найдены!"
    exit 1
fi

# Перебираем найденные файлы и проверяем их срок годности
for file in $files; do
    # Извлекаем часть имени файла после '_'
    file_suffix="${file#*_}"  # Получаем часть после первого '_'

    # Извлекаем дату и время из имени файла
    file_date="${file:0:6}"  # ГГММДД
    file_time="${file:6:4}"  # ЧЧММ

    # Проверяем валидность времени (часы < 24 и минуты < 60)
    hour="${file_time:0:2}"
    minute="${file_time:2:2}"
    if (( 10#$hour >= 24 || 10#$minute >= 60 )); then
        echo "$file" >> "$log_bad_file"
        rm "$file"
        continue
    fi

    # Преобразуем дату и время в секунды с начала эпохи
    year="20${file_date:0:2}"
    month="${file_date:2:2}"
    day="${file_date:4:2}"
    file_time_sec=$(date -d "${year}-${month}-${day} ${hour}:${minute}" +%s 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "$file" >> "$log_bad_file"
        rm "$file"
        continue
    fi

    # Сравниваем разницу времени, чтобы знать, не старше ли файл 5 минут
    if (( current_time_sec - file_time_sec > 301 )); then
        echo "$file" >> "$log_bad_file"
        rm "$file"
        continue
    fi

    # Флаг для отслеживания успешной обработки файла
    all_success=true

    # Чтение метрики из имени файла
    metric_name="${file_suffix%.txt}"  # Убираем .txt

    # Считываем заголовок (имена labels)
    IFS=$'\t' read -r -a labels < "$file"

    # Пропускаем первую строку и читаем остальные строки файла
    tail -n +2 "$file" | while IFS=$'\t' read -r -a values; do
        # Проверяем, если строка пустая, то пропускаем её
        if [[ -z "${values[*]}" ]]; then
            continue
        fi

        # Формируем данные для отправки на сервер
        # Создаем строку для labels, начиная со второго элемента
        label_pairs=()
        for (( i=1; i<${#labels[@]}; i++ )); do
            # Экранируем кавычки в значениях
            labels[i]="${labels[i]//\"/\\\"}"
            values[i]="${values[i]//\"/\\\"}"  # Экранируем кавычки
            label_pairs+=("${labels[i]}=\"${values[i]:-NULL}\"")  # Заполняем значениями или NULL
        done
        
        labels_string=$(IFS=,; echo "${label_pairs[*]}")  # Объединяем пары и добавляем запятые

        # Изменяем data_value, передавая только первый столбец
        data_value="${metric_name}{${labels_string}} ${values[0]}"

        # Отправляем данные на сервер и сохраняем ответ
        response_value=$(curl -s -w "%{http_code}" -o /dev/null -X POST -d "$data_value" "$url")

        # Записываем отправленные данные и ответ в лог
        echo "Отправлено: $data_value" >> "$log_file"
        echo "Ответ сервера: $response_value" >> "$log_file"

        if [[ "$response_value" != "200" && "$response_value" != "204" ]]; then
            all_success=false
        fi
    done

    # Запись имени обработанного файла в log.txt, если данные успешно отправлены
    if [[ $all_success == true ]]; then
        echo "$file" >> "$log_file"
    fi

    # Удаляем исходный файл
    rm "$file"
done
