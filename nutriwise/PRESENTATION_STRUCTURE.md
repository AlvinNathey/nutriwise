# NutriWise: 15-Minute Presentation Structure
## Final Year Informatics & Computer Science Project

---

## **TIMING BREAKDOWN (15 minutes total)**

| Section | Time | Cumulative |
|---------|------|------------|
| 1. Introduction & Problem Statement | 1.5 min | 1.5 min |
| 2. Project Overview & Objectives | 1 min | 2.5 min |
| 3. Technical Architecture | 2 min | 4.5 min |
| 4. AI/ML Components (Core Innovation) | 4 min | 8.5 min |
| 5. Key Features Demo | 3 min | 11.5 min |
| 6. Implementation Highlights | 2 min | 13.5 min |
| 7. Results & Future Work | 1.5 min | 15 min |

---

## **DETAILED PRESENTATION STRUCTURE**

### **1. INTRODUCTION & PROBLEM STATEMENT (1.5 minutes)**

#### Slide 1: Title Slide
- **Title**: "NutriWise: AI-Powered Nutrition Tracking Application"
- **Subtitle**: "Leveraging Deep Learning for Automated Food Recognition and Nutrition Analysis"
- **Your Name & Institution**
- **Date**

#### Slide 2: Problem Statement
**Key Points:**
- Manual food logging is time-consuming and error-prone
- Existing apps lack accurate food recognition for diverse cuisines (especially regional foods)
- Need for intelligent portion size estimation
- Integration of multiple data sources for comprehensive nutrition tracking

**What to Say:**
> "Traditional nutrition tracking apps require extensive manual input, making them impractical for daily use. Users struggle with accurately identifying foods, especially in multi-item meals, and estimating portion sizes. This project addresses these challenges through AI-powered food recognition and segmentation."

---

### **2. PROJECT OVERVIEW & OBJECTIVES (1 minute)**

#### Slide 3: Project Overview
**Key Points:**
- Cross-platform mobile application (Android, iOS, Windows, macOS, Linux)
- Real-time food recognition using computer vision
- Automated nutrition tracking and analytics
- Personalized goal setting and progress monitoring

**What to Say:**
> "NutriWise is a comprehensive nutrition tracking application that uses deep learning models to automatically identify and segment foods from images, extract nutritional information, and provide detailed analytics to help users achieve their health goals."

#### Slide 4: Core Objectives
**Technical Objectives:**
1. Implement multi-model CNN architecture for food classification
2. Develop semantic segmentation for multi-food meal detection
3. Integrate OCR for nutrition label extraction
4. Build scalable cloud-based data management system
5. Create comprehensive analytics and reporting features

**User Objectives:**
- Reduce manual input time by 80%
- Achieve >75% accuracy in food recognition
- Support offline functionality
- Provide exportable nutrition reports

---

### **3. TECHNICAL ARCHITECTURE (2 minutes)**

#### Slide 5: Technology Stack
**Frontend:**
- Flutter/Dart (Cross-platform UI framework)
- State Management (Provider/Riverpod pattern)

**Backend & Services:**
- Firebase Authentication (User management)
- Cloud Firestore (NoSQL database)
- Firebase Storage (Image storage)
- HTTP Client (API integration)

**AI/ML:**
- TensorFlow Lite (On-device inference)
- Google ML Kit (OCR for nutrition labels)
- Custom CNN models (Food classification & segmentation)

**External APIs:**
- Open Food Facts API
- USDA Food Database
- Multiple barcode lookup services

**What to Say:**
> "The application follows a modular architecture with clear separation between UI, business logic, and data layers. We leverage Firebase for scalable cloud infrastructure and TensorFlow Lite for efficient on-device AI inference, ensuring privacy and performance."

#### Slide 6: System Architecture Diagram
**Visual Elements:**
```
┌─────────────────────────────────────────┐
│         Flutter UI Layer                 │
│  (Home, Food Logging, Analytics)        │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      Service Layer                      │
│  (Auth, Food Recognition, API Calls)     │
└──────────────┬──────────────────────────┘
               │
    ┌──────────┴──────────┐
    │                      │
┌───▼────┐          ┌─────▼─────┐
│Firebase│          │  AI Models │
│(Cloud) │          │ (TFLite)  │
└────────┘          └───────────┘
```

