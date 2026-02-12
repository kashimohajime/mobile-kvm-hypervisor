# 📱 KVM Supervisor — Application Mobile Flutter

Application mobile de supervision d'hyperviseur KVM, communiquant avec un backend Flask via API REST.

---

## 📋 Prérequis

| Élément | Version minimale |
|---------|-----------------|
| Flutter SDK | 3.16+ |
| Dart SDK | 3.1+ |
| Android SDK | API 21+ (Android 5.0) |
| Xcode (iOS) | 15+ |
| Backend Flask | Démarré et accessible |

---

## 🚀 Installation

### 1. Installer Flutter

Suivre les instructions officielles : https://docs.flutter.dev/get-started/install

```bash
# Vérifier l'installation
flutter doctor
```

### 2. Installer les dépendances du projet

```bash
cd frontend/
flutter pub get
```

### 3. Configurer l'IP du backend

L'IP du backend est configurable directement dans l'application (écran Paramètres). Par défaut : `http://192.168.1.100:5000`.

> **Pour Android Emulator** : utilisez `http://10.0.2.2:5000`
> **Pour appareil physique** : utilisez l'IP de votre VM Ubuntu sur le réseau local

---

## ▶️ Lancement

### Sur émulateur Android

```bash
# Lister les appareils disponibles
flutter devices

# Lancer l'app
flutter run
```

### Sur appareil physique (USB)

```bash
# Activer le mode développeur + débogage USB sur le téléphone
flutter run -d <device_id>
```

### Build APK (pour distribution)

```bash
flutter build apk --release
# L'APK est dans : build/app/outputs/flutter-apk/app-release.apk
```

---

## 📁 Structure du projet

```
frontend/
├── lib/
│   ├── main.dart                      # Point d'entrée, thèmes, routing
│   ├── models/
│   │   └── vm_model.dart              # Modèles de données (VM, Metrics, Host)
│   ├── services/
│   │   └── api_service.dart           # Client HTTP (GET/POST, retry, erreurs)
│   ├── providers/
│   │   ├── vm_provider.dart           # State management principal
│   │   └── settings_provider.dart     # Paramètres persistants
│   ├── screens/
│   │   ├── vm_list_screen.dart        # Liste des VMs (écran principal)
│   │   ├── vm_detail_screen.dart      # Détails + métriques d'une VM
│   │   ├── settings_screen.dart       # Configuration de l'app
│   │   └── dashboard_screen.dart      # Vue globale de l'hyperviseur
│   └── widgets/
│       ├── vm_card.dart               # Carte VM réutilisable
│       └── metric_widgets.dart        # Jauges, barres de progression, shimmer
├── pubspec.yaml                       # Dépendances Flutter
└── README.md                          # Ce fichier
```

---

## 🎨 Fonctionnalités

### Écran 1 — Liste des VMs
- ✅ Cards colorées par état (vert=running, rouge=stopped)
- ✅ Pull-to-refresh
- ✅ Barre de recherche
- ✅ Filtres par état (Toutes, Actives, Arrêtées, En pause)
- ✅ Compteurs rapides (Total / Actives / Arrêtées)
- ✅ Bouton flottant auto-refresh (configurable)
- ✅ Animations d'entrée fluides
- ✅ États loading (shimmer) / erreur / vide

### Écran 2 — Détails VM
- ✅ Informations complètes (UUID, OS, réseau, etc.)
- ✅ Jauges CPU et RAM animées
- ✅ Graphique historique temps réel (fl_chart)
- ✅ I/O Disque et Réseau
- ✅ Boutons Start / Stop / Restart avec confirmation
- ✅ Suivi temps réel activable

### Écran 3 — Dashboard
- ✅ Infos hôte (hostname, CPU, RAM, libvirt)
- ✅ Compteurs VMs avec icônes
- ✅ Diagramme circulaire des états
- ✅ Tableau compact des VMs

### Écran 4 — Paramètres
- ✅ URL du backend modifiable
- ✅ Test de connexion
- ✅ Thème sombre / clair / système
- ✅ Configuration auto-refresh

---

## 🔧 Configuration réseau (Android)

### Autoriser HTTP en clair (si backend sans HTTPS)

Le fichier `android/app/src/main/AndroidManifest.xml` doit contenir :

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

### Permissions Internet

Le fichier `android/app/src/main/AndroidManifest.xml` doit contenir :

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

---

## 🐛 Dépannage

### L'app ne se connecte pas au backend
1. Vérifier l'IP dans **Paramètres** → tester la connexion
2. Vérifier que le backend tourne (`curl http://<IP>:5000/health`)
3. Vérifier le firewall (`sudo ufw allow 5000/tcp`)

### Emulateur Android → backend sur localhost
Utiliser `http://10.0.2.2:5000` (l'émulateur redirige `10.0.2.2` vers l'hôte)

### Le "flutter run" plante au démarrage (Android Emulator)
Vous voyez l'erreur : `Using the Impeller rendering backend (OpenGLES)` puis l'app quitte.
C'est un problème de compatibilité graphique avec l'émulateur.

**Solution :**
Désactivez Impeller au lancement :
```bash
flutter run --no-enable-impeller
```

### Les métriques CPU montrent 0%
C'est normal si la VM vient de démarrer. Attendez quelques secondes.

---

## 📄 Licence

Projet académique — Supervision d'hyperviseur KVM.
