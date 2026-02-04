#!/bin/bash
set -e

echo "Ruta aplicación: ${APP_PATH}"
echo "Package name: ${PACKAGE_NAME}"
echo "Device simulator: ${DEVICE_SIMULATOR}"

# Crear directorios
mkdir -p frames debug_logs

echo "Configuracion inicial"

echo "Obtener UUID del simulador"
UUID=$(xcrun simctl list devices "${DEVICE_SIMULATOR}" available 2>/dev/null | grep -m 1 -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)

echo "UUID del simulador: $UUID"

if [ -z "$UUID" ]; then
    echo "? No se encontró el simulador iPhone 16 Pro"
    echo "Simuladores disponibles:"
    xcrun simctl list devices available
    exit 1
fi

echo "? Usando Simulador: $UUID"

# Función para timeout en macOS (alternativa a timeout command)
run_with_timeout() {
    local timeout=$1
    shift
    perl -e "alarm $timeout; exec @ARGV" "$@"
}

echo ""
echo "Arranque del simulador"

echo "Verificar estado actual"
CURRENT_STATE=$(xcrun simctl list devices | grep "$UUID" | grep -o "([^)]*)" | tail -1)
echo "Estado actual: $CURRENT_STATE"

echo "Intentar arrancar si no está booted"

if [[ "$CURRENT_STATE" != *"Booted"* ]]; then
    echo "Arrancando simulador..."
    xcrun simctl boot $UUID 2>&1 || true
    
    echo "Esperando arranque (máx 120s)..."
    for i in {1..12}; do
        sleep 10
        STATE=$(xcrun simctl list devices | grep "$UUID" | grep -o "([^)]*)" | tail -1)
        echo "  [$i/12] Estado: $STATE"
        
        if [[ "$STATE" == *"Booted"* ]]; then
            echo "? Simulador arrancado"
            break
        fi
        
        if [ $i -eq 12 ]; then
            echo "? Timeout esperando arranque"
            exit 1
        fi
    done
else
    echo "? Simulador ya está arrancado"
fi

echo "Esperando SpringBoard..."
sleep 5

echo ""
echo "Preparación de la APP"
if [ ! -d "${APP_PATH}" ]; then
    echo "? No se encuentra la app en: ${APP_PATH}"
    exit 1
fi

echo "Limpiando archivos innecesarios..."
find "${APP_PATH}" -name ".DS_Store" -delete 2>/dev/null || true
xattr -rc "${APP_PATH}" 2>/dev/null || true

echo "Firmando componentes..."
# codesign --force --deep --sign - --timestamp=none "${APP_PATH}" 2>&1 | head -n 10
#codesign --force --sign - --timestamp=none --generate-entitlement-der "${APP_PATH}" 2>&1 | head -n 10
#
#echo "Verificando firma..."
#codesign -vvv "${APP_PATH}" 2>&1 | head -n 5


# echo "FIRMA NIVEL GUERRA PARA XCODE 16"

# echo "1. Crear un archivo de permisos al vuelo (esto es la llave)"
# cat <<EOF > debug.entitlements
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#     <key>com.apple.security.get-task-allow</key>
#     <true/>
#     <key>com.apple.security.cs.disable-library-validation</key>
#     <true/>
#     <key>com.apple.security.cs.allow-jit</key>
#     <true/>
# </dict>
# </plist>
# EOF

# echo "2. Limpieza total de atributos (crucial en Runner de GitHub)"
# xattr -cr "${APP_PATH}"

# echo "3. Firma con Hardened Runtime y los permisos inyectados"
# --options=runtime activa el Hardened Runtime
# --entitlements inyecta la configuración para que iOS no te bloquee
# codesign --force --deep --sign - --options=runtime --entitlements debug.entitlements --timestamp=none "${APP_PATH}"

# echo "? Firma completada. Verificando..."
# codesign -vvv --display "${APP_PATH}"

echo ""
echo "Instalación "
echo ""

echo "Desinstalando versión previa (si existe)..."
xcrun simctl uninstall $UUID "${PACKAGE_NAME}" 2>/dev/null || true

