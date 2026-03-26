# NutriWise: File Reference Guide for Presentation
## Quick Reference - Which Files to Mention for Each Section

---

## **1. INTRODUCTION & PROBLEM STATEMENT**

**Files to Reference:**
- `README.md` - Project overview and problem statement
- `lib/main.dart` - Entry point showing app initialization

**Key Points:**
- README explains the motivation and features
- Main.dart shows Firebase initialization and app structure

---

## **2. PROJECT OVERVIEW & OBJECTIVES**

**Files to Reference:**
- `pubspec.yaml` - Dependencies showing technology stack
- `lib/auth/auth_wrapper.dart` - Authentication flow
- `lib/bottom_nav.dart` - Navigation structure

**Key Points:**
- pubspec.yaml lists all dependencies (Flutter, Firebase, TFLite, ML Kit)
- Auth wrapper shows secure user authentication
- Bottom nav demonstrates app navigation structure

---

## **3. TECHNICAL ARCHITECTURE**

**Files to Reference:**
- `lib/services/auth_services.dart` - Service layer pattern
- `lib/firebase_options.dart` - Firebase configuration
- `lib/home/home_screen.dart` - Main UI component
- `assets/` folder - TFLite models location

**Key Points:**
- Services folder shows separation of concerns
- Firebase options demonstrate cloud integration
- Home screen shows UI architecture
- Assets folder contains AI models (food101.tflite, kenyanfood.tflite, uec_unet.tflite)

---

## **4. AI/ML COMPONENTS (CORE INNOVATION)**

### **Segmentation Model (UEC UNet)**
**Files to Reference:**
- `lib/food/food_recognition.dart` (Lines 1-500) - Model loading and segmentation
- `assets/uec_unet.tflite` - Segmentation model file
- `assets/uec_unet_int8.tflite` - Quantized version

**Key Code Sections:**
- Model loading logic
- Segmentation inference
- Connected component analysis
- Mask processing

### **Classification Models**
**Files to Reference:**
- `lib/food/food_recognition.dart` (Lines 500-1500) - Classification logic
- `assets/food101.tflite` - Food-101 model
- `assets/kenyanfood.tflite` - Kenyan food model

**Key Code Sections:**
- Multi-model inference
- Ensemble prediction combining
- Confidence thresholding
- Per-region classification

### **Portion Size Estimation**
**Files to Reference:**
- `lib/food/food_recognition.dart` (Lines 2000-3000) - Portion estimation algorithms
- `lib/food/food_model.dart` - Food data models

**Key Code Sections:**
- Bounding box area calculation
- Plate size detection
- Density factor application
- Gram conversion logic

### **Nutrition API Integration**
**Files to Reference:**
- `lib/food/food_recognition.dart` (Lines 3000-4000) - API calls
- `lib/food/log_food.dart` - Barcode lookup with multiple APIs

**Key Code Sections:**
- Open Food Facts API integration
- USDA database queries
- Multi-source barcode lookup
- Fallback mechanisms

---

## **5. KEY FEATURES DEMO**

### **Feature 1: Multiple Food Logging Methods**
**Files to Reference:**
- `lib/food/log_food.dart` - Main logging interface
- `lib/food/log_food.dart` (Lines 120-260) - Camera/Gallery/Barcode handlers
- `lib/food/log_food.dart` (Lines 263-569) - Enhanced barcode lookup

**Key Code Sections:**
- Image picker integration
- Barcode scanner integration
- Multiple API fallback chain
- Permission handling

### **Feature 2: AI Food Recognition**
**Files to Reference:**
- `lib/food/food_recognition.dart` - Complete recognition pipeline
- `lib/food/meal_summary.dart` - Meal review and editing

**Key Code Sections:**
- Image preprocessing
- Model inference pipeline
- Result visualization
- User editing interface

### **Feature 3: Analytics & Reporting**
**Files to Reference:**
- `lib/records.dart` (4,106 lines) - Comprehensive analytics
- `lib/records.dart` (Lines 1-200) - Data fetching
- `lib/records.dart` (Lines 2000-4106) - PDF generation

**Key Code Sections:**
- Calendar view with meal indicators
- Chart generation (fl_chart)
- PDF report creation
- Trend analysis

### **Feature 4: OCR Nutrition Extraction**
**Files to Reference:**
- `lib/food/meal_summary.dart` (Lines 1-150) - OCR integration
- `lib/food/meal_summary.dart` (Lines 200-400) - Text recognition

**Key Code Sections:**
- Google ML Kit integration
- Text extraction from images
- Nutrition value parsing
- Manual correction interface

### **Feature 5: Goal Setting & Personalization**
**Files to Reference:**
- `lib/profile.dart` (2,465 lines) - Profile and goal management
- `lib/auth/goal_setup_screen.dart` - Initial goal setup
- `lib/home/home_screen.dart` (Lines 144-243) - BMR/TDEE calculation

**Key Code Sections:**
- BMR calculation formulas
- TDEE with activity factors
- Macro distribution logic
- Goal adjustment algorithms

---

## **6. IMPLEMENTATION HIGHLIGHTS**

### **Data Management**
**Files to Reference:**
- `lib/services/auth_services.dart` - User data management
- `lib/home/home_screen.dart` (Lines 481-582) - Meal fetching from Firestore
- `lib/history.dart` - Timeline and history management

**Key Code Sections:**
- Firestore collection structure
- Real-time data synchronization
- Offline support logic
- Query optimization

