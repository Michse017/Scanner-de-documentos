import cv2
import numpy as np

def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]  # Esquina superior izquierda
    rect[2] = pts[np.argmax(s)]  # Esquina inferior derecha
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]  # Esquina superior derecha
    rect[3] = pts[np.argmax(diff)]  # Esquina inferior izquierda
    return rect

def scan_document_realtime():
    cap = cv2.VideoCapture(0)  # Iniciar cámara (0 = cámara predeterminada)
    
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        
        # Preprocesamiento
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edged = cv2.Canny(blurred, 50, 150)
        
        # Detectar contornos
        contours, _ = cv2.findContours(edged.copy(), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]
        
        # Buscar contorno del documento
        doc_contour = None
        for contour in contours:
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            if len(approx) == 4:
                doc_contour = approx
                break
        
        # Dibujar contorno y rectificar
        if doc_contour is not None:
            cv2.drawContours(frame, [doc_contour], -1, (0, 255, 0), 2)  # Dibujar en verde
            
            # Ordenar puntos y aplicar transformación
            ordered_pts = order_points(doc_contour.reshape(4, 2))
            (tl, tr, br, bl) = ordered_pts
            
            # Calcular dimensiones del documento
            width = int(max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl)))
            height = int(max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)))
            
            # Definir puntos de destino
            dst = np.array([[0, 0], [width-1, 0], [width-1, height-1], [0, height-1]], dtype="float32")
            
            # Obtener matriz de transformación
            matrix = cv2.getPerspectiveTransform(ordered_pts, dst)
            warped = cv2.warpPerspective(frame, matrix, (width, height))
            
            # Mostrar documento rectificado en otra ventana
            cv2.imshow("Documento Rectificado", warped)
        
        # Mostrar video original
        cv2.imshow("Escaneo en Tiempo Real", frame)
        
        # Teclas de control
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):  # Salir
            break
        elif key == ord('s'):  # Guardar documento
            if 'warped' in locals():
                cv2.imwrite("documento_escaneado.jpg", warped)
                print("Documento guardado!")
    
    cap.release()
    cv2.destroyAllWindows()

# Ejecutar
scan_document_realtime()