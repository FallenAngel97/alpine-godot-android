FROM azul/zulu-openjdk-alpine:25.0.0-25.28 AS base

ENV GODOT_VERSION=4.5

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
  clang \
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
  gcompat

RUN git clone --depth 1 https://github.com/godotengine/godot.git -b $GODOT_VERSION-$RELEASE_NAME && \
    cd godot && \
    scons platform=linuxbsd \
    target=editor \
    tools=no \
    module_3d_enabled=no \
    module_bullet_enabled=no \
    module_openssl_enabled=no \
    module_theora_enabled=no \
    module_webm_enabled=no \
    module_vorbis_enabled=yes \
    use_lto=yes \
    use_static_cpp=yes \
    CC=clang \
    CXX=clang++ \
    CPPDEFINES=["DISABLE_3D"] \
    LINKFLAGS="-Wl,--gc-sections -Wl,-O1 -s -flto" \
    CFLAGS="-Os -pipe -fomit-frame-pointer -fdata-sections -ffunction-sections" \
    CXXFLAGS="-Os -pipe -fomit-frame-pointer -fdata-sections -ffunction-sections" \
    -j1 \
    && strip bin/godot* && mv bin/godot* /usr/bin/godot && rm -rf godot 

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
    && sdkmanager "platform-tools" "build-tools;33.0.2" "platforms;android-33" "cmdline-tools;latest" "cmake;3.22.1" "ndk;29.0.14033849"

# Add Android keystore and settings.
RUN keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 \
    && mv debug.keystore /root/debug.keystore

RUN godot -v -e --quit --headless ${GODOT_TEST_ARGS}
RUN rm -rf /root/.local/share/godot/export_templates/**/android_source.zip \
   /root/.local/share/godot/export_templates/**/ios.zip \
   /root/.local/share/godot/export_templates/**/windows_* \
   /root/.local/share/godot/export_templates/**/web*.zip \
   /root/.local/share/godot/export_templates/**/macos.zip \
   /root/.local/share/godot/export_templates/**/linux* \
   /usr/lib/android-sdk/ndk/29.0.14033849/sources \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/python3 \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/lib/x86_64-unknown-linux-gnu \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/lib/x86_64-w64-windows-gnu \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/lib/i686-w64-windows-gnu \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/lib/python3.11 \
   /usr/lib/android-sdk/ndk/29.0.14033849/toolchains/llvm/prebuilt/linux-x86_64/lib/python3 \
   /usr/lib/android-sdk/platforms/android-33/data \
   /usr/lib/android-sdk/platforms/android-33/skins \
   /usr/lib/android-sdk/platforms/android-33/templates \
   /usr/lib/android-sdk/platforms/android-33/optional \
   /usr/lib/android-sdk/platforms/android-33/uiautomator.jar \
   /usr/lib/android-sdk/platforms/android-33/android-stubs-src.jar \
   /usr/lib/android-sdk/platforms/android-33/core-for-system-modules.jar \
   /usr/lib/android-sdk/platforms/android-33/build.prop \
   /usr/lib/android-sdk/platforms/android-33/build.prop \

RUN find . \( -type f \
   -name "LICENSE*" \
   -o -name "NOTICE*" \
   -o -name "CHANGELOG*" \
   -o -name "README*" \
   -o -name "Copyright*" \
   -o -name "COPYRIGHT*" \) \
   -exec rm -v {} \; 
# Godot editor settings are stored per minor version since 4.3.
# `${GODOT_VERSION:0:3}` transforms a string of the form `x.y.z` into `x.y`, even if it's already `x.y` (until Godot 4.9).
RUN echo '[gd_resource type="EditorSettings" format=3]' > ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo '[resource]' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/java_sdk_path = "/usr/lib/jvm/zulu25-ca"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/android_sdk_path = "/usr/lib/android-sdk"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore = "/root/debug.keystore"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore_user = "androiddebugkey"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/debug_keystore_pass = "android"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/force_system_user = false' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/timestamping_authority_url = ""' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres
RUN echo 'export/android/shutdown_adb_on_exit = true' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres

FROM azul/zulu-openjdk-alpine:25.0.0-25.28 AS preprod
COPY --from=base /usr/bin/godot /usr/bin/godot
COPY --from=base /usr/lib/android-sdk /usr/lib/android-sdk
COPY --from=base /root/debug.keystore /root/debug.keystore
COPY --from=base /root/.config /root/.config
COPY --from=base /root/.local /root/.local
COPY --from=base /root/.android /root/.android
RUN mkdir -p /root/.gradle && echo '\
org.gradle.caching=true\n\
org.gradle.parallel=false\n\
org.gradle.daemon=false\n\
org.gradle.jvmargs=-Xmx512m -XX:+UseSerialGC\n' \
> /root/.gradle/gradle.properties
RUN apk add eudev-dev gcompat curl fontconfig --no-cache
FROM scratch
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV JAVA_HOME=/usr/lib/jvm/zulu25
ENV ANDROID_HOME=/usr/lib/android-sdk
COPY --from=preprod / /