### **State Management**
**Files to Reference:**
- `lib/home/home_screen.dart` - StatefulWidget pattern
- `lib/food/food_recognition.dart` - Complex state management

**Key Code Sections:**
- State initialization
- Async data loading
- UI updates on data changes

### **Error Handling**
**Files to Reference:**
- `lib/food/log_food.dart` (Lines 570-634) - Permission error handling
- `lib/food/food_recognition.dart` - Model loading error handling

**Key Code Sections:**
- Try-catch blocks
- User-friendly error messages
- Fallback mechanisms
- Retry logic

### **Performance Optimizations**
**Files to Reference:**
- `lib/food/food_recognition.dart` - Model loading and caching
- `lib/food/food_recognition.dart` - Image preprocessing

**Key Code Sections:**
- Lazy model loading
- Image resizing before inference
- Result caching
- Efficient data structures

---

## **7. RESULTS & FUTURE WORK**

**Files to Reference:**
- `README.md` (Lines 278-367) - Model performance metrics
- `lib/food/food_recognition.dart` - Areas for improvement

**Key Metrics from README:**
- Food-101: 78.87% Top-1, 90.45% Top-3
- Kenyan Food: 79.51% Top-1 (with TTA)
- UEC UNet: 78% Pixel Accuracy, 64% Mean IoU

---

## **CODE COMPLEXITY METRICS**

**Largest/Most Complex Files:**
1. `lib/food/food_recognition.dart` - **5,502 lines** (Core AI logic)
2. `lib/records.dart` - **4,106 lines** (Analytics & PDF generation)
3. `lib/profile.dart` - **2,465 lines** (User profile & goals)
4. `lib/history.dart` - **524 lines** (Timeline management)
5. `lib/home/home_screen.dart` - **1,447 lines** (Main dashboard)

**Total Project Size:**
- Approximately **14,000+ lines** of Dart code
- Multiple TFLite models (assets folder)
- Firebase configuration
- Platform-specific code (Android, iOS)

---

## **PRESENTATION FLOW - FILE REFERENCES**

### **Opening (Problem Statement)**
→ Show `README.md` overview
→ Reference `lib/main.dart` for app structure

### **Architecture Overview**
→ Show `pubspec.yaml` for tech stack
→ Reference `lib/services/` for service layer
→ Show `assets/` folder for models

### **AI Components (Main Focus)**
→ Deep dive into `lib/food/food_recognition.dart`
  - Segmentation: Lines 200-800
  - Classification: Lines 800-2000
  - Portion estimation: Lines 2000-3000
  - API integration: Lines 3000-4000

### **Features Demo**
→ `lib/food/log_food.dart` - Logging methods
→ `lib/food/food_recognition.dart` - AI workflow
→ `lib/records.dart` - Analytics
→ `lib/food/meal_summary.dart` - OCR
→ `lib/profile.dart` - Goals

### **Implementation Details**
→ `lib/services/auth_services.dart` - Data management
→ `lib/home/home_screen.dart` - State management
→ Error handling throughout codebase

### **Results**
→ `README.md` - Performance metrics
→ Model files in `assets/` folder

---

## **DEMO SCRIPT WITH FILE REFERENCES**

### **Demo 1: Food Recognition**
1. Open `lib/food/log_food.dart` - Show logging options
2. Navigate to `lib/food/food_recognition.dart` - Show AI pipeline
3. Reference model files in `assets/` folder
4. Show result in `lib/food/meal_summary.dart`

### **Demo 2: Analytics**
1. Show `lib/home/home_screen.dart` - Daily tracking
2. Navigate to `lib/records.dart` - Monthly calendar
3. Show PDF generation code
4. Display generated report

### **Demo 3: Goal Setting**
1. Show `lib/profile.dart` - Profile screen
2. Reference `lib/home/home_screen.dart` (BMR calculation)
3. Show goal tracking in home screen

---

## **KEY CODE SNIPPETS TO HIGHLIGHT**

### **1. Model Loading (food_recognition.dart)**
```dart
// Show how models are loaded
final interpreter = Interpreter.fromAsset('assets/uec_unet.tflite');
```

### **2. Segmentation Inference**
```dart
// Show segmentation process
interpreter.run(inputBuffer, outputBuffer);
```

### **3. Multi-Model Classification**
```dart
// Show ensemble approach
final food101Pred = await _classifyWithFood101(croppedImage);
final kenyanPred = await _classifyWithKenyanFood(croppedImage);
```

### **4. Portion Estimation**
```dart
// Show portion calculation
final area = boundingBox.width * boundingBox.height;
final grams = estimateGramsFromArea(area, foodDensity);
```

### **5. Firestore Integration**
```dart
// Show data storage
await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('meals')
    .add(mealData);
```

---

## **QUESTIONS PREPARATION**

**If asked about code organization:**
→ Reference folder structure in `lib/`
→ Explain separation of concerns
→ Show service layer pattern

**If asked about model performance:**
→ Reference `README.md` metrics
→ Explain model selection rationale
→ Discuss quantization benefits

**If asked about scalability:**
→ Reference Firebase architecture
→ Show Firestore collection structure
→ Explain offline support

**If asked about accuracy:**
→ Reference ensemble approach in `food_recognition.dart`
→ Show fallback mechanisms
→ Explain user correction interface

---

This guide helps you quickly reference the right files during your presentation!