**What to Say:**
> "The architecture is designed for scalability and maintainability. The UI layer communicates with service classes that handle business logic, API calls, and model inference. Data is synchronized with Firebase for cloud backup and multi-device access."

#### Slide 7: Folder Structure Overview
**Key Directories:**
- `lib/auth/` - Authentication screens and logic
- `lib/food/` - Food recognition, logging, and meal management
- `lib/home/` - Main dashboard and daily tracking
- `lib/services/` - Business logic and API integrations
- `assets/` - TFLite models and images

**What to Say:**
> "The codebase is organized into logical modules. The auth folder handles user authentication and onboarding. The food folder contains our core AI recognition logic. Services abstract API calls and data operations, making the codebase maintainable and testable."

---

### **4. AI/ML COMPONENTS - CORE INNOVATION (4 minutes)**

#### Slide 8: AI Pipeline Overview
**Three-Stage Process:**
1. **Segmentation** → Identify food regions in image
2. **Classification** → Recognize food types per region
3. **Nutrition Retrieval** → Fetch nutritional data from APIs

**What to Say:**
> "Our AI pipeline processes food images through three stages. First, semantic segmentation identifies distinct food regions. Then, each region is classified using multiple CNN models. Finally, nutritional information is retrieved from external databases."

#### Slide 9: Model 1 - Food Segmentation (UEC UNet)
**Technical Details:**
- **Architecture**: MobileNetV2-based UNet
- **Purpose**: Semantic segmentation of food regions
- **Training**: 80 epochs on UEC Food-256 dataset
- **Performance Metrics:**
  - Pixel Accuracy: **78%**
  - Mean IoU: **64%**
  - Best Loss: 0.016

**Key Innovation:**
- Detects multiple foods in a single image
- Generates binary masks for each food region
- Calculates real bounding boxes from mask data

**What to Say:**
> "The segmentation model uses a UNet architecture with MobileNetV2 encoder, optimized for mobile deployment. It achieves 78% pixel accuracy, successfully identifying multiple food items in complex meal images. The model outputs binary masks that we use to calculate precise bounding boxes and estimate portion sizes."

#### Slide 10: Model 2 - Food Classification (Food-101)
**Technical Details:**
- **Architecture**: ResNet50
- **Dataset**: Food-101 (101 food categories)
- **Training**: 100 epochs
- **Performance Metrics:**
  - Top-1 Accuracy: **78.87%**
  - Top-3 Accuracy: **90.45%**
  - Top-5 Accuracy: **93.55%**
  - F1 Score (Macro): **0.7892**

**What to Say:**
> "The Food-101 model uses ResNet50 architecture, trained on 101 diverse food categories. With 78.87% top-1 accuracy, it provides reliable classification for international cuisines. The high top-3 accuracy of 90.45% ensures we can provide alternative suggestions when the primary prediction is uncertain."

#### Slide 11: Model 3 - Regional Food Classification (Kenyan Food 13)
**Technical Details:**
- **Architecture**: Ultimate ConvNex
- **Dataset**: 13 Kenyan food categories
- **Training**: 250 epochs with test-time augmentation
- **Performance Metrics:**
  - Top-1 Accuracy: **79.51%** (with TTA)
  - Top-3 Accuracy: **94.11%**
  - Top-5 Accuracy: **97.18%**
  - F1 Score (Weighted): **0.7899**

**Key Innovation:**
- Specialized for regional cuisine recognition
- Test-time augmentation improves accuracy
- High performance on culturally specific foods

**What to Say:**
> "Recognizing the limitation of generic models on regional foods, we trained a specialized model for Kenyan cuisine. Using Ultimate ConvNex architecture and test-time augmentation, we achieved 79.51% accuracy on 13 local food categories. This demonstrates the importance of domain-specific models in global applications."

#### Slide 12: Multi-Model Ensemble Strategy
**Approach:**
- Run both classification models on each segmented region
- Combine predictions using confidence-weighted voting
- Fallback to nutrition APIs if models are uncertain
- Per-region classification ensures accurate multi-food meal analysis

**What to Say:**
> "We employ an ensemble approach, running both classification models on each food region. Predictions are combined using confidence scores, and we fallback to external nutrition APIs when model confidence is low. This ensures robust performance across diverse food types."

