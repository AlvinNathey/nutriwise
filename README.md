# NutriWise

NutriWise is a cross-platform mobile application built with Flutter, designed to help users log, track, and analyze their food intake for improved nutrition and wellness. The app leverages modern AI techniques, including Convolutional Neural Networks (CNN) for image-based food recognition and Retrieval-Augmented Generation (RAG) for enhanced information retrieval and personalized recommendations.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Architecture](#architecture)
- [Technologies Used](#technologies-used)
- [Getting Started](#getting-started)
- [Usage Guide](#usage-guide)
- [AI Components](#ai-components)
- [Extending NutriWise](#extending-nutriwise)
- [Troubleshooting](#troubleshooting)
- [Folder Structure](#folder-structure)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Features

- **Barcode Scanning:** Instantly log packaged food items by scanning barcodes.
- **Image Recognition (CNN):** Identify food items from photos using a custom-trained Convolutional Neural Network.
- **OCR Nutrition Extraction:** Scan nutrition labels and automatically extract calories, macros, and serving size.
- **RAG-powered Search:** Retrieve accurate and context-aware nutritional information using Retrieval-Augmented Generation, combining external data sources with generative AI.
- **Personalized Meal Summaries:** View daily, weekly, and historical summaries of your nutritional intake.
- **Goal Setting:** Set and track nutrition goals tailored to your needs.
- **Custom Quantity Entry:** Enter precise food quantities for accurate tracking.
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
-->

---

## Architecture

NutriWise is structured for scalability and maintainability:

- **Flutter UI:** Modular screens and widgets for food logging, summaries, and profile management.
- **Service Layer:** Handles API calls, barcode/image recognition, and Firebase interactions.
- **AI Integration:** CNN model for food image classification; RAG pipeline for nutritional data retrieval.
- **State Management:** Uses Provider or Riverpod for reactive UI updates.
- **Data Storage:** Firebase Firestore for cloud data, local SQLite for offline support.

---

## Technologies Used

- **Flutter**: UI framework for building natively compiled applications for mobile, web, and desktop from a single codebase.
- **Dart**: Programming language for Flutter development.
- **Firebase**: Authentication, Firestore database, and cloud storage.
- **CNN (Convolutional Neural Networks)**: Used for image-based food recognition.
- **RAG (Retrieval-Augmented Generation)**: Used for advanced search and personalized recommendations.
- **Google ML Kit**: OCR for nutrition label scanning.
- **Barcode Scan2**: For barcode scanning functionality.
- **HTTP**: For API requests and data retrieval.

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

- **Log Food:** Use barcode scanning, image recognition, or manual entry to log food items.
- **Scan Nutrition Label:** Use the camera to scan and extract nutrition facts via OCR.
- **Custom Quantity:** Tap the quantity field to enter a custom value (e.g., 237.5g).
- **View Summaries:** Check your meal summaries and progress towards goals.
- **Set Goals:** Personalize your nutrition targets in the profile section.
- **Offline Logging:** Log foods even when offline; syncs when reconnected.

---

## AI Components

### Convolutional Neural Networks (CNN)

NutriWise uses CNNs to analyze food images and automatically identify food items, streamlining the logging process. This feature is powered by a custom-trained model integrated into the app.

### Retrieval-Augmented Generation (RAG)

RAG combines external nutritional databases with generative AI to provide users with accurate, context-aware information and recommendations. This ensures that food data and suggestions are both relevant and up-to-date.

### OCR Nutrition Extraction

Google ML Kit OCR is used to scan nutrition labels and extract calories, macros, and serving sizes, making manual entry faster and more accurate.

---

## Extending NutriWise

- **Add New Food Recognition Models:** Replace or retrain the CNN model for improved accuracy.
- **Integrate More Data Sources:** Extend RAG to use additional nutrition databases.
- **Custom Analytics:** Add charts, trends, and export features for deeper insights.
- **Localization:** Add support for more languages and regional food databases.

---

## Troubleshooting

- **Barcode not recognized:** Ensure the barcode is clear and well-lit; try manual entry if needed.
- **OCR errors:** Retake the photo with better lighting and focus.
- **Firebase issues:** Check your Firebase configuration and internet connection.
- **App crashes:** Run `flutter doctor` and ensure all dependencies are installed.

---

## Folder Structure

```
lib/
  main.dart                # App entry point
  log_food.dart            # Food logging logic
  meal_summary.dart        # Meal summary screen
  profile.dart             # User profile
  auth/                    # Authentication screens and logic
  home/                    # Home screen
  services/                # Service classes (e.g., auth, food recognition)
assets/                    # Images and icons
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
