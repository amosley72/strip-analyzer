import io
import os
import time
import requests
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Initialize the FastAPI Production App
app = FastAPI(
    title="Lateral Flow Strip Quantitative Analyzer",
    description="Production-grade 4PL and Roboflow engine handling image micro-profiling.",
    version="1.0.0"
)

# Enable CORS for Mobile/Flutter Development Connections
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- TRUE 4PL CALIBRATION PARAMS (From your fitted Colab Curve) ---
A = -0.1000  # Minimum Asymptote
B = -0.8434  # Hill Slope
C = 0.0147   # Inflection Point
D = 3.0000   # Maximum Asymptote

# --- ROBOFLOW API CREDENTIALS ---
API_KEY = "2bkVHYg4suLikhfIwOfK"
MODEL_ENDPOINT = "my-first-project-7hb5n/6"

def logistic_4pl(x: float, A_param: float, B_param: float, C_param: float, D_param: float) -> float:
    """Calculates chemical concentration safely handling negative exponential slopes."""
    if x <= 0:
        return 0.0
    try:
        return ((A_param - D_param) / (1.0 + ((x / C_param) ** B_param))) + D_param
    except:
        return 0.0

# Structured JSON Response Contract
class AnalysisResult(BaseModel):
    tc_ratio: float
    estimated_concentration_mg_ml: float
    interpretation: str

@app.get("/")
def read_root():
    return {"status": "Online", "engine": "Roboflow Dynamic Scan Integration Active"}

