import io
import os
import time
import requests
import cv2
import numpy as np
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
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
A = 0.9701  # Minimum Asymptote
B = 0.6768  # Hill Slope
C = 0.0703   # Inflection Point
D = -0.0717   # Maximum Asymptote

# --- ROBOFLOW API CREDENTIALS ---
API_KEY = "77mP6FibKN6ybXjlQ6oq"
MODEL_ENDPOINT = "my-first-project-7hb5n/8"

# 📐 LOCKED PRODUCTION BAND DIMENSIONS (In Pixels)
FIXED_BAND_WIDTH = 20
FIXED_BAND_HEIGHT = 24

def inverse_logistic_4pl(y: float, A_param: float, B_param: float, C_param: float, D_param: float) -> float:
    """Calculates chemical concentration from a given T/C ratio using the inverse 4PL model."""
    try:
        if y <= D_param:
            return 2.0  
        
        numerator = A_param - D_param
        denominator = y - D_param
        
        inner_value = (numerator / denominator) - 1.0
        if inner_value <= 0:
            return 0.0
            
        return C_param * (inner_value ** (1.0 / B_param))
    except:
        return 0.0

# Structured JSON Response Contract
class AnalysisResult(BaseModel):
    tc_ratio: float = 0.0
    estimated_concentration_mg_ml: float = 0.0
    original_concentration_mg_ml: float = 0.0  
    interpretation: str = ""
    dilution_factor: int = 1                   
    qualitative_result: str = ""              # 👈 NEW: Binary objective result ("Positive", "Negative", "Invalid")

@app.get("/", response_class=FileResponse)
def read_root():
    return Path(__file__).resolve().parent / "index.html"

