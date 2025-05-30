# DocScanner

<p align="center">
  <img src="static/logo.png" alt="DocScanner Logo" style="max-height:40px;">
</p>

Aplicación web simple y eficiente para escanear documentos usando tu PC o la cámara de tu celular (vía IP Webcam), con funciones de enderezado, filtros, recorte y descarga en imagen o PDF.

---

## Características

- **Logo personalizado:** Visualización del logo en la interfaz.
- **Carga desde PC** o **toma la foto con tu celular** (usando apps tipo IP Webcam).
- **Detección automática de bordes** del documento con previsualización y marco amarillo (solo en la vista previa).
- **Aplanar** (corregir perspectiva) y recortar el documento.
- **Filtros:** Color, escala de grises, blanco y negro.
- **Ajustes:** Brillo, contraste, suavizado, rotación.
- **Descarga:** Imagen (JPG) o PDF del documento enderezado y filtrado.
- **Botón Limpiar:** Permite reiniciar el flujo para escanear otro documento fácilmente.
- **Interfaz moderna y responsiva** con Bootstrap.

---

## Instalación

1. **Clona o descarga este repositorio.**
2. Instala las dependencias en tu entorno:
   ```
   pip install -r requirements.txt
   ```
3. Ejecuta la app:
   ```
   python app.py
   ```
4. Abre tu navegador en [http://localhost:5000](http://localhost:5000)

---

## Uso

### Escanear desde PC

1. Haz clic en "Subir foto (PC)" y selecciona una imagen de tu documento.
2. Se mostrará una vista previa con el marco amarillo de detección.
3. Pulsa "Aplanar" si deseas corregir la perspectiva.
4. Aplica los filtros y ajustes que desees.
5. Elige el formato de salida y haz clic en "Procesar y Descargar".

### Escanear con tu celular usando IP Webcam

1. Instala la app [IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam) en tu celular.
2. Abre la app y pulsa "Iniciar servidor".
3. Desde el navegador de tu PC, pega la URL de snapshot (ejemplo: `http://192.168.1.3:8080/shot.jpg`) en el campo correspondiente y haz clic en "Tomar foto".
4. Procede igual que en el caso anterior.

### Limpiar para escanear otro documento

- Haz clic en el botón **Limpiar** para reiniciar el flujo y cargar una nueva imagen o URL.

---

## Estructura de archivos

- `app.py` – Lógica principal (Flask + OpenCV)
- `templates/index.html` – Interfaz principal del usuario
- `static/styles.css` – Estilos personalizados
- `static/logo.png` – **Coloca aquí el logo** (usa el proporcionado)
- `uploads/`, `rectified/`, `filtered/` – Carpetas para imágenes temporales

---

¿Comentarios o sugerencias? ¡Bienvenido tu feedback!