#### Slide 13: Portion Size Estimation Algorithm
**Method:**
1. Calculate bounding box area from segmentation mask
2. Estimate real-world dimensions using plate size detection
3. Apply food density factors (from nutrition databases)
4. Convert to grams using volume-to-mass relationships

**What to Say:**
> "Portion estimation combines computer vision with nutritional science. We calculate the area of each segmented region, estimate real-world dimensions by detecting plate size, and apply food-specific density factors to convert volume to mass. This provides accurate gram estimates for nutrition calculation."

---

### **5. KEY FEATURES DEMO (3 minutes)**

#### Slide 14: Feature 1 - Multiple Food Logging Methods
**Three Input Methods:**
1. **Barcode Scanning** → Instant product lookup
2. **Image Recognition** → AI-powered food detection
3. **Manual Entry** → Custom food addition

**What to Say:**
> "Users can log food through three methods. Barcode scanning provides instant product identification. Image recognition uses our AI models to detect and segment multiple foods. Manual entry allows custom foods or corrections."

#### Slide 15: Feature 2 - AI Food Recognition Workflow
**Process Flow:**
1. User takes/selects photo
2. Segmentation model identifies food regions
3. Each region classified by ensemble models
4. Nutrition data fetched from APIs
5. User reviews and edits before saving
6. Portion sizes adjusted with visual feedback

**What to Say:**
> "The AI recognition workflow is seamless. After image capture, segmentation identifies food regions in real-time. Each region is classified, and nutrition data is automatically retrieved. Users can review, edit, merge, or split regions before saving, ensuring accuracy."

#### Slide 16: Feature 3 - Comprehensive Analytics
**Analytics Features:**
- Daily/Weekly/Monthly calorie tracking
- Macro breakdown (carbs, protein, fat)
- Meal distribution charts
- Weight trend visualization
- Goal progress indicators
- Exportable PDF reports

**What to Say:**
> "The analytics dashboard provides comprehensive insights. Users can view daily calorie intake, macro breakdowns, meal distribution patterns, and weight trends. All data is visualized through interactive charts, and detailed reports can be exported as PDFs for sharing with healthcare providers."

#### Slide 17: Feature 4 - OCR Nutrition Label Extraction
**Technology:**
- Google ML Kit Text Recognition
- Automatic extraction of calories, macros, serving size
- Manual correction interface
- Integration with food logging workflow

**What to Say:**
> "For packaged foods, we use OCR to extract nutrition information directly from labels. Google ML Kit recognizes text, and our parsing algorithms extract calories, macros, and serving sizes. Users can review and correct extracted values before logging."

#### Slide 18: Feature 5 - Goal Setting & Personalization
**Personalization Features:**
- BMR/TDEE calculation based on user profile
- Customizable nutrition goals (calories, macros)
- Activity level adjustments
- Weight goal tracking (lose/maintain/gain)
- Automatic macro distribution based on diet type

**What to Say:**
> "The app calculates personalized nutrition goals using BMR and TDEE formulas, considering user's age, gender, weight, height, and activity level. Goals adapt automatically when weight is updated, and macro distribution adjusts based on selected diet type."

---

### **6. IMPLEMENTATION HIGHLIGHTS (2 minutes)**

#### Slide 19: Code Architecture - Key Files
**Critical Components:**

**`lib/food/food_recognition.dart` (5,502 lines)**
- Core AI inference pipeline
- Segmentation and classification logic
- Portion size estimation
- Image processing utilities

**`lib/home/home_screen.dart`**
- Main dashboard with weekly calendar
- Real-time calorie tracking
- Macro progress indicators
- Meal list display

**`lib/records.dart` (4,106 lines)**
- Analytics and chart generation
- PDF report generation
- Monthly calendar with meal indicators
- Trend analysis

**`lib/food/log_food.dart`**
- Multi-source barcode lookup
- Image picker integration
- Navigation to recognition/summary screens

**`lib/services/auth_services.dart`**
- Firebase authentication wrapper
- User data management
- Weight entry tracking

**What to Say:**
> "The implementation spans over 10,000 lines of Dart code. The food recognition module is the most complex, handling model loading, inference, and post-processing. The records page generates comprehensive analytics and PDF reports. All components follow Flutter best practices for state management and performance."

#### Slide 20: Data Management Strategy
**Firebase Collections:**
- `users/{uid}` - User profile and goals
- `users/{uid}/meals` - AI-detected meal logs
- `users/{uid}/barcodes` - Barcode-scanned items
- `users/{uid}/weight_entries` - Weight history

