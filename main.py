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

def scan_with_phone_camera():
    # URL de IP Webcam (ajusta la IP y puerto)
    url = "http://192.168.1.3:8080/video"
    cap = cv2.VideoCapture(url)
    
    if not cap.isOpened():
        print("Error: No se pudo conectar al celular.")
        return

    try:
        while True:
            
            # Dentro del bucle while True:
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('s'):  # Guardar documento
                if doc_contour is not None:
                    try:
                        cv2.imwrite("documento_escaneado.jpg", warped)
                        print("Documento guardado exitosamente!")
                    except Exception as e:
                        print(f"Error al guardar: {e}")
                else:
                    print("No se detectó un documento para guardar.")


            ret, frame = cap.read()
            if not ret:
                print("Error al recibir el frame.")
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

            # Dibujar y rectificar
            if doc_contour is not None:
                cv2.drawContours(frame, [doc_contour], -1, (0, 255, 0), 2)
                ordered_pts = order_points(doc_contour.reshape(4, 2))
                (tl, tr, br, bl) = ordered_pts

                width = int(max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl)))
                height = int(max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)))

                dst = np.array([[0, 0], [width-1, 0], [width-1, height-1], [0, height-1]], dtype="float32")
                matrix = cv2.getPerspectiveTransform(ordered_pts, dst)
                warped = cv2.warpPerspective(frame, matrix, (width, height))
                cv2.imshow("Documento Rectificado", warped)
                

            cv2.imshow("Escaneo con Celular", frame)

            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    except KeyboardInterrupt:
        print("Programa detenido.")

    finally:
        cap.release()
        cv2.destroyAllWindows()

# Ejecutar
scan_with_phone_camera()