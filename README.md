# NutriWise

NutriWise is a cross-platform mobile application built with Flutter, designed to help users log, track, analyze, and export their food intake for improved nutrition and wellness. The app leverages modern AI techniques, including Convolutional Neural Networks (CNN) for image-based food recognition, Retrieval-Augmented Generation (RAG) for enhanced information retrieval, and OCR for nutrition label extraction. NutriWise supports detailed reporting, exportable PDF summaries, and robust history tracking.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Architecture](#architecture)
- [Technologies Used](#technologies-used)
- [Getting Started](#getting-started)
- [Usage Guide](#usage-guide)
- [AI Components](#ai-components)
- [Exportable Reports](#exportable-reports)
- [Food Recognition & Logging](#food-recognition--logging)
- [Meal History & Timeline](#meal-history--timeline)
- [Nutrition Trends & Analytics](#nutrition-trends--analytics)
- [Extending NutriWise](#extending-nutriwise)
- [Troubleshooting](#troubleshooting)
- [Folder Structure](#folder-structure)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)
- [CNN Models & Results](#cnn-models--results)
- [Model Summary Table](#model-summary-table)

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
<!-- 
![Home Screen](assets/screenshots/home.png)
![Barcode Scan](assets/screenshots/barcode.png)
![Meal Summary](assets/screenshots/meal_summary.png)
![Food Recognition](assets/screenshots/food_recognition.png)
![PDF Report](assets/screenshots/pdf_report.png)
-->

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

- **Flutter:** UI framework for building natively compiled applications for mobile, web, and desktop from a single codebase.
- **Dart:** Programming language for Flutter development.
- **Firebase:** Authentication, Firestore database, and cloud storage.
- **CNN (Convolutional Neural Networks):** Used for image-based food recognition and segmentation.
- **RAG (Retrieval-Augmented Generation):** Used for advanced search and personalized recommendations.
- **Google ML Kit:** OCR for nutrition label scanning.
- **Barcode Scan2:** For barcode scanning functionality.
- **HTTP:** For API requests and data retrieval.
- **TFLite Flutter:** For running TensorFlow Lite models on-device.
- **PDF & Printing:** For generating and exporting nutrition reports.

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
   - Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) to the respective platform folders.
   - Update `firebase_options.dart` as needed.
4. **Run the app:**
   ```sh
   flutter run
   ```

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

```text
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

## Contributing

Contributions are welcome! Please open issues or submit pull requests for improvements and bug fixes.

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

\*With test-time augmentation.

---
