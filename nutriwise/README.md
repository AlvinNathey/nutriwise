# NutriWise

NutriWise is a cross-platform mobile application built with Flutter, designed to help users log, track, analyze, and export their food intake for improved nutrition and wellness. The app leverages modern AI techniques, including Convolutional Neural Networks (CNN) for image-based food recognition, Retrieval-Augmented Generation (RAG) for enhanced information retrieval, and OCR for nutrition label extraction. NutriWise supports detailed reporting, exportable PDF summaries, and robust history tracking.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [System Requirements](#system-requirements)
- [Architecture](#architecture)
- [Technologies Used](#technologies-used)
- [Dependencies](#dependencies)
- [Getting Started](#getting-started)
- [Firebase Setup](#firebase-setup)
- [Configuration](#configuration)
- [Build Instructions](#build-instructions)
- [Usage Guide](#usage-guide)
- [AI Components](#ai-components)
- [Model Training Details](#model-training-details)
- [External APIs](#external-apis)
- [Exportable Reports](#exportable-reports)
- [Food Recognition & Logging](#food-recognition--logging)
- [Meal History & Timeline](#meal-history--timeline)
- [Nutrition Trends & Analytics](#nutrition-trends--analytics)
- [Performance & Optimization](#performance--optimization)
- [Security & Privacy](#security--privacy)
- [Testing](#testing)
- [Development Setup](#development-setup)
- [Deployment](#deployment)
- [Limitations & Known Issues](#limitations--known-issues)
- [Extending NutriWise](#extending-nutriwise)
- [Troubleshooting](#troubleshooting)
- [Folder Structure](#folder-structure)
- [Code Examples](#code-examples)
- [Contributing](#contributing)
- [Version History](#version-history)
- [Acknowledgments](#acknowledgments)
- [References](#references)
- [License](#license)
- [Contact](#contact)

---

## Features

- **Barcode Scanning:** Instantly log packaged food items by scanning barcodes.
- **Image Recognition (CNN):** Identify food items from photos using custom-trained models (Kenyan Food, Food-101, UEC UNet).
- **Food Segmentation:** Detect and segment multiple food regions in a single image, with per-region classification and nutrition estimation.
- **OCR Nutrition Extraction:** Scan nutrition labels and automatically extract calories, macros, and serving size.
- **RAG-powered Search:** Retrieve accurate and context-aware nutritional information using Retrieval-Augmented Generation, combining external data sources with generative AI.
- **Manual Logging:** Add foods manually with custom quantities and nutrition details.
- **Meal Logging:** Log entire meals with multiple foods, portion size estimation, and image upload.
- **Edit & Modify Foods:** Edit detected foods, adjust portion sizes, merge/split regions, and update nutrition data.
- **Personalized Meal Summaries:** View daily, weekly, monthly, and historical summaries of your nutritional intake.
- **Goal Setting:** Set and track nutrition goals tailored to your needs (calories, carbs, protein, fat).
- **Weight Tracking:** Log and visualize weight changes over time.
- **Nutrition Trends:** Analyze intake and macro trends with interactive charts.
- **Exportable Reports:** Generate and download detailed PDF nutrition reports for any period (day, week, month, custom range).
- **History Timeline:** View all logged foods and meals in a grouped timeline, with editing capabilities.
- **Multi-platform Support:** Available on Android, iOS, Windows, macOS, and Linux.
- **Firebase Integration:** Secure authentication, cloud storage, and real-time database for user data and food logs.
- **Offline Mode:** Log foods and view summaries even without an internet connection.

---

## Screenshots

<!-- Add screenshots here if available -->
<!-- Example:
![Home Screen](assets/screenshots/home.png)
![Barcode Scan](assets/screenshots/barcode.png)
![Meal Summary](assets/screenshots/meal_summary.png)
![Food Recognition](assets/screenshots/food_recognition.png)
![PDF Report](assets/screenshots/pdf_report.png)
-->

---

## System Requirements

### Minimum Requirements

**Mobile (Android/iOS):**
- Android: API level 21 (Android 5.0) or higher
- iOS: iOS 12.0 or higher
- RAM: 2GB minimum, 4GB recommended
- Storage: 100MB for app + 200MB for models
- Camera: Required for food recognition features
- Internet: Required for initial setup and cloud sync (offline mode available)

**Desktop (Windows/macOS/Linux):**
- Windows: Windows 10 or higher
- macOS: macOS 10.14 or higher
- Linux: Ubuntu 18.04 or equivalent
- RAM: 4GB minimum, 8GB recommended
- Storage: 200MB for app + 300MB for models

### Recommended Requirements

- **RAM:** 4GB or more for optimal performance
- **Storage:** 500MB free space for app, models, and cached data
- **Internet:** Stable connection for cloud sync and API calls
- **Camera:** High-resolution camera (8MP+) for better food recognition accuracy

---

## Architecture

NutriWise is structured for scalability and maintainability:

- **Flutter UI:** Modular screens and widgets for food logging, summaries, history, and profile management.
- **Service Layer:** Handles API calls, barcode/image recognition, nutrition API integration, and Firebase interactions.
- **AI Integration:** CNN models for food image classification and segmentation; RAG pipeline for nutritional data retrieval.
- **State Management:** Uses Provider or Riverpod for reactive UI updates.
- **Data Storage:** Firebase Firestore for cloud data, Firebase Storage for images, local SQLite for offline support.
- **Reporting:** PDF generation using `pdf` and `printing` packages, with customizable report periods and content.

---

## Technologies Used

- **Flutter**: UI framework for building natively compiled applications for mobile, web, and desktop from a single codebase.
- **Dart**: Programming language for Flutter development.
- **Firebase**: Authentication, Firestore database, and cloud storage.
- **CNN (Convolutional Neural Networks)**: Used for image-based food recognition and segmentation.
- **RAG (Retrieval-Augmented Generation)**: Used for advanced search and personalized recommendations.
- **Google ML Kit**: OCR for nutrition label scanning.
- **Barcode Scan2**: For barcode scanning functionality.
- **HTTP**: For API requests and data retrieval.
- **TFLite Flutter**: For running TensorFlow Lite models on-device.
- **PDF & Printing**: For generating and exporting nutrition reports.

---

## Dependencies

### Core Dependencies

```yaml
# UI & Framework
flutter: SDK
cupertino_icons: ^1.0.8

# Firebase Services
firebase_core: ^4.0.0
cloud_firestore: ^6.0.0
firebase_auth: ^6.0.1
firebase_storage: 13.0.4

# AI & Machine Learning
tflite_flutter: ^0.12.1          # TensorFlow Lite for on-device inference
google_mlkit_text_recognition: ^0.15.0  # OCR for nutrition labels

# Image Processing
image_picker: ^1.0.4              # Camera and gallery access
image: ^4.5.4                     # Image manipulation and processing

# Barcode Scanning
barcode_scan2: ^4.2.0             # Barcode scanning functionality

# Networking & APIs
http: ^1.5.0                      # HTTP client for API calls

# Data Visualization
fl_chart: ^0.63.0                 # Interactive charts and graphs

# PDF Generation
pdf: ^3.10.4                      # PDF document creation
printing: ^5.11.1                 # PDF printing and sharing

# Utilities
intl: ^0.20.2                     # Internationalization and date formatting
permission_handler: ^12.0.1       # Runtime permission management
device_info_plus: ^12.1.0         # Device information
local_auth: ^2.1.6                # Biometric authentication
```

### Development Dependencies

```yaml
flutter_test: SDK                 # Unit and widget testing
flutter_lints: ^6.0.0             # Linting rules
flutter_launcher_icons: ^0.14.4   # App icon generation
```

### Model Files (Assets)

- `uec_unet.tflite` - Segmentation model (full precision)
- `uec_unet_int8.tflite` - Segmentation model (quantized INT8)
- `food101.tflite` - Food-101 classification model
- `kenyanfood.tflite` - Kenyan food classification model

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Dart SDK](https://dart.dev/get-dart)
- Firebase project setup (see below)

### Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/AlvinNathey/nutriwise.git
   cd nutriwise
   ```
2. **Install dependencies:**
   ```sh
   flutter pub get
   ```
3. **Configure Firebase:**
   - See [Firebase Setup](#firebase-setup) section for detailed instructions.
4. **Run the app:**
   ```sh
   flutter run
   ```

---

## Firebase Setup

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" and follow the setup wizard
3. Enable Google Analytics (optional but recommended)

### Step 2: Add Android App

1. In Firebase Console, click "Add app" → Android
2. Register app with package name: `com.example.nutriwise` (or your package name)
3. Download `google-services.json`
4. Place it in `android/app/` directory
5. Add to `android/build.gradle`:
   ```gradle
   dependencies {
       classpath 'com.google.gms:google-services:4.3.15'
   }
   ```
6. Add to `android/app/build.gradle`:
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

### Step 3: Add iOS App

1. In Firebase Console, click "Add app" → iOS
2. Register app with bundle ID (from Xcode project)
3. Download `GoogleService-Info.plist`
4. Add to `ios/Runner/` directory via Xcode
5. Update `ios/Podfile` if needed

### Step 4: Enable Firebase Services

**Authentication:**
- Go to Authentication → Sign-in method
- Enable Email/Password authentication

**Firestore Database:**
- Go to Firestore Database → Create database
- Start in test mode (update security rules for production)
- Set location (choose closest to your users)

**Storage:**
- Go to Storage → Get started
- Start in test mode (update security rules for production)

### Step 5: Configure Firestore Security Rules

Update `firestore.rules`:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      match /meals/{mealId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      match /barcodes/{barcodeId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      match /weight_entries/{entryId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

### Step 6: Configure Storage Security Rules

Update `storage.rules`:
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Step 7: Generate Firebase Options

Run FlutterFire CLI:
```sh
flutter pub global activate flutterfire_cli
flutterfire configure
```

This generates `lib/firebase_options.dart` automatically.

---

## Configuration

### Environment Variables

No environment variables are required. All configuration is handled through:
- Firebase configuration files (`google-services.json`, `GoogleService-Info.plist`)
- `lib/firebase_options.dart` (auto-generated)

### App Configuration

**Model Selection:**
- Models are loaded from `assets/` folder
- Quantized models (INT8) are used by default for better performance
- Full precision models available as fallback

**API Endpoints:**
- Open Food Facts: `https://world.openfoodfacts.org/api/v0/product/`
- USDA Database: Integrated via HTTP requests
- Barcode Lookup: Multiple fallback APIs configured in code

**Performance Settings:**
- Image preprocessing: Resize to 224x224 before inference
- Model caching: Enabled by default
- API response caching: 24-hour cache for nutrition data

---

## Build Instructions

### Android

**Debug Build:**
```sh
flutter build apk --debug
```

**Release Build:**
```sh
flutter build apk --release
```

**App Bundle (for Play Store):**
```sh
flutter build appbundle --release
```

**Requirements:**
- Android SDK (API 21+)
- Java Development Kit (JDK 11+)
- Android Studio or command-line tools

### iOS

**Debug Build:**
```sh
flutter build ios --debug
```

**Release Build:**
```sh
flutter build ios --release
```

**Requirements:**
- macOS with Xcode installed
- iOS 12.0+ deployment target
- Valid Apple Developer account (for release builds)
- CocoaPods installed

**Additional Steps:**
```sh
cd ios
pod install
cd ..
```

### Windows

**Build:**
```sh
flutter build windows --release
```

**Requirements:**
- Windows 10 SDK
- Visual Studio 2019 or later with C++ desktop development tools

### macOS

**Build:**
```sh
flutter build macos --release
```

**Requirements:**
- macOS 10.14+
- Xcode with command-line tools

### Linux

**Build:**
```sh
flutter build linux --release
```

**Requirements:**
- Linux development tools
- GTK 3.0 development libraries

---

## Usage Guide

### Logging Food

- **Barcode Scan:** Tap the barcode icon and scan a packaged food item. Nutrition data is fetched automatically.
- **Image Recognition:** Tap the camera icon, take a photo of your meal, and let NutriWise detect and segment foods. Review and edit detected foods, adjust portion sizes, and log the meal.
- **Manual Entry:** Tap "Add Food" to manually enter food name, quantity, and nutrition details.

### Editing & Modifying Foods

- **Edit Detected Foods:** Tap on a detected food region to edit its name, portion size, and nutrition data.
- **Merge/Split Foods:** Merge multiple regions (e.g., rice + sauce) or split a region into components (e.g., mixed plate).
- **Portion Size Estimation:** Use plate size presets or adjust grams manually for accurate nutrition calculation.

### Viewing Summaries & Trends

- **Records Page:** View monthly calendar with meal types, daily calorie intake, and meal counters.
- **Nutrients Page:** Analyze weight trends, intake trends, meal distribution, and macro breakdowns with interactive charts.
- **History Timeline:** Browse all logged foods and meals, grouped by day, with editing options.

### Exporting Reports

- **Download PDF Report:** Tap the download icon in the Records page, select a period (month, week, custom), preview the report, and export as PDF.
- **Report Content:** Includes summary, macronutrient breakdown, meal distribution, weight tracking, daily calories, top meals, and detailed meal tables.

### Goal Setting & Weight Tracking

- **Set Nutrition Goals:** Personalize your daily targets for calories, carbs, protein, and fat in the profile section.
- **Log Weight:** Update your weight regularly and visualize progress in the Nutrients page.

### Offline Logging

- Log foods and meals even when offline. Data syncs automatically when reconnected.

---

## AI Components

### Convolutional Neural Networks (CNN)

NutriWise uses CNNs for food image analysis:
- **Segmentation Model (UEC UNet):** Detects and segments multiple food regions in a meal photo.
- **Classification Models (Kenyan Food, Food-101):** Identifies food types for each region, with per-region predictions.

### Retrieval-Augmented Generation (RAG)

RAG combines external nutritional databases (Open Food Facts, USDA) with generative AI to provide users with accurate, context-aware information and recommendations. This ensures food data and suggestions are both relevant and up-to-date.

### OCR Nutrition Extraction

Google ML Kit OCR is used to scan nutrition labels and extract calories, macros, and serving sizes, making manual entry faster and more accurate.

---

## Model Training Details

### Dataset Information

**Food-101 Dataset:**
- **Source:** [Food-101 Dataset](https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/)
- **Size:** 101,000 images
- **Categories:** 101 food classes
- **Split:** 750 training images + 250 test images per class
- **Preprocessing:** Resize to 224x224, normalization, data augmentation (rotation, flip, color jitter)

**Kenyan Food Dataset:**
- **Source:** Custom dataset
- **Size:** ~13,000 images
- **Categories:** 13 Kenyan food classes (bhaji, chapati, githeri, kachumbari, kukuchoma, mandazi, matoke, mukimo, nyama choma, pilau, rice, sukuma wiki, ugali)
- **Collection:** Manual collection and annotation
- **Augmentation:** Heavy augmentation due to smaller dataset size

**UEC Food-256 Dataset (for Segmentation):**
- **Source:** [UEC Food-256](http://foodcam.mobi/)
- **Size:** 31,395 images
- **Categories:** 256 food categories
- **Annotations:** Pixel-level segmentation masks
- **Preprocessing:** Resize to 256x256, normalize, augment with rotation and scaling

### Training Configuration

**Food-101 Model (ResNet50):**
- **Framework:** TensorFlow/Keras
- **Optimizer:** Adam (learning rate: 0.001, decay: 1e-6)
- **Loss Function:** Categorical Crossentropy
- **Batch Size:** 32
- **Epochs:** 100
- **Early Stopping:** Patience of 10 epochs
- **Hardware:** GPU training (NVIDIA GPU recommended)
- **Training Time:** ~24-48 hours on single GPU

**Kenyan Food Model (Ultimate ConvNex):**
- **Framework:** PyTorch
- **Optimizer:** AdamW (learning rate: 0.0001)
- **Loss Function:** CrossEntropyLoss with label smoothing (0.1)
- **Batch Size:** 16 (smaller due to dataset size)
- **Epochs:** 250
- **Test-Time Augmentation:** Enabled (improves accuracy by ~2%)
- **Training Time:** ~12-24 hours on single GPU

**UEC UNet (MobileNetV2):**
- **Framework:** TensorFlow
- **Architecture:** UNet with MobileNetV2 encoder
- **Optimizer:** Adam (learning rate: 0.0001)
- **Loss Function:** Combined Dice Loss + Binary Crossentropy
- **Batch Size:** 8
- **Epochs:** 80
- **Input Size:** 256x256
- **Output:** Binary segmentation masks
- **Training Time:** ~36-48 hours on single GPU

### Model Conversion to TFLite

**Quantization:**
- Post-training quantization to INT8 for mobile deployment
- Reduces model size by ~75% with minimal accuracy loss
- Quantization-aware training considered for future improvements

**Conversion Process:**
```python
# Example conversion script
converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.int8]
tflite_model = converter.convert()
```

**Model Sizes:**
- `food101.tflite`: ~45MB (quantized)
- `kenyanfood.tflite`: ~12MB (quantized)
- `uec_unet.tflite`: ~8MB (quantized)
- `uec_unet_int8.tflite`: ~2MB (INT8 quantized)

---

## External APIs

### Open Food Facts API

**Endpoint:** `https://world.openfoodfacts.org/api/v0/product/{barcode}.json`

**Usage:**
- Primary source for barcode-based nutrition data
- Free and open-source database
- Returns comprehensive nutrition information including calories, macros, vitamins, and allergens

**Rate Limits:**
- No official rate limit, but recommended: < 1 request/second
- Caching implemented to reduce API calls

**Response Format:**
```json
{
  "status": 1,
  "product": {
    "product_name": "Product Name",
    "nutriments": {
      "energy-kcal_100g": 250,
      "carbohydrates_100g": 30,
      "proteins_100g": 10,
      "fat_100g": 5
    }
  }
}
```

### USDA Food Data Central API

**Endpoint:** `https://api.nal.usda.gov/fdc/v1/foods/search`

**Usage:**
- Fallback nutrition database
- Comprehensive food composition data
- Requires API key (free tier available)

**Rate Limits:**
- Free tier: 1,200 requests/day
- Paid tiers available for higher limits

### Barcode Lookup Services

**Multiple Fallback APIs:**
1. **Barcode List** (`barcode-list.com`)
2. **UPC Item DB** (`upcitemdb.com`)
3. **Google Search** (web scraping fallback)
4. **Kenyan Retail Stores** (site-specific searches)

**Strategy:**
- Try APIs sequentially until successful
- 10-second timeout per API
- Graceful degradation to manual entry

---

## Performance & Optimization

### Model Inference Performance

**On-Device Performance (Android, mid-range device):**
- Segmentation: ~800-1200ms per image
- Classification (single model): ~200-400ms per region
- Combined pipeline: ~2-3 seconds for multi-food meal

**Optimization Techniques:**
- Model quantization (INT8) reduces inference time by ~40%
- Image preprocessing (resize before inference)
- Lazy model loading (load on first use)
- Result caching for repeated queries

### App Performance Metrics

**Startup Time:**
- Cold start: ~2-3 seconds
- Warm start: ~1 second

**Memory Usage:**
- Base app: ~80-120MB
- With models loaded: ~150-200MB
- Peak usage (during inference): ~250-300MB

**Battery Impact:**
- Minimal background usage
- Camera usage: ~5-10% battery per 10 photos
- Cloud sync: Negligible impact

### Optimization Strategies

1. **Image Processing:**
   - Resize images to 1024x1024 max before processing
   - Compress images before upload to Firebase Storage
   - Cache processed images locally

2. **Network Optimization:**
   - Implement request batching for Firestore
   - Use Firestore offline persistence
   - Cache API responses locally (24-hour TTL)

3. **UI Optimization:**
   - Lazy loading for lists
   - Image caching with `cached_network_image`
   - Debounce user inputs to reduce unnecessary API calls

4. **Model Optimization:**
   - Use quantized models by default
   - Load models asynchronously
   - Unload models when not in use (future enhancement)

---

## Security & Privacy

### Data Security

**Authentication:**
- Firebase Authentication with email/password
- Email verification required
- Secure password hashing (handled by Firebase)

**Data Encryption:**
- All data in transit encrypted via HTTPS/TLS
- Firestore data encrypted at rest
- Firebase Storage files encrypted

**User Data:**
- All user data stored in user-specific Firestore collections
- Access controlled via security rules
- No cross-user data access

### Privacy Policy

**Data Collection:**
- User profile information (name, email, weight, height, goals)
- Food logs and meal images
- Weight tracking history
- App usage analytics (Firebase Analytics)

**Data Usage:**
- Data used solely for app functionality
- No data sold to third parties
- No advertising data sharing

**Data Storage:**
- User data stored in Firebase (Google Cloud)
- Images stored in Firebase Storage
- Local caching for offline functionality

**User Rights:**
- Users can delete their account and all associated data
- Export data via PDF reports
- Request data deletion by contacting support

**Third-Party Services:**
- Firebase (Google) - Authentication and data storage
- Open Food Facts - Nutrition database (public API)
- USDA - Nutrition database (public API)
- Google ML Kit - On-device OCR (no data sent to Google)

### Compliance

- **GDPR:** User data can be exported and deleted
- **COPPA:** App not intended for users under 13
- **HIPAA:** Not a medical device; consult healthcare providers for medical advice

---

## Testing

### Unit Tests

Run unit tests:
```sh
flutter test
```

**Test Coverage:**
- Service layer functions
- Utility functions
- Data model validation
- Calculation functions (BMR, TDEE, macros)

### Widget Tests

Test UI components:
```sh
flutter test test/widget_test.dart
```

**Tested Components:**
- Authentication screens
- Food logging widgets
- Chart rendering
- Form validation

### Integration Tests

**Manual Testing Checklist:**
- [ ] Food recognition accuracy
- [ ] Barcode scanning
- [ ] OCR extraction
- [ ] Firebase sync
- [ ] Offline functionality
- [ ] PDF generation
- [ ] Cross-platform compatibility

### Performance Testing

**Benchmarks:**
- Model inference time
- App startup time
- Memory usage
- Battery consumption
- Network request efficiency

---

## Development Setup

### IDE Configuration

**Recommended IDEs:**
- **Android Studio** (with Flutter plugin)
- **VS Code** (with Flutter extension)
- **IntelliJ IDEA** (with Flutter plugin)

**Required Plugins:**
- Flutter
- Dart
- Firebase (optional, for debugging)

### Code Style

**Linting:**
- Uses `flutter_lints` package
- Configuration in `analysis_options.yaml`
- Run linter: `flutter analyze`

**Code Formatting:**
- Automatic formatting: `dart format .`
- Format on save enabled in IDE

### Git Workflow

**Branching Strategy:**
- `main` - Production-ready code
- `develop` - Development branch
- `feature/*` - Feature branches
- `bugfix/*` - Bug fix branches

**Commit Messages:**
- Follow conventional commits format
- Prefix with type: `feat:`, `fix:`, `docs:`, `refactor:`, etc.

### Debugging

**Flutter DevTools:**
```sh
flutter pub global activate devtools
flutter pub global run devtools
```

**Firebase Debugging:**
- Use Firebase Console for data inspection
- Enable debug logging in Firebase
- Monitor performance in Firebase Performance

---

## Deployment

### Android (Google Play Store)

**Prerequisites:**
- Google Play Developer account ($25 one-time fee)
- App signing key generated
- Privacy policy URL

**Steps:**
1. Build release app bundle:
   ```sh
   flutter build appbundle --release
   ```
2. Create app listing in Play Console
3. Upload app bundle
4. Complete store listing (screenshots, description, etc.)
5. Submit for review

**App Signing:**
- Generate keystore:
  ```sh
  keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```
- Configure in `android/key.properties`
- Update `android/app/build.gradle`

### iOS (App Store)

**Prerequisites:**
- Apple Developer account ($99/year)
- Xcode installed on macOS
- App Store Connect account

**Steps:**
1. Build iOS app:
   ```sh
   flutter build ios --release
   ```
2. Archive in Xcode
3. Upload to App Store Connect
4. Complete app metadata
5. Submit for review

**Requirements:**
- App Store guidelines compliance
- Privacy policy URL
- App icons and screenshots
- Age rating information

### Desktop Distribution

**Windows:**
- Build installer or portable executable
- Distribute via website or Microsoft Store

**macOS:**
- Build DMG or App Store distribution
- Code signing required for distribution

**Linux:**
- Build AppImage, Snap, or DEB package
- Distribute via package repositories

---

## Limitations & Known Issues

### Current Limitations

1. **Food Recognition:**
   - Accuracy depends on image quality and lighting
   - Limited to 114 food categories (101 + 13)
   - May struggle with very similar-looking foods
   - Portion estimation is approximate (±20% accuracy)

2. **Barcode Scanning:**
   - Requires products in Open Food Facts database
   - Some regional products may not be found
   - Barcode quality affects recognition

3. **OCR Extraction:**
   - Requires clear, well-lit nutrition labels
   - May misread handwritten or damaged labels
   - Language support limited to English labels

4. **Platform Support:**
   - Camera features require physical camera (not available on all devices)
   - Some features optimized for mobile (desktop experience may vary)

5. **Offline Functionality:**
   - Models work offline
   - Nutrition API lookups require internet
   - Cloud sync requires connection

### Known Issues

1. **Model Loading:**
   - First-time model loading can be slow (5-10 seconds)
   - Large model files increase app size
   - **Workaround:** Models load asynchronously, show loading indicator

2. **Memory Usage:**
   - High memory usage during image processing
   - **Workaround:** Process images in batches, clear cache regularly

3. **Firebase Quotas:**
   - Free tier has read/write limits
   - **Workaround:** Implement efficient queries, use caching

4. **Multi-food Segmentation:**
   - May miss small food items
   - Overlapping foods can be challenging
   - **Workaround:** User can manually add missed foods

### Future Improvements

- Expand food category coverage
- Improve portion estimation accuracy
- Add depth estimation for better portion calculation
- Implement active learning from user corrections
- Add more regional food databases
- Improve offline nutrition database

---

## Exportable Reports

- **Customizable Periods:** Export nutrition reports for any period (month, week, custom date range).
- **Preview & Download:** Preview report content before exporting. Download as PDF for sharing or record-keeping.
- **Report Sections:**
  - User summary and period details
  - Total and average calories/macros
  - Meal distribution (Breakfast, Lunch, Dinner, Snack)
  - Weight tracking and progress
  - Daily calorie intake table
  - Top meals by calories
  - Detailed meal and food tables

---

## Food Recognition & Logging

- **Multi-region Segmentation:** Detects multiple foods in a single image, with real bounding boxes and masks.
- **Per-region Classification:** Assigns food names and nutrition data to each region using multiple models.
- **Nutrition API Integration:** Fetches nutrition data from Open Food Facts and USDA databases.
- **Portion Size Estimation:** Estimates grams based on bounding box area, food density, and plate size.
- **Edit & Review:** Users can review, edit, merge, split, or add foods before saving a meal.

---

## Meal History & Timeline

- **Unified Timeline:** Combines barcode logs and meal logs into a single, grouped timeline.
- **Sectioned View:** Groups logs by Today, Yesterday, Last Week, etc.
- **Editing:** Edit barcode logs and review meal details directly from the timeline.

---

## Nutrition Trends & Analytics

- **Weight Trend:** Visualize weight changes over time with interactive charts.
- **Intake Trend:** Analyze daily and weekly calorie intake against goals.
- **Meal Trend:** View meal distribution and macro breakdowns for any week.
- **Nutrition Trend:** Pie charts for carbs, protein, and fat trends.

---

## Extending NutriWise

- **Add New Food Recognition Models:** Replace or retrain CNN models for improved accuracy.
- **Integrate More Data Sources:** Extend RAG to use additional nutrition databases.
- **Custom Analytics:** Add charts, trends, and export features for deeper insights.
- **Localization:** Add support for more languages and regional food databases.
- **Advanced Plate Detection:** Improve portion estimation with computer vision.

---

## Troubleshooting

- **Barcode not recognized:** Ensure the barcode is clear and well-lit; try manual entry if needed.
- **OCR errors:** Retake the photo with better lighting and focus.
- **Firebase issues:** Check your Firebase configuration and internet connection.
- **App crashes:** Run `flutter doctor` and ensure all dependencies are installed.
- **Model loading errors:** Ensure all TFLite models are present in the assets folder.

---

## Folder Structure

```
lib/
  main.dart                # App entry point
  log_food.dart            # Food logging logic
  meal_summary.dart        # Meal summary screen
  profile.dart             # User profile
  records.dart             # Records and reporting
  history.dart             # Timeline/history
  food/
    food_recognition.dart  # Food recognition and segmentation
    edit_food_log.dart     # Edit barcode logs
    edit_food_page.dart    # Edit segmented foods
  auth/                    # Authentication screens and logic
  home/                    # Home screen
  services/                # Service classes (e.g., auth, food recognition)
assets/                    # Images, icons, TFLite models
android/, ios/, web/, ...  # Platform-specific files
```

---

## Code Examples

### Food Recognition Workflow

```dart
// Load segmentation model
final interpreter = await Interpreter.fromAsset('assets/uec_unet.tflite');

// Preprocess image
final inputImage = img.decodeImage(imageBytes);
final resized = img.copyResize(inputImage!, width: 256, height: 256);
final inputBuffer = preprocessImage(resized);

// Run segmentation
var outputBuffer = List.filled(256 * 256, 0).reshape([1, 256, 256, 1]);
interpreter.run(inputBuffer, outputBuffer);

// Process segmentation mask
final regions = extractFoodRegions(outputBuffer[0]);
```

### Firestore Data Structure

```dart
// User document structure
{
  'name': 'John Doe',
  'email': 'john@example.com',
  'weight': 75.5,
  'height': 175,
  'calories': 2000,
  'carbG': 250,
  'proteinG': 150,
  'fatG': 67,
  'createdAt': Timestamp.now()
}

// Meal document structure
{
  'mealType': 'Lunch',
  'date': '2024-01-15',
  'time': '12:30 PM',
  'totalCalories': 650,
  'foodItems': [
    {
      'foodName': 'Rice',
      'gramsAmount': 200,
      'calories': 260,
      'carbs': 56,
      'protein': 5,
      'fat': 0.4
    }
  ],
  'originalImageUrl': 'gs://...',
  'createdAt': Timestamp.now()
}
```

### Barcode Lookup with Fallback

```dart
Future<String> lookupBarcode(String barcode) async {
  // Try multiple APIs sequentially
  final apis = [
    _lookupOpenFoodFacts,
    _lookupUPCItemDB,
    _lookupBarcodeList,
  ];
  
  for (var api in apis) {
    try {
      final result = await api(barcode).timeout(Duration(seconds: 10));
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (e) {
      continue; // Try next API
    }
  }
  
  return 'Unknown Product';
}
```

---

## Contributing

We welcome contributions! Please follow these guidelines:

### How to Contribute

1. **Fork the repository**
2. **Create a feature branch:**
   ```sh
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes:**
   - Follow the existing code style
   - Add tests for new features
   - Update documentation
4. **Commit your changes:**
   ```sh
   git commit -m "feat: add new feature"
   ```
5. **Push to your fork:**
   ```sh
   git push origin feature/your-feature-name
   ```
6. **Create a Pull Request**

### Contribution Guidelines

**Code Style:**
- Follow Dart/Flutter style guide
- Run `flutter analyze` before committing
- Format code with `dart format`

**Pull Request Requirements:**
- Clear description of changes
- Reference related issues
- Include tests if applicable
- Update documentation if needed

**Areas for Contribution:**
- Bug fixes
- New features
- Performance improvements
- Documentation updates
- Test coverage
- UI/UX improvements
- Additional food recognition models
- Localization support

### Reporting Issues

**Bug Reports:**
- Use the issue template
- Include steps to reproduce
- Provide device/platform information
- Attach screenshots if applicable

**Feature Requests:**
- Describe the feature clearly
- Explain the use case
- Consider implementation complexity

---

## Version History

### Version 1.0.0 (Current)

**Initial Release:**
- ✅ Food recognition with CNN models
- ✅ Multi-food segmentation
- ✅ Barcode scanning
- ✅ OCR nutrition extraction
- ✅ Analytics and reporting
- ✅ PDF export
- ✅ Goal setting and tracking
- ✅ Weight tracking
- ✅ Cross-platform support

**Model Performance:**
- Food-101: 78.87% Top-1 accuracy
- Kenyan Food: 79.51% Top-1 accuracy
- UEC UNet: 78% pixel accuracy, 64% Mean IoU

**Known Issues:**
- First-time model loading can be slow
- Portion estimation accuracy ±20%

---

## Acknowledgments

### Datasets

- **Food-101 Dataset:** [ETH Zurich](https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/)
- **UEC Food-256 Dataset:** [UEC Food-256](http://foodcam.mobi/)
- **Open Food Facts:** [Open Food Facts](https://world.openfoodfacts.org/) - Open-source food database
- **USDA Food Data Central:** [USDA](https://fdc.nal.usda.gov/) - Comprehensive nutrition database

### Libraries & Frameworks

- **Flutter Team** - Cross-platform framework
- **Firebase** - Backend infrastructure
- **TensorFlow** - Machine learning framework
- **Google ML Kit** - On-device ML capabilities

### Inspiration

- Inspired by the need for accessible nutrition tracking
- Built to support diverse food cultures and regional cuisines
- Designed with privacy and offline-first principles

---

## References

### Research Papers

1. **Food-101 Dataset:**
   - Bossard, L., Guillaumin, M., & Van Gool, L. (2014). "Food-101 – Mining Discriminative Components with Random Forests." European Conference on Computer Vision.

2. **UEC Food-256:**
   - Matsuda, Y., Hoashi, H., & Yanai, K. (2012). "Recognition of Multiple-Food Images by Detecting Candidate Regions." IEEE International Conference on Multimedia and Expo.

3. **UNet Architecture:**
   - Ronneberger, O., Fischer, P., & Brox, T. (2015). "U-Net: Convolutional Networks for Biomedical Image Segmentation." MICCAI.

4. **ResNet Architecture:**
   - He, K., Zhang, X., Ren, S., & Sun, J. (2016). "Deep Residual Learning for Image Recognition." CVPR.

### Documentation

- [Flutter Documentation](https://flutter.dev/docs)
- [Firebase Documentation](https://firebase.google.com/docs)
- [TensorFlow Lite Guide](https://www.tensorflow.org/lite)
- [Google ML Kit Documentation](https://developers.google.com/ml-kit)

### APIs

- [Open Food Facts API](https://world.openfoodfacts.org/data)
- [USDA Food Data Central API](https://fdc.nal.usda.gov/api-guide.html)

---

## License

This project is licensed under the MIT License.

---

## Contact

For questions or support, please contact [AlvinNathey](https://github.com/AlvinNathey).

---

## CNN Models & Results

NutriWise uses several deep learning models for food recognition and segmentation. Below are the details and results for each:

### FOOD-101 (ResNet50)

- **Algorithm:** ResNet50
- **Training:** 100 epochs
- **Top-1 Accuracy:** 78.87%
- **Top-3 Accuracy:** 90.45%
- **Top-5 Accuracy:** 93.55%
- **F1 Score (Macro):** 0.7892
- **F1 Score (Weighted):** 0.7892

<details>
<summary>Per-class metrics (sample)</summary>

| Class                | Precision | Recall | F1-score | Support |
|----------------------|-----------|--------|----------|---------|
| apple_pie            | 0.5875    | 0.5640 | 0.5755   | 250     |
| baklava              | 0.7992    | 0.8440 | 0.8210   | 250     |
| bibimbap             | 0.9407    | 0.8880 | 0.9136   | 250     |
| ...                  | ...       | ...    | ...      | ...     |

</details>

---

### Kenya Food 13 (Ultimate ConvNex)

- **Algorithm:** Ultimate ConvNex
- **Training:** 250 epochs
- **Standard Evaluation:**
  - Top-1 Accuracy: 77.67%
  - Top-3 Accuracy: 93.74%
  - Top-5 Accuracy: 96.56%
  - F1 Score (Macro): 0.7362
  - F1 Score (Weighted): 0.7707
- **With Test-Time Augmentation:**
  - Top-1 Accuracy: 79.51%
  - Top-3 Accuracy: 94.11%
  - Top-5 Accuracy: 97.18%
  - F1 Score (Macro): 0.7552
  - F1 Score (Weighted): 0.7899

<details>
<summary>Per-class F1 scores</summary>

| Class         | F1-score |
|---------------|----------|
| bhaji         | 0.8323   |
| chapati       | 0.8969   |
| githeri       | 0.9391   |
| kachumbari    | 0.5833   |
| kukuchoma     | 0.2941   |
| mandazi       | 0.8987   |
| ...           | ...      |

</details>

---

### UEC UNet (MobilenetV2)

- **Algorithm:** MobilenetV2 (UNet architecture)
- **Training:** 80 epochs
- **Best Pixel Accuracy:** 78%
- **Best Mean IoU:** 62%
- **Sample Training Log:**

| Epoch | Loss    | Mean IoU | Pixel Accuracy |
|-------|---------|----------|---------------|
| 0     | 0.33    | 0.009    | 0.49          |
| 10    | 0.11    | 0.16     | 0.69          |
| 20    | 0.07    | 0.43     | 0.82          |
| 40    | 0.02    | 0.82     | 0.94          |
| 59    | 0.016   | 0.87     | 0.95          |

---

## Model Summary Table

| Model         | Algorithm         | Epochs | Top-1 Acc | Top-3 Acc | Top-5 Acc | F1 Macro | F1 Weighted | Pixel Acc | Mean IoU |
|---------------|------------------|--------|-----------|-----------|-----------|----------|-------------|-----------|----------|
| Food-101      | ResNet50         | 100    | 78.87%    | 90.45%    | 93.55%    | 0.7892   | 0.7892      | -         | -        |
| Kenya Food 13 | Ultimate ConvNex | 250    | 79.51%*   | 94.11%*   | 97.18%*   | 0.7552*  | 0.7899*     | -         | -        |
| UEC UNet      | MobilenetV2      | 80     | -         | -         | -         | -        | -           | 78%       | 64%      |

*With test-time augmentation.

---

## Additional Resources

### Documentation Files

- **API Documentation:** See inline code comments for detailed API documentation
- **Architecture Diagrams:** Available in project documentation (if created)
- **User Guide:** Comprehensive usage instructions in [Usage Guide](#usage-guide) section

### Support Channels

- **GitHub Issues:** For bug reports and feature requests
- **Email:** Contact via GitHub profile
- **Documentation:** This README and inline code documentation

### Community

- Star the repository if you find it useful
- Share feedback and suggestions
- Report bugs to help improve the project

### Related Projects

- Similar nutrition tracking apps (for comparison)
- Food recognition research projects
- Open-source nutrition databases

---

## Quick Start Checklist

For new developers setting up the project:

- [ ] Install Flutter SDK (3.8.1+)
- [ ] Install Dart SDK
- [ ] Clone repository
- [ ] Run `flutter pub get`
- [ ] Set up Firebase project
- [ ] Add `google-services.json` (Android)
- [ ] Add `GoogleService-Info.plist` (iOS)
- [ ] Run `flutterfire configure`
- [ ] Verify all TFLite models in `assets/` folder
- [ ] Run `flutter doctor` to check setup
- [ ] Test app with `flutter run`
- [ ] Review [Usage Guide](#usage-guide) for app features

---
