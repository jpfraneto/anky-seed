ANDROID_SDK ?= $(HOME)/Android/Sdk
ANDROID_JAVA_HOME ?= $(HOME)/.jdks/temurin-17
ANDROID_AVD ?= Anky_API_35_Play
ANDROID_APP_ID ?= app.anky.mobile.debug
ANDROID_EMULATOR_FLAGS ?= -gpu host -netdelay none -netspeed full
ANDROID_QT_PLATFORM ?= xcb

ANDROID_PATH := $(ANDROID_SDK)/platform-tools:$(ANDROID_SDK)/emulator:$(ANDROID_SDK)/cmdline-tools/latest/bin:$(PATH)
ANDROID_ENV := JAVA_HOME=$(ANDROID_JAVA_HOME) ANDROID_HOME=$(ANDROID_SDK) PATH="$(ANDROID_PATH)"

.PHONY: dev protocol-test mirror-dev mirror-test android-test android-build android-connected-test inspect

protocol-test:
	cd protocol/implementations/typescript && bun install && bun test

mirror-dev:
	cd backend && bun install && bun run dev

mirror-test:
	cd backend && bun install && bun test

android-test:
	cd apps/android && $(ANDROID_ENV) ./gradlew :app:test

android-build:
	cd apps/android && $(ANDROID_ENV) ./gradlew :app:assembleDebug

android-connected-test:
	cd apps/android && $(ANDROID_ENV) ./gradlew :app:connectedDebugAndroidTest

dev:
	@set -eu; \
	export JAVA_HOME="$(ANDROID_JAVA_HOME)"; \
	export ANDROID_HOME="$(ANDROID_SDK)"; \
	export QT_QPA_PLATFORM="$(ANDROID_QT_PLATFORM)"; \
	export PATH="$(ANDROID_PATH)"; \
	APK="apps/android/app/build/outputs/apk/debug/app-debug.apk"; \
	if [ ! -x "$$JAVA_HOME/bin/java" ]; then \
		echo "Missing JDK at $$JAVA_HOME"; \
		echo "Override with: make dev ANDROID_JAVA_HOME=/path/to/jdk17"; \
		exit 1; \
	fi; \
	if [ ! -x "$$ANDROID_HOME/platform-tools/adb" ] || [ ! -x "$$ANDROID_HOME/emulator/emulator" ]; then \
		echo "Missing Android SDK tools under $$ANDROID_HOME"; \
		echo "Override with: make dev ANDROID_SDK=/path/to/Android/Sdk"; \
		exit 1; \
	fi; \
	if ! emulator -list-avds | grep -Fxq "$(ANDROID_AVD)"; then \
		echo "Missing AVD: $(ANDROID_AVD)"; \
		echo "Create it with Android Studio Device Manager or override with ANDROID_AVD=<name>."; \
		exit 1; \
	fi; \
	echo "Building debug APK..."; \
	cd apps/android; \
	./gradlew :app:assembleDebug; \
	cd ../..; \
	adb start-server >/dev/null; \
	if ! adb get-state >/dev/null 2>&1; then \
		echo "Starting emulator $(ANDROID_AVD)..."; \
		emulator @"$(ANDROID_AVD)" $(ANDROID_EMULATOR_FLAGS) >/tmp/anky-android-emulator.log 2>&1 & \
	fi; \
	echo "Waiting for Android device..."; \
	for i in $$(seq 1 120); do \
		if adb get-state >/dev/null 2>&1; then break; fi; \
		sleep 2; \
	done; \
	if ! adb get-state >/dev/null 2>&1; then \
		echo "No Android device became available. See /tmp/anky-android-emulator.log"; \
		exit 1; \
	fi; \
	echo "Waiting for boot completion..."; \
	for i in $$(seq 1 120); do \
		boot=$$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); \
		if [ "$$boot" = "1" ]; then break; fi; \
		sleep 2; \
	done; \
	boot=$$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); \
	if [ "$$boot" != "1" ]; then \
		echo "Emulator did not finish booting. See /tmp/anky-android-emulator.log"; \
		exit 1; \
	fi; \
	echo "Installing $$APK..."; \
	adb install -r "$$APK"; \
	echo "Launching $(ANDROID_APP_ID)..."; \
	adb shell monkey -p "$(ANDROID_APP_ID)" 1; \
	if command -v wmctrl >/dev/null 2>&1; then \
		wmctrl -r "Android Emulator - $(ANDROID_AVD):5554" -b remove,hidden,shaded >/dev/null 2>&1 || true; \
		wmctrl -r "Android Emulator - $(ANDROID_AVD):5554" -e 0,1100,80,500,1050 >/dev/null 2>&1 || true; \
		wmctrl -a "Android Emulator - $(ANDROID_AVD):5554" >/dev/null 2>&1 || wmctrl -a "Emulator" >/dev/null 2>&1 || true; \
	fi; \
	echo "Ready: $(ANDROID_APP_ID) is running on $$(adb devices | awk 'NR==2 {print $$1}')"

inspect:
	bun run scripts/inspect-anky.ts $(FILE)