**Features:**
- Real-time synchronization
- Offline support with local caching
- Efficient querying with date-based indexes
- Image storage in Firebase Storage

**What to Say:**
> "We use Firebase Firestore for cloud data storage, organized into user-specific collections. Meal logs and barcode scans are stored separately for efficient querying. Images are stored in Firebase Storage with optimized compression. The app supports offline logging with automatic sync when connectivity is restored."

#### Slide 21: Performance Optimizations
**Key Optimizations:**
- Model quantization (INT8) for faster inference
- Image preprocessing (resize to 224x224 before inference)
- Lazy loading of models (load on first use)
- Caching of nutrition API responses
- Efficient Firestore queries with composite indexes

**What to Say:**
> "Performance is critical for mobile apps. We use quantized INT8 models for faster inference, preprocess images to optimal sizes, and implement caching strategies. Models are loaded lazily to reduce initial app startup time. Firestore queries use composite indexes for efficient data retrieval."

#### Slide 22: Error Handling & Edge Cases
**Robustness Features:**
- Graceful degradation when models fail
- Multiple fallback APIs for barcode lookup
- User correction interfaces for AI errors
- Network error handling with retry logic
- Model loading retry mechanism (3 attempts)

**What to Say:**
> "The app handles various edge cases gracefully. If AI models fail, we fallback to manual entry. Barcode lookup tries multiple APIs sequentially. Users can always correct AI predictions. Network errors trigger retry logic, and model loading failures are handled with multiple retry attempts."

---

### **7. RESULTS & FUTURE WORK (1.5 minutes)**

#### Slide 23: Project Achievements
**Technical Achievements:**
✅ Three trained CNN models with >75% accuracy
✅ Multi-food segmentation in single images
✅ Cross-platform deployment (5 platforms)
✅ Real-time on-device inference
✅ Comprehensive analytics and reporting

**User Experience Achievements:**
✅ Reduced manual input by ~80%
✅ Support for 114+ food categories (101 + 13)
✅ Offline functionality
✅ Exportable PDF reports
✅ Personalized goal tracking

**What to Say:**
> "The project successfully demonstrates the integration of deep learning into a practical mobile application. We achieved our accuracy targets, deployed across multiple platforms, and created a user-friendly interface that significantly reduces manual input. The app supports over 114 food categories and provides comprehensive analytics."

#### Slide 24: Model Performance Summary
**Performance Table:**
| Model | Architecture | Accuracy | Use Case |
|-------|--------------|----------|----------|
| UEC UNet | MobileNetV2 | 78% Pixel, 64% IoU | Segmentation |
| Food-101 | ResNet50 | 78.87% Top-1 | Classification |
| Kenyan Food | ConvNex | 79.51% Top-1 | Regional Foods |

**What to Say:**
> "All three models meet or exceed our 75% accuracy target. The segmentation model successfully identifies food regions, while the classification models provide reliable food identification. The specialized Kenyan food model demonstrates the value of domain-specific training."

#### Slide 25: Challenges & Solutions
**Key Challenges:**
1. **Multi-food segmentation** → Solved with UNet architecture
2. **Portion size estimation** → Combined CV with density factors
3. **Model size for mobile** → Used quantization and MobileNetV2
4. **Regional food recognition** → Trained specialized model
5. **Real-time performance** → Optimized preprocessing and caching

**What to Say:**
> "Several challenges emerged during development. Multi-food segmentation required careful model selection and post-processing. Portion estimation needed a hybrid approach combining computer vision with nutritional science. Model optimization was crucial for mobile deployment, leading us to use quantized models and efficient architectures."

#### Slide 26: Future Enhancements
**Planned Improvements:**
1. **Expanded Food Databases**
   - Train models on more regional cuisines
   - Integrate additional nutrition APIs

2. **Advanced Features**
   - Meal recommendations based on goals
   - Social features (sharing meals, challenges)
   - Integration with fitness trackers

3. **Model Improvements**
   - Fine-tune models on user-corrected data
   - Implement active learning pipeline
   - Add more sophisticated portion estimation

4. **Performance**
   - Further model optimization
   - Implement model versioning
   - Add A/B testing for model variants

