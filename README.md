# LifeOS – AI Executive Function Operating System

**LifeOS** is a native Apple ecosystem application (iOS, macOS, watchOS, iPadOS) that acts as an AI-powered **executive function operating system** — not a task manager. It reduces cognitive load by becoming your second brain across work, personal life, health, relationships, creativity, finances, and routines.

---

## 🌟 Key Features

### 🧠 Executive Brain & Cognitive Model
- **"What Should I Do Now?" Dashboard**: Analyzes energy, focus capacity, stress, sleep debt, and deadlines to recommend the SINGLE best next action.
- **Energy-Aware Scheduling**: Automatically matches task difficulty to your current energy state (Peak, High, Moderate, Low, Recovery).
- **Executive Function (EF) Score**: Holistic score based on task completion patterns and cognitive state, not raw productivity.

### 📥 Universal Inbox
- Quick capture text, voice notes, photos, links, emails, and PDFs.
- AI automatically categorizes items into Life Areas, assigns priority, and suggests actionable tasks.

### ⚡ ADHD-Specific Scaffolding
- **Emergency Mode**: Shows ONLY your top 3 actions with large tap targets when feeling overwhelmed.
- **Task Initiation Countdown**: 3-2-1 countdown to overcome start resistance.
- **Focus Sessions**: Timer with hyperfocus detection and break reminders.
- **Body Doubling Mode**: Virtual co-working presence with ambient timer and breathing ring.
- **Context Recovery**: Pick up right where you left off after an interruption.
- **Task Decomposition**: AI breaks complex tasks into 5-minute actionable micro-steps.

### 🤖 AI Coach
- Supportive, non-judgmental conversational AI companion powered by **Google Gemini API**.
- Offers practical strategies for task initiation, emotional regulation, and prioritization.

### ❤️ HealthKit & Watch Data Integration
- Reads sleep stages (Deep, REM, Core), HRV (SDNN), heart rate, and workouts from HealthKit.
- Apple Watch data syncs automatically to iPhone's HealthKit — **no Watch app required**.
- Privacy-first: raw health data never leaves your device. Only daily aggregated metrics feed the AI model.

### 💻 macOS Background Productivity Monitor
- Unsigned macOS app monitors active windows/apps and idle time.
- Syncs productivity logs via **Firebase Firestore** so your iPhone AI knows your Mac context.

---

## 📐 Architecture

LifeOS is structured as a modular set of Swift Packages following Clean Architecture principles:

```
LifeOS/
├── Packages/
│   ├── LifeOSCore/         # Platform-agnostic domain models & protocols
│   ├── LifeOSAI/           # Gemini API provider, Executive Brain, Prompts, Task Decomposer
│   ├── LifeOSData/         # Firebase Firestore & Auth repositories
│   ├── LifeOSHealth/       # HealthKit manager (sleep, HRV, heart rate, activity)
│   └── LifeOSFeatures/     # ViewModels (BrainVM, TasksVM, InboxVM, ADHDVM)
├── LifeOS-iOS/             # SwiftUI iOS app target
├── LifeOS-macOS/           # SwiftUI macOS target (menu bar + tracker)
└── project.yml             # XcodeGen spec
```

---

## 🚀 Getting Started

### 1. Prerequisites
- macOS Sonoma (14.0+) or later
- Xcode 15.0+ or Xcode 16+
- Free Google Gemini API Key (get one at [ai.google.dev](https://ai.google.dev))

### 2. Generate Xcode Project
If you have `xcodegen` installed:
```bash
cd /Users/samaksh/ADHD/LifeOS
xcodegen generate
```

Or open the Swift Packages directly in Xcode by opening `Packages/` or running `open Package.swift`.

### 3. Configure Gemini API Key
1. Open LifeOS on iOS or Mac.
2. Go to **Settings** → **AI Engine**.
3. Enter your Gemini API key.

---

## 🔒 Privacy & Data Policy
- **Health Data**: Raw heart rate and sleep samples remain encrypted on your iPhone in HealthKit.
- **Cloud Sync**: Firebase Firestore handles cross-device sync with security rules tied to your account.
- **No Data Selling**: Your behavioral patterns and health metrics are strictly yours.