# para que siri no la vea como una descarga de internet y le de los permisos
echo "Limpieza total de atributos de cuarentena"
chmod -R 755 "${APP_PATH}"
xattr -rc "${APP_PATH}"
chmod +x "${APP_PATH}/${PROJECT_FOLDER}"
sudo xattr -rd com.apple.quarantine "${APP_PATH}" 2>/dev/null || true
# echo "Firma ad-hoc limpia (importante en Apple Silicon)"
# codesign --force --deep --sign - "${APP_PATH}"

sleep 5

#

echo "Instalando app..."
if xcrun simctl install $UUID "${APP_PATH}"; then
    echo "? App instalada correctamente"

    echo "Otorgando permisos de notificación..."
    xcrun simctl privacy $UUID grant notifications "${PACKAGE_NAME}" || {
        echo "?? simctl privacy falló (permisos de macOS). Intentando vía AppleScript..."
        osascript -e 'tell application "System Events" to tell process "Simulator" to click button "Allow" of window 1' || echo "No se pudo hacer clic automático."
    }

    xcrun simctl spawn $UUID notifyutil -p com.apple.SpringBoard.icons-changed || echo "?? No se pudo refrescar iconos, continuando..."

else
    echo "? Falló la instalación"
    exit 1
fi

sleep 10

echo "Verificando instalación...-si no verifica, fue fantasma , copio pero no registro la app"
echo "Verificando si la app es un fantasma..."
if xcrun simctl listapps $UUID | grep -q "${PACKAGE_NAME}"; then
    echo "? Confirmado: La app está registrada."
else
    echo "? ERROR: La app se instaló pero NO aparece en el sistema (posible problema de firma)."
    exit 1
fi

echo ""
sleep 5
echo "Captura de logs"

echo "Iniciar captura de logs en background"
LOG_FILE="app_stream_full.txt"
xcrun simctl spawn $UUID log stream --level debug > "$LOG_FILE" 2>&1 &
LOG_PID=$!
echo "Log stream iniciado (PID: $LOG_PID)"

sleep 5

echo ""
echo "Lanzamiento de la APP"
#LAUNCH_OUTPUT=$(xcrun simctl launch $UUID ${PACKAGE_NAME} 2>&1)
xcrun simctl launch --stderr=/tmp/app_stderr.txt $UUID ${PACKAGE_NAME}
echo "$LAUNCH_OUTPUT" | tee debug_logs/launch_output.txt

# Forzar creación del contenedor de datos (el Sandbox)
xcrun simctl get_app_container $UUID "${PACKAGE_NAME}" data

APP_PID=$(echo "$LAUNCH_OUTPUT" | grep -oE '[0-9]+' | head -1)
echo "App lanzada (PID: $APP_PID)"

echo "Esperando inicialización de la app..."
sleep 5

echo ""
echo "Captura de frames"
FRAME_COUNT=25
FRAME_DELAY=1

for i in $(seq 1 $FRAME_COUNT); do
    printf "Frame %2d/%d\r" $i $FRAME_COUNT
    
    echo "Actualizar status bar (opcional)"
    xcrun simctl status_bar $UUID override --time "12:$(printf "%02d" $i)" 2>/dev/null || true
    
    # Capturar screenshot
    if xcrun simctl io $UUID screenshot "frames/f${i}.png" 2>/dev/null; then
        #: # Screenshot exitoso
        echo "Screenshot exitoso $i"
    else
        echo "??  Error capturando frame $i"
    fi
    
    sleep $FRAME_DELAY
done

echo ""
echo "? Capturados $FRAME_COUNT frames"

echo ""
echo "Finalizando captura de logs"
# Detener log stream de forma ordenada
kill -TERM $LOG_PID 2>/dev/null || true
sleep 2
kill -KILL $LOG_PID 2>/dev/null || true
wait $LOG_PID 2>/dev/null || true

# Copiar log stream a debug_logs
[ -f "$LOG_FILE" ] && cp "$LOG_FILE" debug_logs/ || true

