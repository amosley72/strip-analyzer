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

#  LOCKED PRODUCTION BAND DIMENSIONS (In Pixels)
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


def compute_tc_ratio(test_density: float, control_density: float) -> float:
    """Preserve the original T/C ratio calculation as a simple density ratio."""
    if control_density <= 0:
        return 0.0
    return test_density / control_density


def estimate_control_line_density(single_band, green_channel, img_width, img_height):
    """Use the lone detected band as a control-line proxy when only one line is found."""
    try:
        bx, by = int(single_band["x"]), int(single_band["y"])
        bw, bh = int(single_band["width"]), int(single_band["height"])
        padding = max(10, int(bw * 0.25))

        x1 = max(0, bx - (bw // 2) - padding)
        x2 = min(img_width, bx + (bw // 2) + padding)
        y1 = max(0, by - (bh // 2))
        y2 = min(img_height, by + (bh // 2))

        roi = green_channel[y1:y2, x1:x2]
        if roi.size == 0:
            return 0.0

        profile_line = np.mean(roi, axis=0)
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
        window_radius = max(2, int(bw * 0.1))
        start_w = max(0, peak_idx - window_radius)
        end_w = min(len(signal_profile), peak_idx + window_radius + 1)
        return float(np.mean(signal_profile[start_w:end_w]))
    except Exception:
        return 0.0


def build_single_band_shortcut_inputs(single_band, green_channel, img_width, img_height):
    """Return test/control values for the shortcut path where only one detected band exists."""
    control_density = estimate_control_line_density(single_band, green_channel, img_width, img_height)
    test_density = 0.0
    test_profile = np.zeros(12, dtype=float)
    control_profile = np.ones(12, dtype=float) * max(control_density, 0.0)
    return test_density, control_density, test_profile, control_profile


def build_profile_graph_payload(
    test_profile,
    control_profile,
    points: int = 12,
    test_peak_value: float | None = None,
    control_peak_value: float | None = None,
    tc_ratio: float | None = None,
) -> dict:
    """Create a normalized payload for rendering two peak graphs while preserving raw densities."""
    test_arr = np.asarray(test_profile, dtype=float).reshape(-1)
    control_arr = np.asarray(control_profile, dtype=float).reshape(-1)

    if test_arr.size == 0:
        test_arr = np.array([0.0])
    if control_arr.size == 0:
        control_arr = np.array([0.0])

    def resample_profile(values):
        values = np.clip(np.asarray(values, dtype=float), 0.0, None)
        if values.size == 1:
            return np.array([values[0], values[0]], dtype=float)
        if values.size == points:
            return values
        x_old = np.linspace(0.0, 1.0, values.size)
        x_new = np.linspace(0.0, 1.0, points)
        return np.interp(x_new, x_old, values)

    test_resampled = resample_profile(test_arr)
    control_resampled = resample_profile(control_arr)

    shared_max = max(float(np.max(test_resampled)), float(np.max(control_resampled)))
    if shared_max <= 0:
        shared_max = 1.0

    test_norm = test_resampled / shared_max
    control_norm = control_resampled / shared_max

    raw_test_peak = max(0.0, float(test_peak_value) if test_peak_value is not None else float(np.max(test_resampled)))
    raw_control_peak = max(0.0, float(control_peak_value) if control_peak_value is not None else float(np.max(control_resampled)))
    ratio_value = float(tc_ratio) if tc_ratio is not None else 0.0

    return {
        "test_profile": [float(v) for v in test_norm],
        "control_profile": [float(v) for v in control_norm],
        "test_peak_height": float(np.max(test_norm)) if test_norm.size else 0.0,
        "control_peak_height": float(np.max(control_norm)) if control_norm.size else 0.0,
        "test_line_density": raw_test_peak,
        "control_line_density": raw_control_peak,
        "test_to_control_ratio": ratio_value,
        "peak_label": ""
    }

# Structured JSON Response Contract
class AnalysisResult(BaseModel):
    tc_ratio: float = 0.0
    estimated_concentration_mg_ml: float = 0.0
    original_concentration_mg_ml: float = 0.0  
    interpretation: str = ""
    dilution_factor: int = 1                   
    qualitative_result: str = ""              #  Binary objective result ("Positive", "Negative", "Invalid")
    profile_graph: dict = {}                  # Optional visual representation of test/control peak profiles

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
        
    # 2. Optimized "Floor-First" Discovery Scan Engine
        raw_predictions = []
        all_predictions_at_chosen_confidence = []
        found_suitable_predictions = False
        
        predictions_at_floor = []
        current_all_predictions = []
        
        #  STEP A: Test the lowest acceptable floor first
        floor_conf = 10
        upload_url_floor = f"https://detect.roboflow.com/{MODEL_ENDPOINT}?api_key={API_KEY}&confidence={floor_conf}"
        
        print("\n--- STARTING IMAGE ANALYSIS ---")
        print(f"[Step A] Sending image to Roboflow at {floor_conf}% floor confidence...")
        
        try:
            with open(temp_filename, "rb") as img_file:
                response = requests.post(upload_url_floor, files={"file": img_file})
            
            print(f"[Step A] Response Code received: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                current_all_predictions = result.get("predictions", [])
                predictions_at_floor = [p for p in current_all_predictions if p.get('class') == 'Band']
                
                print(f"[Step A] Total Bands detected at floor: {len(predictions_at_floor)}")
                
                if len(predictions_at_floor) < 2:
                    print("[Step A] 🛑 Shortcut triggered! Less than 2 lines found at floor. Skipping Step B.")
                    raw_predictions = predictions_at_floor
                    all_predictions_at_chosen_confidence = current_all_predictions

                    if len(predictions_at_floor) == 1:
                        test_density, control_density, test_profile, control_profile = build_single_band_shortcut_inputs(
                            predictions_at_floor[0],
                            green_channel,
                            img_width,
                            img_height,
                        )
                        print(f"[Step A] Using single detected line as a control-line proxy with intensity {control_density:.6f}")

                        shortcut_profile_graph = build_profile_graph_payload(
                            test_profile,
                            control_profile,
                            test_peak_value=test_density,
                            control_peak_value=control_density,
                            tc_ratio=compute_tc_ratio(test_density, control_density),
                        )

                        return AnalysisResult(
                            tc_ratio=0.0,
                            estimated_concentration_mg_ml=2.0,
                            original_concentration_mg_ml=2.0 * dilution_factor,
                            interpretation="Target concentration saturated at 2 mg/mL or greater.",
                            dilution_factor=dilution_factor,
                            qualitative_result="POSITIVE",
                            profile_graph=shortcut_profile_graph,
                        )

                    return AnalysisResult(
                        tc_ratio=0.0,
                        estimated_concentration_mg_ml=2.0,
                        original_concentration_mg_ml=2.0 * dilution_factor,
                        interpretation="No test strip was identified in the photo.",
                        dilution_factor=dilution_factor,
                        qualitative_result="INVALID",
                        profile_graph=build_profile_graph_payload(
                            np.array([0.0]),
                            np.array([0.0]),
                            test_peak_value=0.0,
                            control_peak_value=0.0,
                            tc_ratio=0.0,
                        ),
                    )
                else:
                    print("[Step A] 2 or more lines found at floor. Proceeding to Step B to find highest confidence match.")
                    
        except Exception as e:
            print(f"[Step A] CRITICAL EXCEPTION: {e}")

        #  STEP B: Deep dynamic scan
        if not found_suitable_predictions:
            print("[Step B] Entering fallback loop. Scanning from 40% down to 10%...")
            test_confidences = list(range(40, 9, -10))
            for current_conf in test_confidences:
                print(f"[Step B] Checking confidence threshold: {current_conf}%...")
                
                if current_conf == 10:
                    print("[Step B] Reached 10%, reusing data collected from Step A.")
                    raw_predictions = predictions_at_floor
                    all_predictions_at_chosen_confidence = current_all_predictions
                    found_suitable_predictions = True
                    break
                    
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
                        print(f"[Step B] 🎯 Found clean 2-line break at {current_conf}% confidence. Stopping loop.")
                        raw_predictions = predictions_at_current_conf
                        all_predictions_at_chosen_confidence = current_all_predictions
                        found_suitable_predictions = True
                        break
                except Exception as e:
                    print(f"[Step B] Loop error at {current_conf}%: {e}")
                    continue
        print("--- END OF ENGINE ANALYSIS ---\n")
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
                interpretation="Target concentration saturated at 2 mg/mL or greater." if qual_status == "POSITIVE" else "No test strip was identified in the photo.",
                dilution_factor=dilution_factor,
                qualitative_result=qual_status,
                profile_graph=build_profile_graph_payload(
                    np.array([0.0]),
                    np.array([0.0]),
                    test_peak_value=0.0,
                    control_peak_value=0.0,
                    tc_ratio=0.0,
                ),
            )
            
        # 4. PROFILE PEAK MATH ENGINE 
        def calculate_high_precision_peak(box):
            bx, by = int(box["x"]), int(box["y"])
            bw, bh = int(box["width"]), int(box["height"]) #  Grab actual box dimensions
            
            # Pad the width slightly to ensure we capture surrounding background context
            padding = max(10, int(bw * 0.25))
            
            x1 = max(0, bx - (bw // 2) - padding)
            x2 = min(img_width, bx + (bw // 2) + padding)
            y1 = max(0, by - (bh // 2))
            y2 = min(img_height, by + (bh // 2))
            
            roi = green_channel[y1:y2, x1:x2]
            if roi.size == 0:
                return 0.0, np.array([0.0], dtype=float)
                
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
            
            peak_value = float(np.mean(signal_profile[start_w:end_w]))
            return peak_value, signal_profile

        # --- Dynamic Orientation Mapping Logic ---
        test_band = None
        control_band = None
        sorted_bands = sorted(raw_predictions, key=lambda b: b["x"]) #used to determine test line and control line by sorting which band is closer to the front of the strip or back of the strip.
        
        front_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') in ['Front of strip', 'front_of_strip']), None)
        back_of_strip_x = next((p['x'] for p in all_predictions_at_chosen_confidence if p.get('class') in ['Back of strip', 'back_of_strip']), None)
        
        if front_of_strip_x is not None and back_of_strip_x is not None and front_of_strip_x > back_of_strip_x:
            test_band = sorted_bands[1]  
            control_band = sorted_bands[0]
        else:
            test_band = sorted_bands[0]  
            control_band = sorted_bands[1]
        
        # --- Execution of Peak Density Math ---
        t_density, test_profile = calculate_high_precision_peak(test_band)
        c_density, control_profile = calculate_high_precision_peak(control_band)
        
        if c_density <= 0.05:
            return AnalysisResult(
                tc_ratio=0.0,
                estimated_concentration_mg_ml=2.0,
                original_concentration_mg_ml=2.0 * dilution_factor,
                interpretation="Control line density registered as unreadable or too faint.",
                dilution_factor=dilution_factor,
                qualitative_result="INVALID",
                profile_graph=build_profile_graph_payload(
                    np.array([0.0]),
                    np.array([0.0]),
                    test_peak_value=0.0,
                    control_peak_value=0.0,
                    tc_ratio=0.0,
                )
            )

        computed_tc_ratio = compute_tc_ratio(t_density, c_density)
        print(f"[Profile] test_density={t_density:.6f} control_density={c_density:.6f} tc_ratio={computed_tc_ratio:.6f}")
        predicted_concentration = inverse_logistic_4pl(computed_tc_ratio, A, B, C, D)

        # Build a lightweight graph payload for the frontend so it can draw peak profiles.
        # We normalize the profiles so their peak heights are comparable.
        profile_graph = build_profile_graph_payload(
            test_profile,
            control_profile,
            test_peak_value=t_density,
            control_peak_value=c_density,
            tc_ratio=computed_tc_ratio,
        )
        
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
            qualitative_result=qual_status,
            profile_graph=profile_graph
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Engine failure during real-time compilation: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    from pathlib import Path
    
    port = int(os.environ.get("PORT", 8001))
    cert_file = Path(__file__).parent / "cert.pem"
    key_file = Path(__file__).parent / "key.pem"
    
    # We add h11_max_incomplete_event_size to prevent Python from dropping large image streams
    if cert_file.exists() and key_file.exists():
        uvicorn.run(
            app, 
            host="0.0.0.0", 
            port=port, 
            ssl_certfile=str(cert_file), 
            ssl_keyfile=str(key_file),
            h11_max_incomplete_event_size=50000000
        )
    else:
        uvicorn.run(
            app, 
            host="0.0.0.0", 
            port=port,
            h11_max_incomplete_event_size=50000000
        )