import os
import cv2
import numpy as np
import requests
from flask import Flask, render_template, request, send_file, jsonify, session
from werkzeug.utils import secure_filename
from fpdf import FPDF
from io import BytesIO
import tempfile
import uuid

UPLOAD_FOLDER = 'uploads'
RECTIFIED_FOLDER = 'rectified'
FILTERED_FOLDER = 'filtered'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['RECTIFIED_FOLDER'] = RECTIFIED_FOLDER
app.config['FILTERED_FOLDER'] = FILTERED_FOLDER
app.secret_key = 'supersecretkey'

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(RECTIFIED_FOLDER, exist_ok=True)
os.makedirs(FILTERED_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def np_to_base64(img, ext='.jpg'):
    _, buf = cv2.imencode(ext, img)
    return BytesIO(buf)

def np_to_base64str(img, ext='.jpg'):
    _, buf = cv2.imencode(ext, img)
    from base64 import b64encode
    return b64encode(buf.tobytes()).decode('utf-8')

def base64_to_np(base64str):
    from base64 import b64decode
    img_bytes = b64decode(base64str)
    arr = np.frombuffer(img_bytes, dtype=np.uint8)
    return cv2.imdecode(arr, cv2.IMREAD_UNCHANGED)

def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def four_point_transform(image, pts):
    rect = order_points(pts)
    (tl, tr, br, bl) = rect
    widthA = np.linalg.norm(br - bl)
    widthB = np.linalg.norm(tr - tl)
    maxWidth = int(max(widthA, widthB))
    heightA = np.linalg.norm(tr - br)
    heightB = np.linalg.norm(tl - bl)
    maxHeight = int(max(heightA, heightB))
    dst = np.array([
        [0, 0],
        [maxWidth - 1, 0],
        [maxWidth - 1, maxHeight - 1],
        [0, maxHeight - 1]
    ], dtype="float32")
    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
    return warped

def detect_document(image):
    ratio = image.shape[0] / 500.0
    image_resized = cv2.resize(image, (int(image.shape[1] / ratio), 500))
    gray = cv2.cvtColor(image_resized, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5,5), 0)
    edged = cv2.Canny(blurred, 50, 150)
    kernel = np.ones((5,5),np.uint8)
    dilate = cv2.dilate(edged, kernel, iterations=1)
    closing = cv2.morphologyEx(dilate, cv2.MORPH_CLOSE, kernel)
    contours, _ = cv2.findContours(closing.copy(), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    doc_cnt = None
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            doc_cnt = approx.reshape(4,2) * ratio
            break
    # Solo la preview lleva el marco
    preview = image.copy()
    if doc_cnt is not None:
        doc_cnt_int = np.int32(doc_cnt)
        cv2.polylines(preview, [doc_cnt_int], True, (0,255,255), 3)
    return preview, doc_cnt

def apply_filter(img, filter_type):
    if filter_type == "gray":
        return cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    elif filter_type == "bw":
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        _, bw = cv2.threshold(gray, 128, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        return bw
    elif filter_type == "color":
        return img
    else:
        return img

def adjust_brightness_contrast_smooth(img, brightness=0, contrast=1.0, smooth=0):
    if len(img.shape) == 2:
        img = img.astype(np.float32)
        img = img * contrast + brightness
        img = np.clip(img, 0, 255)
        img = img.astype(np.uint8)
        if smooth > 0 and smooth % 2 == 1:
            img = cv2.GaussianBlur(img, (smooth, smooth), 0)
        return img
    else:
        img = img.astype(np.float32)
        img = img * contrast + brightness
        img = np.clip(img, 0, 255)
        img = img.astype(np.uint8)
        if smooth > 0 and smooth % 2 == 1:
            img = cv2.GaussianBlur(img, (smooth, smooth), 0)
        return img

def rotate_image(img, angle):
    angle = int(angle)
    if angle == 0:
        return img
    rot_code = {
        90: cv2.ROTATE_90_CLOCKWISE,
        180: cv2.ROTATE_180,
        270: cv2.ROTATE_90_COUNTERCLOCKWISE
    }
    if angle in rot_code:
        return cv2.rotate(img, rot_code[angle])
    (h, w) = img.shape[:2]
    center = (w // 2, h // 2)
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    return cv2.warpAffine(img, M, (w, h), borderMode=cv2.BORDER_REPLICATE)

def save_image(img, folder):
    # Save as jpg with unique name, return filename
    filename = f"{uuid.uuid4().hex}.jpg"
    path = os.path.join(folder, filename)
    cv2.imwrite(path, img)
    return filename

def load_image_from(folder, filename):
    path = os.path.join(folder, filename)
    img = cv2.imread(path)
    return img

@app.route('/', methods=['GET'])
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if file and allowed_file(file.filename):
        filename = secure_filename(f"{uuid.uuid4().hex}_{file.filename}")
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file.save(file_path)
        img = cv2.imread(file_path)
        # Guarda el nombre de la imagen original sin marco para siguientes pasos
        session['orig_img_filename'] = filename
        preview, doc_cnt = detect_document(img)
        # La preview lleva el marco amarillo
        preview_b64 = np_to_base64str(preview)
        doc_cnt_list = doc_cnt.tolist() if doc_cnt is not None else []
        return jsonify({
            'preview': preview_b64,
            'doc_cnt': doc_cnt_list
        })
    return jsonify({'error': 'Archivo no permitido'}), 400

@app.route('/webcam', methods=['POST'])
def webcam():
    data = request.json
    url = data['url']
    try:
        resp = requests.get(url, timeout=5)
        img_arr = np.asarray(bytearray(resp.content), dtype=np.uint8)
        img = cv2.imdecode(img_arr, cv2.IMREAD_COLOR)
        if img is None:
            return jsonify({'error': 'No se pudo decodificar la imagen.'}), 400
        filename = f"{uuid.uuid4().hex}_webcam.jpg"
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        cv2.imwrite(file_path, img)
        session['orig_img_filename'] = filename
        preview, doc_cnt = detect_document(img)
        preview_b64 = np_to_base64str(preview)
        doc_cnt_list = doc_cnt.tolist() if doc_cnt is not None else []
        return jsonify({
            'preview': preview_b64,
            'doc_cnt': doc_cnt_list
        })
    except Exception as e:
        return jsonify({'error': f'No se pudo obtener la imagen de la webcam: {e}'}), 400

@app.route('/rectify', methods=['POST'])
def rectify():
    data = request.json
    orig_img_filename = session.get('orig_img_filename')
    if not orig_img_filename:
        return jsonify({'error': 'No hay imagen original cargada.'}), 400
    doc_cnt = np.array(data['doc_cnt'], dtype=np.float32)
    img = load_image_from(app.config['UPLOAD_FOLDER'], orig_img_filename)
    rectified = four_point_transform(img, doc_cnt)
    rectified_filename = save_image(rectified, app.config['RECTIFIED_FOLDER'])
    session['rectified_img_filename'] = rectified_filename
    rectified_b64 = np_to_base64str(rectified)
    return jsonify({'rectified': rectified_b64})

@app.route('/filter', methods=['POST'])
def filter_api():
    data = request.json
    # Usa la imagen rectificada si existe, si no la original
    rectified_img_filename = session.get('rectified_img_filename')
    if rectified_img_filename:
        img = load_image_from(app.config['RECTIFIED_FOLDER'], rectified_img_filename)
    else:
        orig_img_filename = session.get('orig_img_filename')
        if not orig_img_filename:
            return jsonify({'error': 'No hay imagen para filtrar.'}), 400
        img = load_image_from(app.config['UPLOAD_FOLDER'], orig_img_filename)
    filter_type = data.get('filter', 'color')
    brightness = int(data.get('brightness', 0))
    contrast = float(data.get('contrast', 1.0))
    smooth = int(data.get('smooth', 0))
    rotate = int(data.get('rotate', 0))
    img = rotate_image(img, rotate)
    filtered = apply_filter(img, filter_type)
    processed = adjust_brightness_contrast_smooth(filtered, brightness, contrast, smooth)
    filtered_filename = save_image(processed, app.config['FILTERED_FOLDER'])
    session['filtered_img_filename'] = filtered_filename
    processed_b64 = np_to_base64str(processed)
    return jsonify({'processed': processed_b64})

@app.route('/save', methods=['POST'])
def save():
    data = request.json
    # Usa la imagen filtrada si existe, si no la rectificada, si no la original
    fname = session.get('filtered_img_filename')
    folder = app.config['FILTERED_FOLDER']
    if not fname:
        fname = session.get('rectified_img_filename')
        folder = app.config['RECTIFIED_FOLDER']
    if not fname:
        fname = session.get('orig_img_filename')
        folder = app.config['UPLOAD_FOLDER']
    if not fname:
        return "No hay imagen para descargar", 400

    img = load_image_from(folder, fname)
    output_format = data.get('output', 'image')
    if output_format == 'image':
        is_success, buffer = cv2.imencode(".jpg", img)
        if not is_success:
            return "Error al codificar la imagen", 500
        byte_io = BytesIO(buffer)
        byte_io.seek(0)
        return send_file(byte_io, mimetype="image/jpeg", as_attachment=True, download_name="documento.jpg")
    else:
        is_success, buffer = cv2.imencode(".jpg", img)
        if not is_success:
            return "Error al codificar la imagen para PDF", 500
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp:
            tmp.write(buffer)
            tmp.flush()
            pdf = FPDF(unit='pt', format=[img.shape[1], img.shape[0]])
            pdf.add_page()
            pdf.image(tmp.name, 0, 0, img.shape[1], img.shape[0])
            pdf_bytes = pdf.output(dest='S').encode('latin1')
            pdf_io = BytesIO(pdf_bytes)
            pdf_io.seek(0)
        os.unlink(tmp.name)
        return send_file(pdf_io, mimetype="application/pdf", as_attachment=True, download_name="documento.pdf")

if __name__ == '__main__':
    app.run(debug=True)