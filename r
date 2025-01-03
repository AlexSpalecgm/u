#!/usr/bin/env bash

# Указываем директорию для работы
directory="/home/exporter/1/"

# Текущая дата и время в секундах с начала эпохи
current_time_sec=$(date +%s)

# Указываем URL для отправки данных
url="http://localhost:8428/api/v1/import/prometheus"

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
mask="2[4-6][0-1][0-2][0-9][0-9][0-9][0-9][0-9][0-9]_*.txt"

# Находим файлы по маске
files=$(ls $mask 2>/dev/null)

# Проверяем, найдены ли файлы
if [ -z "$files" ]; then
    echo "Файлы не найдены!"
    exit 1
fi

start_time=$(date +%s%3N)  # Общее время начала работы скрипта в миллисекундах

# Перебираем найденные файлы и проверяем их срок годности
for file in $files; do
    # Извлекаем часть имени файла после '_'
    file_suffix="${file#_}"  # Получаем часть после первого '_'

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

    # Чтение метрики из имени файла
    metric_name="${file#*_}"  # Убираем часть до первого '_'
    metric_name="${metric_name%.txt}"  # Убираем .txt

    # Удаляем символы перевода каретки и обрабатываем файл с AWK для формирования строки для VictoriaMetrics
    metrics_data=$(tr -d '\r' < "$file" | awk -v metric_name="$metric_name" -F'\t' '
    NR==1 {
        # Чтение заголовка с labels
        for (i=2; i<=NF; i++) labels[i-1]=$i; 
        next
    }
    {
        # Формируем значения для каждого ряда
        value = $1;  # Значение метрики из первого столбца
        values = "";
        for (i=2; i<=NF; i++) {
            if (values != "") values = values ",";
            values = values labels[i-1] "=\"" $i "\"";  # Значения label в кавычках
        }
        print metric_name "{" values "} " value;  # Добавляем значение метрики
    }')

    # Отправка данных в VictoriaMetrics
    if [[ -n "$metrics_data" ]]; then
        curl -X POST --data "$metrics_data" "$url"
        # Логируем отправленные данные
        metrics_count=$(echo "$metrics_data" | wc -l)  # Считаем количество строк метрик
        echo -e "Отправленные данные для файла '$file':\n$metrics_data\nКоличество отправленных метрик: $metrics_count" >> "$log_file"
        # Удаляем файл после успешной обработки
        rm "$file"
    fi
done

end_time=$(date +%s%3N)  # Общее время окончания работы скрипта в миллисекундах
total_duration=$((end_time - start_time))  # Общее время выполнения скрипта

# Запись в лог с информацией о выполнении
echo "Общее время выполнения скрипта: $total_duration мс" >> "$log_file"