@app.post("/analyze", response_model=AnalysisResult)
async def analyze_strip(file: UploadFile = File(...)):
    if not file:
        raise HTTPException(status_code=400, detail="No file payload provided.")
    
    try:
        # 1. Read network image stream bytes directly
        contents = await file.read()
        
        # Convert raw bytes directly into a numpy byte array
        nparr = np.frombuffer(contents, np.uint8)
        
        # Decode the byte array directly into a native OpenCV BGR matrix
        # This completely bypasses PIL and mirrors Colab's cv2.imread behavior 1:1
        open_cv_image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if open_cv_image is None:
            raise HTTPException(status_code=400, detail="Uploaded file is not a valid image format.")
            
        img_height, img_width = open_cv_image.shape[:2]
        
        # Isolate Green Channel matrix directly from the native BGR matrix
        green_channel = open_cv_image[:, :, 1]
        
        # Save temporary file for the cloud API endpoint request payload
        temp_filename = f"temp_upload_{int(time.time())}.png"
        cv2.imwrite(temp_filename, open_cv_image)
        
        # 2. Adaptive Confidence Discovery Scan Engine
        test_confidences = list(range(90, 15, -5)) + list(range(15, 4, -1))
        raw_predictions = []
        all_predictions_at_chosen_confidence = []
        found_suitable_predictions = False
        
        for current_conf in test_confidences:
            upload_url = f"https://detect.roboflow.com/{MODEL_ENDPOINT}?api_key={API_KEY}&confidence={current_conf}"
            
            try:
                with open(temp_filename, "rb") as img_file:
                    response = requests.post(upload_url, files={"file": img_file})
                
                if response.status_code != 200:
                    continue
                    
                result = response.json()
                current_all_predictions = result.get("predictions", [])
                predictions_at_current_conf = [p for p in current_all_predictions if p.get('class') == 'Band']
                
                if len(predictions_at_current_conf) >= 2:
                    raw_predictions = predictions_at_current_conf
                    all_predictions_at_chosen_confidence = current_all_predictions
                    found_suitable_predictions = True
                    break
                elif current_conf == 5:
                    raw_predictions = predictions_at_current_conf
                    all_predictions_at_chosen_confidence = current_all_predictions
                    found_suitable_predictions = True
                    break
            except:
                continue

        # Clean up disk footprint immediately
        if os.path.exists(temp_filename):
            os.remove(temp_filename)
            
        # 3. Guardrails & Spatial Constraints
        if not found_suitable_predictions or len(raw_predictions) < 2:
            return AnalysisResult(
                tc_ratio=0.0,
                estimated_concentration_mg_ml=2.0,
                interpretation="Below detection sensitivity limit. Target concentration saturated at 2 mg/mL or greater."
            )
            
        # 4. PROFILE PEAK MATH ENGINE (High Precision 11px Micro-Windows)
        def calculate_high_precision_peak(box):
            bx, by, bw, bh = int(box["x"]), int(box["y"]), int(box["width"]), int(box["height"])
            
            # Shave 10% off edges to protect from background plastic frame shading artifacts
            edge_pad = max(1, int(bw * 0.10))
            x1 = max(0, bx - bw//2 + edge_pad)
            x2 = min(img_width, bx + bw//2 - edge_pad)
            y1 = max(0, by - bh//2)
            y2 = min(img_height, by + bh//2)
            
            roi = green_channel[y1:y2, x1:x2]
            if roi.size == 0:
                return 0.0
                
            # Compress matrix vertically into horizontal signal wave
            profile_line = np.mean(roi, axis=0)
            
            # Local background threshold derivation
            if len(profile_line) > 6:
                bg_left = np.mean(profile_line[:3])
                bg_right = np.mean(profile_line[-3:])
                local_background = (bg_left + bg_right) / 2.0
            else:
                local_background = np.mean(profile_line)
                
            signal_profile = local_background - profile_line
            signal_profile[signal_profile < 0] = 0
            
            # Isolate 11-pixel core around true absorption peak
            peak_idx = np.argmax(signal_profile)
            window_radius = 5
            start_w = max(0, peak_idx - window_radius)
            end_w = min(len(signal_profile), peak_idx + window_radius + 1)
            
            return float(np.mean(signal_profile[start_w:end_w]))

        # --- Robust Class-Based Assignment Engine ---
        test_band = None
        control_band = None
        
        # Look for explicit class names if your model uses them
        for band in raw_predictions:
            if band.get('class_name') == 'test' or band.get('class') == 'test_line':
                test_band = band
            elif band.get('class_name') == 'control' or band.get('class') == 'control_line':
                control_band = band

        # Fallback: Check orientation coordinates dynamically before assigning
        if test_band is None or control_band is None:
            sorted_bands = sorted(raw_predictions, key=lambda b: b["x"])
            
            front_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') == 'Front of strip'), None)
            back_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') == 'Back of strip'), None)
            
            # If front is on the right side, the image is rotated 180 degrees
            if front_of_strip_x is not None and back_of_strip_x is not None and front_of_strip_x > back_of_strip_x:
                print("Image detected as physically rotated 180 degrees. Reversing line assignments.")
                test_band = sorted_bands[1]  # Control on left, Test on right
                control_band = sorted_bands[0]
            else:
                test_band = sorted_bands[0]  # Normal orientation
                control_band = sorted_bands[1]

        # --- Execution of Peak Density Math ---
        t_density = calculate_high_precision_peak(test_band)
        c_density = calculate_high_precision_peak(control_band)
        
        if c_density <= 0:
            return AnalysisResult(
                tc_ratio=0.0,
                estimated_concentration_mg_ml=2.0,
                interpretation="Control line density registered as unreadable. Invalid test matrix execution."
            )
            
        computed_tc_ratio = t_density / c_density
        
        # 5. Model Evaluation
        predicted_concentration = logistic_4pl(computed_tc_ratio, A, B, C, D)
        
        # Enforce range safety definitions
        if predicted_concentration < 0.0625:
            interpretation = "Below Lower Limit of Quantification (< 0.0625 mg/mL) - Trace quantities detected."
            predicted_concentration = max(0.0, predicted_concentration)
        elif computed_tc_ratio <= 0.00114 or predicted_concentration >= 2.0:
            interpretation = "Saturation Limit Reached (>= 2.000 mg/mL). High concentration."
            predicted_concentration = 2.0
        else:
            interpretation = "Quantitation Successful. Within linear dynamic calibration range."
            
        return AnalysisResult(
            tc_ratio=round(computed_tc_ratio, 4),
            estimated_concentration_mg_ml=round(predicted_concentration, 4),
            interpretation=interpretation
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Engine failure during real-time compilation: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    import os
    # This dynamically checks if Render gave it a port, fallback to 8001 if local
    port = int(os.environ.get("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
