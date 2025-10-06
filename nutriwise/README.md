 # NutriWise

 NutriWise is a cross-platform mobile application built with Flutter, designed to help users log, track, and analyze their food intake for improved nutrition and wellness. The app leverages modern AI techniques, including Convolutional Neural Networks (CNN) for image-based food recognition and Retrieval-Augmented Generation (RAG) for enhanced information retrieval and personalized recommendations.

 ## Features

 - **Barcode Scanning:** Quickly log food items by scanning barcodes using your device's camera.
 - **Image Recognition (CNN):** Identify food items from photos using a trained Convolutional Neural Network, making food logging effortless.
 - **RAG-powered Search:** Retrieve accurate and context-aware nutritional information using Retrieval-Augmented Generation, combining external data sources with generative AI.
 - **Firebase Integration:** Secure authentication, cloud storage, and real-time database for user data and food logs.
 - **Personalized Meal Summaries:** View daily and weekly summaries of your nutritional intake.
 - **Goal Setting:** Set and track nutrition goals tailored to your needs.
 - **Multi-platform Support:** Available on Android, iOS, Windows, macOS, and Linux.

 ## Technologies Used

 - **Flutter**: UI framework for building natively compiled applications for mobile, web, and desktop from a single codebase.
 - **Firebase**: Authentication, Firestore database, and cloud storage.
 - **Dart**: Programming language for Flutter development.
 - **CNN (Convolutional Neural Networks)**: Used for image-based food recognition.
 - **RAG (Retrieval-Augmented Generation)**: Used for advanced search and personalized recommendations.
 - **Barcode Scan2**: For barcode scanning functionality.
 - **HTTP**: For API requests and data retrieval.

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

 ### Usage
 - **Log Food:** Use barcode scanning or image recognition to log food items.
 - **View Summaries:** Check your meal summaries and progress towards goals.
 - **Set Goals:** Personalize your nutrition targets.

 ## AI Components

 ### Convolutional Neural Networks (CNN)
 NutriWise uses CNNs to analyze food images and automatically identify food items, streamlining the logging process. This feature is powered by a custom-trained model integrated into the app.

 ### Retrieval-Augmented Generation (RAG)
 RAG combines external nutritional databases with generative AI to provide users with accurate, context-aware information and recommendations. This ensures that food data and suggestions are both relevant and up-to-date.

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

 ## Contributing
 Contributions are welcome! Please open issues or submit pull requests for improvements and bug fixes.

 ## License
 This project is licensed under the MIT License.

 ## Contact
 For questions or support, please contact [AlvinNathey](https://github.com/AlvinNathey).
