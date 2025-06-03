FROM alpine/java:17-jdk AS base
USER root

# When in doubt, see the downloads page: https://github.com/godotengine/godot-builds/releases/
ARG GODOT_VERSION="4.4.1"

# Example values: stable, beta3, rc1, dev2, etc.
# Also change the `SUBDIR` argument below when NOT using stable.
ARG RELEASE_NAME="stable"

# This is only needed for non-stable builds (alpha, beta, RC)
# e.g. SUBDIR "/beta3"
# Use an empty string "" when the RELEASE_NAME is "stable".
ARG SUBDIR=""

ARG GODOT_TEST_ARGS=""
ARG GODOT_PLATFORM="linux.x86_64"

RUN apk add \
  scons \
  pkgconf \
  gcc \
  g++ \
  libx11-dev \
  libxcursor-dev \
  libxinerama-dev \
  libxi-dev \
  libxrandr-dev \
  mesa-dev \
  eudev-dev \
  alsa-lib-dev \
  pulseaudio-dev \
  git \
  gcompat \
  upx --no-cache

RUN git clone --depth 1 https://github.com/godotengine/godot.git -b $GODOT_VERSION-$RELEASE_NAME && \
    cd godot && scons platform=linuxbsd target=editor && strip bin/godot* && upx bin/godot* && mv bin/godot* /usr/bin/godot && rm -rf godot 


# Download and set up Android SDK to export to Android.
ENV ANDROID_HOME="/usr/lib/android-sdk"
RUN wget https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip \
    && wget https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${RELEASE_NAME}/Godot_v${GODOT_VERSION}-${RELEASE_NAME}_export_templates.tpz \
    && unzip Godot_v${GODOT_VERSION}-${RELEASE_NAME}_export_templates.tpz \
    && mkdir -p ~/.local/share/godot/export_templates/${GODOT_VERSION}.${RELEASE_NAME} \
    && mv templates/* ~/.local/share/godot/export_templates/${GODOT_VERSION}.${RELEASE_NAME} \
    && unzip commandlinetools-linux-*_latest.zip \
    && mkdir -p $ANDROID_HOME/cmdline-tools/tools \
    && mv cmdline-tools/* $ANDROID_HOME/cmdline-tools/tools/ \
    && rm -rf commandlinetools-linux-*_latest.zip cmdline-tools Godot_v${GODOT_VERSION}-${RELEASE_NAME}_export_templates.tpz

ENV PATH="${ANDROID_HOME}/cmdline-tools/tools/bin:${PATH}"

RUN yes | sdkmanager --licenses \
    && sdkmanager "platform-tools" "build-tools;33.0.2" "platforms;android-33" "cmdline-tools;latest" "cmake;3.22.1" "ndk;25.2.9519653"

# Add Android keystore and settings.
RUN keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 \
    && mv debug.keystore /root/debug.keystore

RUN upx $(find /usr/lib/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/bin/) || true

RUN godot -v -e --quit --headless ${GODOT_TEST_ARGS}
RUN rm -rf /root/.local/share/godot/export_templates/**/android_source.zip \
   /root/.local/share/godot/export_templates/**/ios.zip \
   /root/.local/share/godot/export_templates/**/windows_* \
   /root/.local/share/godot/export_templates/**/web*.zip \
   /root/.local/share/godot/export_templates/**/macos.zip \
   /root/.local/share/godot/export_templates/**/linux*

RUN find . \( -type f \
   -name "LICENSE*" \
   -o -name "NOTICE*" \
   -o -name "README*" \
   -o -name "Copyright*" \
   -o -name "COPYRIGHT*" \) \
   -exec rm -v {} \; 
# Godot editor settings are stored per minor version since 4.3.
# `${GODOT_VERSION:0:3}` transforms a string of the form `x.y.z` into `x.y`, even if it's already `x.y` (until Godot 4.9).
RUN echo '[gd_resource type="EditorSettings" format=3]' > ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo '[resource]' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/java_sdk_path = "/usr/lib/jvm/java-17-openjdk-amd64"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/android_sdk_path = "/usr/lib/android-sdk"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore = "/root/debug.keystore"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore_user = "androiddebugkey"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore_pass = "android"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/force_system_user = false' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/timestamping_authority_url = ""' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/shutdown_adb_on_exit = true' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres

FROM alpine/java:17-jdk AS preprod
COPY --from=base /usr/bin/godot /usr/bin/godot
COPY --from=base /usr/lib/android-sdk /usr/lib/android-sdk
COPY --from=base /root/debug.keystore /root/debug.keystore
COPY --from=base /root/.config /root/.config
COPY --from=base /root/.local /root/.local
COPY --from=base /root/.android /root/.android
RUN apk add eudev-dev gcompat curl --no-cache
FROM scratch
ENV JAVA_VERSION=jdk-17.0.12+7
ENV PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV JAVA_HOME=/opt/java/openjdk
ENV ANDROID_HOME=/usr/lib/android-sdk
ENV JRE_CACERTS_PATH=/opt/java/openjdk/lib/security/cacerts
COPY --from=preprod / /