**What to Say:**
> "Future work includes expanding food databases, adding meal recommendations, and implementing social features. We plan to fine-tune models using user feedback through active learning. Performance optimizations and model versioning will ensure the app continues to improve."

#### Slide 27: Conclusion
**Key Takeaways:**
- Successfully integrated deep learning into mobile nutrition tracking
- Achieved >75% accuracy across all models
- Created scalable, cross-platform solution
- Demonstrated practical application of computer vision and AI

**Impact:**
- Makes nutrition tracking accessible and convenient
- Reduces barriers to healthy eating
- Provides data-driven insights for users

**What to Say:**
> "NutriWise demonstrates the practical application of deep learning in mobile health applications. By combining multiple AI models with comprehensive analytics, we've created a tool that makes nutrition tracking accessible and convenient. The project showcases skills in mobile development, machine learning, cloud computing, and user experience design."

#### Slide 28: Questions & Thank You
- **Contact Information**
- **GitHub Repository** (if applicable)
- **Thank the panel**

---

## **PRESENTATION TIPS**

### **Visual Aids:**
1. **Live Demo** (if possible): Show the app running on a device
   - Take a photo of food → Show segmentation
   - Log a meal → Show analytics update
   - Generate a PDF report

2. **Screenshots/Screen Recordings:**
   - Food recognition workflow
   - Analytics dashboard
   - PDF report sample

3. **Architecture Diagrams:**
   - System architecture
   - AI pipeline flow
   - Data flow diagram

4. **Model Performance Charts:**
   - Accuracy metrics
   - Training curves
   - Confusion matrices (if available)

### **Speaking Tips:**
- **Practice timing** - 15 minutes is strict; practice with a timer
- **Emphasize innovation** - Focus on AI/ML components (your core contribution)
- **Be prepared for questions** about:
  - Model training process
  - Dataset preparation
  - Performance optimization
  - Scalability considerations
  - Comparison with existing solutions

### **Key Points to Emphasize:**
1. **Technical Depth**: Three custom-trained models
2. **Practical Application**: Real-world problem solving
3. **Comprehensive Solution**: Full-stack development
4. **Performance**: On-device inference, offline support
5. **User Experience**: Intuitive interface, error correction

### **Potential Questions & Answers:**

**Q: Why three separate models instead of one?**
A: Each model serves a specific purpose. Segmentation identifies regions, while classification models specialize in different food categories. The ensemble approach provides better accuracy and fallback options.

**Q: How did you handle model size for mobile deployment?**
A: We used model quantization (INT8), efficient architectures like MobileNetV2, and lazy loading. Models are loaded only when needed, reducing initial app size.

**Q: What about foods not in your training dataset?**
A: We fallback to external nutrition APIs (Open Food Facts, USDA) when model confidence is low. Users can also manually correct predictions, and we plan to use this feedback for model improvement.

**Q: How accurate is portion size estimation?**
A: Portion estimation combines bounding box area, plate size detection, and food density factors. While not perfect, it provides reasonable estimates that users can adjust. Future work will improve this using depth estimation.

**Q: What makes this different from existing apps?**
A: Most apps require manual entry or use cloud-based APIs. NutriWise provides on-device AI inference for privacy and speed, supports multi-food meal detection, and includes specialized models for regional cuisines.

---

## **BACKUP SLIDES (If Time Permits)**

### **Slide 29: Dataset Details**
- Food-101: 101,000 images, 101 categories
- Kenyan Food: Custom dataset, 13 categories
- UEC Food-256: 256 categories for segmentation

### **Slide 30: Training Process**
- Data augmentation techniques
- Training hardware and time
- Hyperparameter tuning
- Validation strategies

### **Slide 31: API Integration Details**
- Open Food Facts API usage
- USDA database queries
- Barcode lookup fallback chain
- Error handling strategies

---

## **FINAL CHECKLIST**

Before Presentation:
- [ ] Test app on device (ensure it works)
- [ ] Prepare demo data (sample meals logged)
- [ ] Create screen recordings of key features
- [ ] Prepare architecture diagrams
- [ ] Review model performance metrics
- [ ] Practice timing (aim for 13-14 minutes to leave buffer)
- [ ] Prepare answers to common questions
- [ ] Backup slides ready
- [ ] Test presentation equipment
- [ ] Have code repository accessible (if needed)

---

**Good luck with your presentation!** 🎓