echo ""
echo "Generación de git"
FRAME_FILES=(frames/f*.png)
if [ ${#FRAME_FILES[@]} -gt 0 ] && [ -f "${FRAME_FILES[0]}" ]; then
    echo "Procesando ${#FRAME_FILES[@]} frames..."
    
    # Usar gtimeout si está disponible (brew install coreutils), sino usar perl
    if command -v gtimeout &> /dev/null; then
        TIMEOUT_CMD="gtimeout 30s"
    else
        TIMEOUT_CMD="run_with_timeout 30"
    fi
    
    $TIMEOUT_CMD ffmpeg -y -framerate 2 \
        -pattern_type glob -i 'frames/f*.png' \
        -vf "scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        evidencia_app.gif 2>&1 | tail -n 5
    
    if [ -f evidencia_app.gif ]; then
        echo "? GIF generado: $(ls -lh evidencia_app.gif | awk '{print $5}')"
    else
        echo "? Error generando GIF"
    fi
else
    echo "??  No hay frames para generar GIF"
fi

echo ""
echo "Captura de logs del sistema"
echo ""

echo "Capturando logs del dispositivo..."
run_with_timeout 30 xcrun simctl spawn $UUID log show --last 5m > debug_logs/device_full_log.txt 2>&1 || echo "Timeout/error en device log"

echo "Capturando logs de la app (por bundle ID)..."
run_with_timeout 30 xcrun simctl spawn $UUID log show --last 5m --predicate "senderIdentifier == '${PACKAGE_NAME}'" > debug_logs/app_specific_log.txt 2>&1 || echo "Timeout/error en app log"

echo "Capturando logs de la app (por proceso)..."
run_with_timeout 30 xcrun simctl spawn $UUID log show --last 5m --predicate 'process == "${PROJECT_FOLDER}"' > debug_logs/app_process_log.txt 2>&1 || echo "Timeout/error en ${PROJECT_FOLDER} log"

echo "Capturando logs del sistema..."
run_with_timeout 30 xcrun simctl spawn $UUID log show --last 5m --info --debug > debug_logs/system_log_full.txt 2>&1 || echo "Timeout/error en system log"

echo ""
echo "Busqueda de crash reports"
echo ""
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$CRASH_DIR" ]; then
    find "$CRASH_DIR" -name "*${PROJECT_FOLDER}*" -mtime -1 -exec cp {} debug_logs/ \; 2>/dev/null || true
    find "$CRASH_DIR" \( -name "*.ips" -o -name "*.crash" \) -mtime -1 -exec cp {} debug_logs/ \; 2>/dev/null || true
    
    CRASH_COUNT=$(ls debug_logs/*.{ips,crash} 2>/dev/null | wc -l)
    echo "Crash reports encontrados: $CRASH_COUNT"
else
    echo "??  Directorio de crash reports no encontrado"
fi


echo ""
echo "Resumen final"
echo ""
echo "?? Artefactos generados:"

if [ -f evidencia_app.gif ]; then
    echo "? GIF: $(ls -lh evidencia_app.gif | awk '{print $5}')"
else
    echo "? GIF: No generado"
fi

echo ""
echo "?? Logs capturados:"
if ls debug_logs/*.txt 1> /dev/null 2>&1; then
    for log in debug_logs/*.txt; do
        SIZE=$(ls -lh "$log" | awk '{print $5}')
        NAME=$(basename "$log")
        if [ "$SIZE" = "102B" ]; then
            echo "  ??  $NAME: $SIZE (posiblemente vacío)"
        else
            echo "  ? $NAME: $SIZE"
        fi
    done
else
    echo "  ? No se generaron logs"
fi

echo ""
echo "?? Crash reports:"
CRASH_COUNT=$(ls debug_logs/*.{ips,crash} 2>/dev/null | wc -l | tr -d ' ')
if [ "$CRASH_COUNT" -gt 0 ]; then
    echo "  ??  $CRASH_COUNT crash reports encontrados"
    ls -lh debug_logs/*.{ips,crash} 2>/dev/null
else
    echo "  ? No se encontraron crash reports"
fi

echo ""
echo "???  Frames capturados: $(ls frames/f*.png 2>/dev/null | wc -l | tr -d ' ')"

echo ""
echo "? Script completado"