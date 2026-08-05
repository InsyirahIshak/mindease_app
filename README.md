# MindEase 🧠

A Flutter + Firebase mobile system for monitoring and supporting student emotional wellbeing, built as a Final Year Project.

## 📱 Overview

MindEase helps identify students at risk of emotional distress through structured self-reporting and threshold-based risk classification, connecting them with personal advisors and counsellors for timely support.

## ✨ Key Features

- **Multi-role dashboards** — separate interfaces for Student, Personal Advisor, Counsellor, and Admin
- **Risk classification system** — threshold-based reclassification to flag students needing attention
- **Real-time notifications** — push alerts via OneSignal for timely follow-ups
- **Secure authentication** — Firebase Auth with App Check and device fingerprint verification
- **Progress tracking** — students can log and submit progress reports
- **Responsive UI** — tested and optimized across multiple Android devices

## 🛠️ Tech Stack

| Layer          | Technology                     |
|----------------|---------------------------------|
| Frontend       | Flutter (Dart)                  |
| Backend        | Firebase (Firestore, Auth, Functions) |
| Notifications  | OneSignal                       |
| Testing        | Flutter unit testing (28+ tests)|

## 📸 Screenshots

**Login**
![Login](assets/screenshots/login.png)

**Student Dashboard**
![Student Dashboard](assets/screenshots/student_dashboard.png)

**Logging Mood**
![Logging Mood](assets/screenshots/logMood.png)

**DASS-21 Assessment**
![DASS-21 Assessment](assets/screenshots/dass.png)

**Mood Tracking**
![Mood Tracking](assets/screenshots/moodtracking.png)

**Mood Tracking (Continuous)**
![Mood Tracking Continuous](assets/screenshots/moodtrack2.png)

**Personal Advisor Dashboard**
![PA Dashboard](assets/screenshots/padashboard.png)

**Counsellor Dashboard**
![Counsellor Dashboard](assets/screenshots/counsellordashboard.png)

**Admin Dashboard**
![Admin Dashboard](assets/screenshots/admindashboard.png)

## 🚀 Getting Started

```bash
git clone https://github.com/InsyirahIshak/mindease_app.git
cd mindease_app
flutter pub get
flutter run
```

> **Note:** Firebase and OneSignal configuration files (`google-services.json`, `.env`) are excluded for security. You'll need your own Firebase project and OneSignal app set up to run this locally.

## 🧪 Testing

```bash
flutter test
```

## 📄 Project Context

Developed as a Final Year Project (FYP) exploring how mobile technology can support early identification and intervention for student emotional wellbeing.

## 👩‍💻 Author

**Insyirah Ishak**