@app.post("/analyze", response_model=AnalysisResult)
async def analyze_strip(
    file: UploadFile = File(...),
    dilution_factor: int = Form(1)  
):
    if not file:
        raise HTTPException(status_code=400, detail="No file payload provided.")
    
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        open_cv_image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if open_cv_image is None:
            raise HTTPException(status_code=400, detail="Uploaded file is not a valid image format.")
            
        img_height, img_width = open_cv_image.shape[:2]
        green_channel = open_cv_image[:, :, 1]
        
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

        if os.path.exists(temp_filename):
            os.remove(temp_filename)
            
        # 3. Guardrails & Spatial Constraints / Objective Interpretation
        if not found_suitable_predictions or len(raw_predictions) < 2:
            # Determine status if 2 clear lines aren't found
            if len(raw_predictions) == 1:
                qual_status = "POSITIVE"  # Only 1 line visible (Control line present, Test line gone)
            else:
                qual_status = "INVALID"   # 0 lines visible
                
            return AnalysisResult(
                tc_ratio=0.0,
                estimated_concentration_mg_ml=2.0,
                original_concentration_mg_ml=2.0 * dilution_factor,
                interpretation="Target concentration saturated at 2 mg/mL or greater." if qual_status == "POSITIVE" else "No lines could be identified.",
                dilution_factor=dilution_factor,
                qualitative_result=qual_status
            )
            
        # 4. PROFILE PEAK MATH ENGINE 
        def calculate_high_precision_peak(box):
            bx, by = int(box["x"]), int(box["y"])
            bw, bh = int(box["width"]), int(box["height"]) # 🌟 Grab actual box dimensions
            
            # Pad the width slightly to ensure we capture surrounding background context
            padding = max(10, int(bw * 0.25))
            
            x1 = max(0, bx - (bw // 2) - padding)
            x2 = min(img_width, bx + (bw // 2) + padding)
            y1 = max(0, by - (bh // 2))
            y2 = min(img_height, by + (bh // 2))
            
            roi = green_channel[y1:y2, x1:x2]
            if roi.size == 0:
                return 0.0
                
            # Collapse vertically to get horizontal profile
            profile_line = np.mean(roi, axis=0)
            
            # Dynamic background sampling based on new window size
            sample_width = max(2, len(profile_line) // 6)
            if len(profile_line) > 2 * sample_width:
                bg_left = np.median(profile_line[:sample_width])
                bg_right = np.median(profile_line[-sample_width:])
                local_background = (bg_left + bg_right) / 2.0
            else:
                local_background = np.median(profile_line)
                
            signal_profile = local_background - profile_line
            signal_profile[signal_profile < 0] = 0
            
            if local_background > 0:
                signal_profile = signal_profile / local_background
            else:
                signal_profile = np.zeros_like(signal_profile)
            
            if len(signal_profile) >= 5:
                signal_profile = cv2.GaussianBlur(signal_profile.get() if hasattr(signal_profile, 'get') else signal_profile, (5, 1), 0).flatten()

            peak_idx = np.argmax(signal_profile)
            window_radius = max(2, int(bw * 0.1)) # 🌟 Scale the peak window dynamically
            start_w = max(0, peak_idx - window_radius)
            end_w = min(len(signal_profile), peak_idx + window_radius + 1)
            
            return float(np.mean(signal_profile[start_w:end_w]))

        # --- Dynamic Orientation Mapping Logic ---
        test_band = None
        control_band = None
        sorted_bands = sorted(raw_predictions, key=lambda b: b["x"])
        
        front_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') in ['Front of strip', 'front_of_strip']), None)
        back_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') in ['Back of strip', 'back_of_strip']), None)
        
        if front_of_strip_x is not None and back_of_strip_x is not None and front_of_strip_x > back_of_strip_x:
            test_band = sorted_bands[1]  
            control_band = sorted_bands[0]
        else:
            test_band = sorted_bands[0]  
            control_band = sorted_bands[1]
        
        # --- Execution of Peak Density Math ---
        t_density = calculate_high_precision_peak(test_band)
        c_density = calculate_high_precision_peak(control_band)
        
        if c_density <= 0.05:
            return AnalysisResult(
                tc_ratio=0.0,
                estimated_concentration_mg_ml=2.0,
                original_concentration_mg_ml=2.0 * dilution_factor,
                interpretation="Control line density registered as unreadable or too faint.",
                dilution_factor=dilution_factor,
                qualitative_result="INVALID"
            )
            
        computed_tc_ratio = t_density / c_density
        predicted_concentration = inverse_logistic_4pl(computed_tc_ratio, A, B, C, D)
        
        # Determine qualitative state based on structural line presence
        if len(raw_predictions) >= 2:
            qual_status = "NEGATIVE"  # Two lines detected, meaning target substance hasn't blocked the test line
        else:
            qual_status = "POSITIVE"

        if predicted_concentration < 0.0625:
            interpretation = "Below Lower Limit of Quantification (< 0.0625 mg/mL) - Trace quantities detected."
            predicted_concentration = max(0.0, predicted_concentration)
        elif computed_tc_ratio <= 0.00114 or predicted_concentration >= 2.0:
            interpretation = "Saturation Limit Reached (>= 2.000 mg/mL). High concentration."
            predicted_concentration = 2.0
            qual_status = "POSITIVE"
        else:
            interpretation = "Quantitation Successful. Within linear dynamic calibration range."
            
        final_original_calc = predicted_concentration * dilution_factor
            
        return AnalysisResult(
            tc_ratio=round(computed_tc_ratio, 4),
            estimated_concentration_mg_ml=round(predicted_concentration, 4),
            original_concentration_mg_ml=round(final_original_calc, 4),  
            interpretation=interpretation,
            dilution_factor=dilution_factor,
            qualitative_result=qual_status
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Engine failure during real-time compilation: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    from pathlib import Path
    port = int(os.environ.get("PORT", 8001))
    cert_file = Path(__file__).parent / "cert.pem"
    key_file = Path(__file__).parent / "key.pem"
    
    if cert_file.exists() and key_file.exists():
        uvicorn.run(app, host="0.0.0.0", port=port, ssl_certfile=str(cert_file), ssl_keyfile=str(key_file))
    else:
        uvicorn.run(app, host="0.0.0.0", port=port)