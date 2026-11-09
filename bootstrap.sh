#!/usr/bin/env bash
# Bongkar proyek MochiLyn Voice Changer (Magisk/Zygisk) ke folder MochiLynVoice/.
# Satu file ini berisi semua sumber, jadi cukup unggah file ini ke GitHub.
set -e
mkdir -p MochiLynVoice && cd MochiLynVoice

mkdir -p "$(dirname "build.sh")"
cat > 'build.sh' <<'__MLV_FILE_END__'
#!/usr/bin/env bash
# Build modul Magisk -> MochiLynVoice-<versi>.zip
# Butuh: Android NDK (env ANDROID_NDK_HOME atau ANDROID_NDK_LATEST_HOME), cmake, zip, curl.
# Di GitHub Actions (ubuntu-latest) semuanya sudah tersedia.
set -euo pipefail
cd "$(dirname "$0")"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
[ -n "$NDK" ] && [ -f "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "NDK tidak ketemu. Set ANDROID_NDK_HOME."; exit 1; }

# --- header Zygisk resmi (ABI harus persis sama dengan Magisk, jadi tidak ditulis ulang manual) ---
HDR=native/src/zygisk.hpp
if [ ! -f "$HDR" ]; then
  URLS="${ZYGISK_HPP_URL:-} \
https://raw.githubusercontent.com/topjohnwu/zygisk-module-sample/master/module/jni/zygisk.hpp \
https://raw.githubusercontent.com/topjohnwu/zygisk-module-sample/main/module/jni/zygisk.hpp \
https://raw.githubusercontent.com/topjohnwu/Magisk/master/native/src/core/zygisk/api.hpp"
  for u in $URLS; do
    [ -n "$u" ] || continue
    echo "mencoba $u"
    if curl -fsSL "$u" -o "$HDR.tmp" && grep -q "REGISTER_ZYGISK_MODULE" "$HDR.tmp"; then mv "$HDR.tmp" "$HDR"; break; fi
    rm -f "$HDR.tmp"
  done
fi
[ -f "$HDR" ] || { echo "Gagal mengunduh zygisk.hpp. Salin file resminya ke $HDR lalu jalankan ulang."; exit 1; }
grep -m1 -n "ZYGISK_API_VERSION" "$HDR" || true

VER=$(sed -n 's/^version=//p' module/module.prop)
rm -rf build module/zygisk && mkdir -p module/zygisk
for ABI in arm64-v8a armeabi-v7a; do
  cmake -S native -B "build/$ABI" -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release
  cmake --build "build/$ABI" -j"$(nproc)"
  cp "build/$ABI/libmochilyn_voice.so" "module/zygisk/$ABI.so"
  "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip --strip-unneeded "module/zygisk/$ABI.so" || true
done

OUT="MochiLynVoice-$VER.zip"
rm -f "$OUT"
(cd module && zip -r9 -X "../$OUT" . -x '*.DS_Store')
echo "SELESAI: $OUT"
unzip -l "$OUT"
__MLV_FILE_END__
mkdir -p "$(dirname "README.md")"
cat > 'README.md' <<'__MLV_FILE_END__'
# MochiLyn Voice Changer (Magisk / Zygisk) v0.1.0 - by MochiLyn

Mengubah suara mic cowok jadi cewek natural (+11 semitone) di app pilihan, misalnya WhatsApp dan Roblox.
Mesin suaranya port C++ dari voice changer Sambung (hasilnya identik dengan versi web, sudah diuji).

## Status jujur
- Mesin suara: diuji di PC (identik dengan versi JS, tahan banting lewat fuzz ASan/UBSan).
- Logika modul (companion, config, preset, pencocokan app, jalur PCM16): diuji di PC.
- BELUM dikompilasi untuk ARM dan BELUM diuji di HP. Pemasangan hook ke AudioRecord memakai header Zygisk resmi
  yang diunduh saat build; cocok tidaknya dengan Magisk-mu baru terlihat saat dicoba.
- Hanya menangkap app yang membaca mic lewat Java `AudioRecord`. App yang memakai jalur native (OpenSL ES / AAudio / Oboe)
  tidak tersentuh. Perintah `su -c mlv status` menunjukkan app mana yang benar-benar terhubung.
- Tidak ada EQ per preset (di Sambung ada). Hanya mesin nada dan formant.

## Cara kerja
1. Saat sebuah app dibuka, modul bertanya ke proses companion (root) apakah app itu ada di `apps.txt`. Kalau tidak, modul melepas diri dari app itu.
2. Kalau ya, modul mengganti fungsi baca mic (`AudioRecord.native_read_*`): sistem membaca suara asli, mesin mengubahnya, app menerima hasilnya.
3. Preset/nada/delay dibaca dari `/data/adb/mochilyn_voice/config.txt` dan dikirim ke app tiap ~1 detik (tanpa restart app).
4. Aman-gagal: kalau hook tidak ketemu atau companion mati, suara asli lewat apa adanya. Modul tidak menyentuh system_server dan tidak mengganti file sistem,
   jadi risiko bootloop kecil. Kalau ada masalah: matikan modul di Magisk, atau dari recovery hapus folder `/data/adb/modules/mochilyn_voice`.

## Build (pilih satu)
### A. GitHub Actions (cukup dari HP)
1. Buat repo GitHub baru. Add file > Upload files > unggah satu file: `bootstrap.sh` (berisi seluruh sumber modul).
2. Add file > Create new file, ketik nama `.github/workflows/build.yml`, tempel isi file `build.yml` dari chat, simpan (commit).
3. Tab Actions > build-magisk-module > Run workflow. Selesai (beberapa menit), buka run-nya dan unduh artifact `MochiLynVoice-magisk` (isinya zip modul).
Tanpa GitHub: jalankan `bash bootstrap.sh` untuk membongkar semua file ke folder `MochiLynVoice/`.
### B. PC dengan NDK
`export ANDROID_NDK_HOME=/path/ndk && ./build.sh` menghasilkan `MochiLynVoice-v0.1.0.zip`.
Kalau unduhan `zygisk.hpp` gagal, salin header resmi dari repo Magisk ke `native/src/zygisk.hpp` lalu ulangi.

## Pasang
1. Magisk > Pengaturan > nyalakan **Zygisk**. Pastikan WhatsApp/Roblox tidak ada di DenyList.
2. Magisk > Modul > Pasang dari penyimpanan > pilih zip hasil build > reboot.
3. Buka app, lakukan panggilan atau rekam pesan suara. Cek: `su -c mlv status` (Termux).

## Ganti preset (menu)
- Tombol **Action** modul di aplikasi Magisk (Magisk 27+) = preset berikutnya.
- Atau Termux: `su -c mlv next`, `mlv set natural`, `mlv list`, `mlv tune 1.5`, `mlv delay 60`, `mlv refresh`, `mlv on|off`, `mlv add com.paket.app`.
- Preset: plus11 (Cewe natural +11, bawaan), natural, teen, onee, anime, normal.

## Kalau tidak berubah suaranya
- `su -c mlv status` kosong di bagian "Hook aktif": app memakai jalur audio native atau tidak ada di `apps.txt`. Kirim hasil `logcat -s MochiLynVoice` untuk dilanjutkan ke hook native.
- Modul tidak termuat sama sekali: versi API Zygisk di header mungkin lebih baru dari Magisk-mu. Pakai header versi lebih lama.

## Uji di PC
`bash test/run_tests.sh` (butuh g++, node, python3 + numpy/scipy).
__MLV_FILE_END__
mkdir -p "$(dirname "native/CMakeLists.txt")"
cat > 'native/CMakeLists.txt' <<'__MLV_FILE_END__'
cmake_minimum_required(VERSION 3.18)
project(mochilyn_voice CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/zygisk.hpp")
  message(FATAL_ERROR "src/zygisk.hpp belum ada. Jalankan build.sh (mengunduhnya) atau salin zygisk.hpp resmi ke native/src/.")
endif()

add_library(mochilyn_voice SHARED src/main.cpp)
target_include_directories(mochilyn_voice PRIVATE src)
target_compile_options(mochilyn_voice PRIVATE -O2 -Wall -Wextra -Wno-unused-parameter -ffunction-sections -fdata-sections)
target_link_libraries(mochilyn_voice PRIVATE log)
target_link_options(mochilyn_voice PRIVATE -Wl,--gc-sections -Wl,--build-id=none)
__MLV_FILE_END__
mkdir -p "$(dirname "native/src/engine.hpp")"
cat > 'native/src/engine.hpp' <<'__MLV_FILE_END__'
// Mesin voice changer MochiLyn (cowok -> cewek). Port C++ dari voice-processor.js milik Sambung.
// Cara kerja: pelacak nada NSDF -> pitch mark -> sintesis PSOLA (jarak grain = nada, resample grain = formant).
// Bagian tak bersuara dilewatkan lewat grain identitas. Tanpa alokasi memori di jalur audio setelah konstruktor.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#ifndef M_SQRT1_2
#define M_SQRT1_2 0.70710678118654752440
#endif

namespace mlv {

constexpr int HOP = 128;
constexpr int RING = 1 << 15, RM = RING - 1;
constexpr int FRING = 512, FM = FRING - 1;
constexpr int MRING = 4096, MM = MRING - 1;
constexpr double V_ENTER = 0.45, V_STAY = 0.25, V_SURE = 0.5;
constexpr int V_HANG = 10;

inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }
inline double jround(double x) { return std::floor(x + 0.5); }   // Math.round ala JavaScript

struct Params {
  double f0 = 225, formant = 1.17, inton = 1, tune = 0;
  bool rel = false;        // true: nada target = rata-rata nada pembicara + relSemi semitone
  double relSemi = 0;
};

struct Stat { double f0in = 0, f0out = 0; int voiced = 0, underrun = 0, heal = 0; };

class VoiceEngine {
 public:
  explicit VoiceEngine(int sampleRate)
      : sr_(sampleRate),
        xr(RING), xl(RING), xd(RING), ob(RING),
        fTag(FRING, -1), fV(FRING, 0), fT(FRING, 0), fRun(FRING, 0),
        mPos(MRING, 0), mPer(MRING, 0), mRun(MRING, 0), ref(2048, 0) {
    const double sr = sr_;
    D = std::max(1, (int)jround(sr / 8000));
    srd = sr / D;
    tauMin = std::max(4, (int)std::floor(srd / 500));
    tauMax = (int)std::ceil(srd / 70) + 2;
    W = 192;
    seg.assign(W + tauMax + 4, 0.f);
    nsdf.assign(tauMax + 4, 0.f);
    Tmax = sr / 70;
    Lq = (int)jround(0.045 * sr);
    HW = (int)std::ceil(Tmax) + 4;
    dc = (int)jround(W * D / 2.0 + 0.004 * sr);
    Hu = (int)jround(0.004 * sr);
    LqMin = dc + HW + 64;
    {
      const double wh = 2 * M_PI * 80 / sr, ch = std::cos(wh), ah = std::sin(wh) / (2 * M_SQRT1_2), a0h = 1 + ah;
      hb0 = ((1 + ch) / 2) / a0h; hb1 = -(1 + ch) / a0h; hb2 = hb0;
      ha1 = (-2 * ch) / a0h; ha2 = (1 - ah) / a0h;
    }
    {
      const double w0 = 2 * M_PI * 1000 / sr, cs = std::cos(w0), al = std::sin(w0) / (2 * M_SQRT1_2), a0 = 1 + al;
      lb0 = ((1 - cs) / 2) / a0; lb1 = (1 - cs) / a0; lb2 = lb0;
      la1 = (-2 * cs) / a0; la2 = (1 - al) / a0;
    }
    lnT = std::log(sr / 120);
    mu = std::log(125.0);
  }

  int sampleRate() const { return sr_; }
  int latencySamples() const { return Lq; }
  const Stat& stat() const { return stat_; }
  double speakerF0() const { return std::exp(mu); }

  // ---- pengaturan (panggil dari thread yang sama dengan process) ----
  void setParams(const Params& p) {
    P.f0 = clampd(p.f0, 100, 600);
    P.formant = clampd(p.formant, 0.85, 1.6);
    P.inton = clampd(p.inton, 0, 2);
    P.tune = clampd(p.tune, -15, 15);
    P.rel = p.rel;
    P.relSemi = clampd(p.relSemi, -24, 24);
  }
  void setActive(bool a) { mixTarget = a ? 1 : 0; }
  void setAutoHeal(bool a) { autoHeal = a; }
  void refresh() { if (!idle) hardReset(); }
  bool isIdle() const { return idle; }
  void setDelayMs(double ms) {
    const int L = std::max(LqMin, (int)jround(clampd(ms, 0, 500) / 1000 * sr_));
    if (L != Lq) { Lq = L; if (!idle) reset(); }
  }

  // ---------------------------------------------------------------- utama
  // inp boleh nullptr (dianggap hening). N <= 8192 per panggilan.
  void process(const float* inp, float* out, int N) {
    const int64_t n0 = n;
    const bool active = mixTarget > 0 || mix > 0;
    if (active && idle) wake();

    int pos = 0;
    while (pos < N) {
      const int take = std::min(N - pos, HOP - (int)(n & (HOP - 1)));
      for (int i = 0; i < take; i++) push(inp ? (double)inp[pos + i] : 0.0);
      pos += take;
      if ((n & (HOP - 1)) == 0 && !idle) analyze();
    }

    if (!idle) {
      const int64_t nEnd = n;
      const double lag = (double)((nEnd - Lq) - (int64_t)ts);
      if (!(lag == lag) || (autoHeal && (lag > 0.15 * sr_ || lag < -4.0 * HW))) { stat_.heal++; hardReset(); }
      synth((double)(nEnd - Lq + HW));
    }

    const int64_t e0 = n0 - Lq;
    double sOO = 0, sRR = 0, sOR = 0;
    for (int i = 0; i < N; i++) {
      double dry = inp ? (double)inp[i] : 0.0;
      if (!std::isfinite(dry)) dry = 0; else if (dry > 8) dry = 8; else if (dry < -8) dry = -8;
      double y = dry;
      if (!idle) {
        const int j = (int)((e0 + i) & RM);
        const double wet = (e0 + i) >= 0 ? (double)ob[j] : 0.0;
        ob[j] = 0.f;
        if (mix < mixTarget) mix = std::min((double)mixTarget, mix + mixStep());
        else if (mix > mixTarget) mix = std::max((double)mixTarget, mix - mixStep());
        y = dry + (wet - dry) * mix;
        if (!(y == y) || y > 1e4 || y < -1e4) { y = 0; reset(); }
        const double ay = y < 0 ? -y : y;
        if (ay > 0.8) y = (y < 0 ? -1 : 1) * (0.8 + 0.2 * std::tanh((ay - 0.8) / 0.2));
        if (muteN > 0) { muteN--; y = 0; }
        const double rw = (e0 + i) >= 0 ? (double)xr[j] : 0.0;
        sOO += y * y; sRR += rw * rw; sOR += y * rw;
      }
      out[i] = (float)y;
    }
    if (!idle) {
      emitted = e0 + N;
      if (mix == 0 && mixTarget == 0) idle = true;
      else watch(sOO, sRR, sOR, N);
    }
  }

 private:
  double mixStep() const { return 1.0 / (0.03 * sr_); }

  void watch(double sOO, double sRR, double sOR, int N) {
    if (!autoHeal || mixTarget < 1 || mix < 0.99) { leakN = 0; deadN = 0; return; }
    const double rIn = std::sqrt(sRR / N), rOut = std::sqrt(sOO / N);
    if (rIn < 0.01) { if (leakN > 0) leakN--; if (deadN > 0) deadN--; return; }
    const double rho = sOR / std::sqrt(sOO * sRR + 1e-12);
    const bool shifted = stat_.f0in > 0 && std::fabs(std::log(stat_.f0out / stat_.f0in)) > 0.15;
    if (rho > 0.92 && lastClarity >= 0.75 && shifted) leakN++; else leakN = std::max(0, leakN - 2);
    if (rOut < 0.05 * rIn) deadN++; else deadN = std::max(0, deadN - 2);
    if (leakN > 60 || deadN > 80) { stat_.heal++; hardReset(); }
  }

  void hardReset() {
    hx1 = hx2 = hy1 = hy2 = lx1 = lx2 = ly1 = ly2 = 0;
    std::fill(fTag.begin(), fTag.end(), -1);
    std::fill(fV.begin(), fV.end(), 0);
    if (!std::isfinite(mu)) { mu = std::log(125.0); muN = 0; }
    lnT = std::log(sr_ / 120.0); accD = 0; cntD = 0;
    leakN = 0; deadN = 0;
    muteN = (int)jround(0.05 * sr_);
    wake();
  }

  void wake() {
    idle = false;
    std::fill(ob.begin(), ob.end(), 0.f);
    ts = (double)(n - Lq);
    emitted = n - Lq;
    trk.active = false;
    vs = false; vc = 0; uc = 0; Tprev = 0; hn = 0;
    kLast = n / HOP - 1;
    mptr = mcount;
  }

  void reset() {
    std::fill(ob.begin(), ob.end(), 0.f);
    ts = (double)(n - Lq); emitted = n - Lq;
    trk.active = false; vs = false; vc = 0; uc = 0; Tprev = 0; hn = 0;
    hx1 = hx2 = hy1 = hy2 = lx1 = lx2 = ly1 = ly2 = 0;
  }

  void push(double x) {
    if (!std::isfinite(x)) x = 0;      // NaN/Inf -> hening (tambahan dari versi JS)
    else if (x > 8) x = 8; else if (x < -8) x = -8;
    const int i = (int)(n & RM);
    xr[i] = (float)x;
    const double h = hb0 * x + hb1 * hx1 + hb2 * hx2 - ha1 * hy1 - ha2 * hy2;
    hx2 = hx1; hx1 = x; hy2 = hy1; hy1 = h;
    const double y = lb0 * h + lb1 * lx1 + lb2 * lx2 - la1 * ly1 - la2 * ly2;
    lx2 = lx1; lx1 = h; ly2 = ly1; ly1 = y;
    xl[i] = (float)y;
    accD += y;
    if (++cntD == D) { xd[(int)(nd & RM)] = (float)(accD / D); nd++; accD = 0; cntD = 0; }
    n++;
  }

  // ---------------------------------------------------------------- analisis nada
  struct Cand { double tau, v; };

  void analyze() {
    const int64_t k = n / HOP;
    const int need = W + tauMax;
    bool haveCand = false; Cand cand{0, 0};
    double rmsB = 0;
    if (nd >= need + 4) {
      const int64_t st = nd - need;
      for (int i = 0; i < need; i++) seg[i] = xd[(int)((st + i) & RM)];
      double eB = 0;
      for (int j = 0; j < W; j++) { const double v = seg[tauMax + j]; eB += v * v; }
      rmsB = std::sqrt(eB / W);
      double eA = 0;
      { const int b = tauMax - tauMin; for (int j = 0; j < W; j++) { const double v = seg[b + j]; eA += v * v; } }
      for (int tau = tauMin; tau <= tauMax; tau++) {
        const int b = tauMax - tau;
        if (tau > tauMin) { const double a = seg[b], r = seg[b + W]; eA += a * a - r * r; }
        double dot = 0;
        for (int j = 0; j < W; j++) dot += (double)seg[b + j] * (double)seg[tauMax + j];
        nsdf[tau] = (float)(2 * dot / (eA + eB + 1e-12));
      }
      if (rmsB > 0.0007) haveCand = pickPeak(cand);
    }

    const double thr = vs ? V_STAY : V_ENTER;
    bool ok = haveCand && cand.v >= thr;
    if (ok && vs && Tprev > 0) {
      const double dj = std::fabs(std::log(cand.tau * D / Tprev));
      if ((cand.v < V_SURE && dj > 0.15) || (cand.v < 0.8 && dj > 0.35)) ok = false;
    }
    lastClarity = haveCand ? cand.v : 0;
    if (ok) { vc++; uc = 0; } else { uc++; vc = 0; }
    bool entering = false;
    if (!vs && vc >= 2) { vs = true; entering = true; run++; }
    else if (vs && uc >= V_HANG) { vs = false; Tprev = 0; }

    if (ok) {
      const double lt = std::log(cand.tau * D);
      if (entering) { hist[0] = hist[1] = hist[2] = lt; lnT = lt; }
      else { hist[0] = hist[1]; hist[1] = hist[2]; hist[2] = lt; }
      const double a = hist[0], b = hist[1], c = hist[2];
      const double med = std::max(std::min(a, b), std::min(std::max(a, b), c));
      lnT += (entering ? 1 : 0.4) * (med - lnT);
      lnT = clampd(lnT, std::log(sr_ / 500.0), std::log(Tmax));
      Tprev = std::exp(lnT);
      if (vs && cand.v >= 0.6) {
        const double lf = std::log((double)sr_) - lnT;
        if (std::fabs(lf - mu) < 0.6) {
          muN++;
          mu += (lf - mu) / std::min(4 + muN, 3000);
        }
      }
    }

    const double T = Tprev ? Tprev : std::exp(lnT);
    const int slot = (int)(k & FM);
    fTag[slot] = (int32_t)k; fV[slot] = vs ? 1 : 0; fT[slot] = (float)T; fRun[slot] = run;
    kLast = k;
    stat_.voiced = vs ? 1 : 0;
    if (vs) { stat_.f0in = sr_ / T; stat_.f0out = stat_.f0in * ratio(T); }

    track((double)(n - dc), T, vs, entering);
  }

  bool pickPeak(Cand& out) {
    float keysT[32], keysV[32];
    int nk = 0, tau = tauMin;
    while (tau < tauMax && nsdf[tau] > 0) tau++;
    while (tau < tauMax && nk < 32) {
      while (tau < tauMax && nsdf[tau] <= 0) tau++;
      int pk = -1; double pv = -1;
      while (tau < tauMax && nsdf[tau] > 0) { if (nsdf[tau] > pv) { pv = nsdf[tau]; pk = tau; } tau++; }
      if (pk > tauMin && pk < tauMax - 1) {
        const double a = nsdf[pk - 1], b = nsdf[pk], c = nsdf[pk + 1];
        const double den = a - 2 * b + c;
        const double off = den < -1e-9 ? 0.5 * (a - c) / den : 0;
        keysT[nk] = (float)(pk + clampd(off, -1, 1));
        keysV[nk] = (float)(b - 0.25 * (a - c) * off);
        nk++;
      }
    }
    if (!nk) return false;
    double vmax = 0;
    for (int i = 0; i < nk; i++) if (keysV[i] > vmax) vmax = keysV[i];
    if (vs && Tprev > 0) {
      int li = -1; double lv = -1;
      for (int i = 0; i < nk; i++) {
        if (std::fabs(std::log(keysT[i] * D / Tprev)) < 0.12 && keysV[i] > lv) { lv = keysV[i]; li = i; }
      }
      if (li >= 0 && lv >= 0.7 * vmax) { out = {keysT[li], lv}; return true; }
    }
    const double lim = 0.72 * vmax;
    int bi = -1; double bd = 1e9;
    for (int i = 0; i < nk; i++) {
      if (keysV[i] < lim) continue;
      if (vs && Tprev > 0) {
        const double d = std::fabs(std::log(keysT[i] * D / Tprev));
        if (d < bd) { bd = d; bi = i; }
      } else { bi = i; break; }
    }
    if (bi < 0) return false;
    out = {keysT[bi], keysV[bi]};
    return true;
  }

  // ---------------------------------------------------------------- pitch mark
  void track(double c, double T, bool voiced, bool entering) {
    if (!voiced) { trk.active = false; return; }
    if (entering || !trk.active) {
      const int64_t a = (int64_t)std::floor(c - T), b = (int64_t)std::floor(c);
      if (a <= n - RING + 64) return;
      double mx = -1e9, mn = 1e9; int64_t imx = a, imn = a;
      for (int64_t q = a; q <= b; q++) {
        const double v = xl[(int)(q & RM)];
        if (v > mx) { mx = v; imx = q; }
        if (v < mn) { mn = v; imn = q; }
      }
      trk.pol = mx >= -mn ? 1 : -1;
      trk.last = (double)(trk.pol > 0 ? imx : imn);
      trk.active = true;
      pushMark(trk.last, T);
    }
    int guard = 0;
    while (guard++ < 8) {
      const double pred = trk.last + T;
      if (pred > c + HOP) break;
      const double q = findNext(trk.last, T, pred, trk.pol);
      if (q < 0) break;
      trk.last = q;
      pushMark(q, T);
    }
  }

  void pushMark(double pos, double T) {
    const int i = (int)(mcount & MM);
    mPos[i] = pos; mPer[i] = (float)T; mRun[i] = run;
    mcount++;
  }

  double findNext(double lastD, double T, double pred, int pol) {
    const int64_t last = (int64_t)lastD;   // posisi selalu bulat
    const int h = (int)clampd(std::floor(0.3 * T), 8, 1000);
    const int range = std::max(4, (int)std::floor(0.25 * T));
    const int64_t pr = (int64_t)jround(pred);
    const int64_t lo = pr - range, hi = pr + range;
    if (hi + h + 2 >= n || last - h - 2 <= n - RING + 64) return -1;
    double er = 0;
    for (int j = -h; j <= h; j++) { const double v = xl[(int)((last + j) & RM)]; ref[j + h] = (float)v; er += v * v; }
    if (er < 1e-12) return (double)pr;
    auto score = [&](int64_t q) {
      double dot = 0, ec = 0;
      for (int j = -h; j <= h; j++) { const double v = xl[(int)((q + j) & RM)]; dot += (double)ref[j + h] * v; ec += v * v; }
      const double d = (double)(q - pr) / range;
      return dot / std::sqrt(er * ec + 1e-12) - 0.15 * d * d;
    };
    double best = -9; int64_t bq = pr;
    for (int64_t q = lo; q <= hi; q += 2) { const double s = score(q); if (s > best) { best = s; bq = q; } }
    for (int64_t q = bq - 1; q <= bq + 1; q += 2) { if (q < lo || q > hi) continue; const double s = score(q); if (s > best) { best = s; bq = q; } }
    const int sn = std::max(2, (int)jround(0.12 * T));
    int64_t pk = bq; double pv = pol * (double)xl[(int)(bq & RM)];
    for (int64_t q = bq - sn; q <= bq + sn; q++) { const double v = pol * (double)xl[(int)(q & RM)]; if (v > pv) { pv = v; pk = q; } }
    if ((double)pk <= (double)last + 0.5 * T) pk = (int64_t)jround((double)last + T);
    return (double)pk;
  }

  // ---------------------------------------------------------------- sintesis
  double ratio(double T) const {
    const double F0 = sr_ / T;
    double target;
    if (P.rel) target = std::exp(mu) * std::pow(2.0, (P.relSemi + P.tune) / 12);
    else target = P.f0 * std::pow(2.0, P.tune / 12);
    const double lo = clampd(std::log(target) + P.inton * (std::log(F0) - mu), std::log(60.0), std::log(1000.0));
    return clampd(std::exp(lo) / F0, 0.45, 6);
  }

  int64_t nearestMark(double tsv, int runv, double T) {
    if (mcount == 0) return -1;
    const int64_t lowest = std::max<int64_t>(0, mcount - MRING + 4);
    int64_t i = std::min(std::max(mptr, lowest), mcount - 1);
    while (i + 1 < mcount && std::fabs(mPos[(int)((i + 1) & MM)] - tsv) <= std::fabs(mPos[(int)(i & MM)] - tsv)) i++;
    while (i - 1 >= lowest && std::fabs(mPos[(int)((i - 1) & MM)] - tsv) < std::fabs(mPos[(int)(i & MM)] - tsv)) i--;
    mptr = i;
    if (mRun[(int)(i & MM)] != runv) return -1;
    if (std::fabs(mPos[(int)(i & MM)] - tsv) > 0.8 * T) return -1;
    return i;
  }

  void synth(double tsLimit) {
    int guard = 0;
    while (ts < tsLimit && guard++ < 200) {
      const double tsv = ts;
      const int64_t kf = (int64_t)std::floor((tsv + dc) / HOP);
      bool voiced = false; double T = 0; int runv = -1;
      if (kf <= kLast && kf > kLast - FRING + 8 && fTag[(int)(kf & FM)] == (int32_t)kf) {
        voiced = fV[(int)(kf & FM)] == 1; T = fT[(int)(kf & FM)]; runv = fRun[(int)(kf & FM)];
      } else if (tsv + dc > (double)n) {
        stat_.underrun++;
      }
      if (voiced) {
        const int64_t mi = nearestMark(tsv, runv, T);
        if (mi >= 0) {
          const double m = mPos[(int)(mi & MM)];
          const double Tm = mPer[(int)(mi & MM)];
          const double f = P.formant, p = ratio(T);
          const int Hin = (int)jround(std::min(Tm, T * 1.25));
          const int Hout = std::min(HW, std::max(8, (int)jround(Hin / f)));
          if (m + Hin + 4 < (double)n && m - Hin - 4 > (double)(n - RING + 64)) {
            grain(tsv, m, Hout, f, 1.15 * std::sqrt(f / p));
            ts = tsv + T / p;
            continue;
          }
        }
      }
      if (voiced) {
        const double f = P.formant, p = ratio(T);
        const int Hin = (int)jround(std::min(T, (double)HW));
        const int Hout = std::min(HW, std::max(8, (int)jround(Hin / f)));
        const double c = jround(tsv);
        if (c + Hin + 4 < (double)n && c - Hin - 4 > (double)(n - RING + 64)) {
          grain(tsv, c, Hout, f, 1.15 * std::sqrt(f / p));
          ts = tsv + T / p;
          continue;
        }
      }
      const int H = voiced ? std::min(HW, std::max(16, (int)jround(T))) : Hu;
      grain(tsv, tsv, H, 1, 1);
      ts = tsv + H;
    }
  }

  void grain(double tsv, double src, int H, double f, double gain) {
    const int64_t ti = (int64_t)std::floor(tsv);
    const double fr = tsv - (double)ti;
    const double pi = M_PI / (H + 1);
    const int64_t lowIdx = n - RING + 8;
    const int64_t first = std::max<int64_t>(-H, emitted - ti);
    for (int64_t k = first; k <= H; k++) {
      const double w = 0.5 + 0.5 * std::cos(pi * (double)k);
      const double r = src + ((double)k - fr) * f;
      const int64_t i0 = (int64_t)std::floor(r);
      if (i0 + 2 >= n || i0 - 1 < lowIdx) continue;
      const double u = r - (double)i0;
      const double a = xr[(int)((i0 - 1) & RM)], b = xr[(int)(i0 & RM)], c = xr[(int)((i0 + 1) & RM)], d = xr[(int)((i0 + 2) & RM)];
      const double s = b + 0.5 * u * (c - a + u * (2 * a - 5 * b + 4 * c - d + u * (3 * (b - c) + d - a)));
      const int oi = (int)((ti + k) & RM);
      ob[oi] = (float)((double)ob[oi] + gain * w * s);
    }
  }

  // ---- keadaan ----
  int sr_;
  int D = 1, tauMin = 4, tauMax = 0, W = 192, Lq = 0, HW = 0, dc = 0, Hu = 0, LqMin = 0;
  double srd = 0, Tmax = 0;
  std::vector<float> seg, nsdf, xr, xl, xd, ob;
  int64_t n = 0, nd = 0;
  double accD = 0; int cntD = 0;
  double hb0 = 0, hb1 = 0, hb2 = 0, ha1 = 0, ha2 = 0, lb0 = 0, lb1 = 0, lb2 = 0, la1 = 0, la2 = 0;
  double hx1 = 0, hx2 = 0, hy1 = 0, hy2 = 0, lx1 = 0, lx2 = 0, ly1 = 0, ly2 = 0;
  std::vector<int32_t> fTag; std::vector<uint8_t> fV; std::vector<float> fT; std::vector<int32_t> fRun;
  int64_t kLast = -1;
  bool vs = false; int vc = 0, uc = 0;
  double lnT = 0, Tprev = 0, hist[3] = {0, 0, 0}; int hn = 0;
  double mu = 0; int muN = 0;
  int run = 0;
  double lastClarity = 0;
  std::vector<double> mPos; std::vector<float> mPer; std::vector<int32_t> mRun;
  int64_t mcount = 0, mptr = 0;
  struct Trk { bool active = false; double last = 0; int pol = 1; } trk;
  std::vector<float> ref;
  double ts = 0; int64_t emitted = 0;
  double mix = 0; int mixTarget = 0;
  bool idle = true;
  Params P;
  Stat stat_;
  int muteN = 0;
  bool autoHeal = true;
  int leakN = 0, deadN = 0;
};

}  // namespace mlv
__MLV_FILE_END__
mkdir -p "$(dirname "native/src/main.cpp")"
cat > 'native/src/main.cpp' <<'__MLV_FILE_END__'
// MochiLyn Voice - modul Zygisk (author: MochiLyn)
//
// Alur kerja:
//  - Di tiap app yang baru dibuka, modul bertanya ke proses "companion" (root) apakah app itu ada di daftar
//    /data/adb/mochilyn_voice/apps.txt. Kalau tidak, modul langsung melepas diri dari app itu (tanpa jejak).
//  - Kalau ya, modul mengganti fungsi baca mikrofon Java (android.media.AudioRecord.native_read_*): data asli dibaca dulu
//    oleh sistem, lalu diubah oleh mesin suara (engine.hpp), baru diserahkan ke app.
//  - Pengaturan (preset, nada, delay) dibaca companion dari /data/adb/mochilyn_voice/config.txt dan dikirim
//    ke app tiap ~1 detik, jadi ganti preset berlaku tanpa restart app.
//  - Aman-gagal: kalau ada yang salah (companion mati, hook tidak ketemu, mesin error), suara asli dilewatkan apa adanya.
#include <android/log.h>
#include <jni.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "engine.hpp"
#include "zygisk.hpp"

#define TAG "MochiLynVoice"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

#ifndef MLV_DIR
#define MLV_DIR "/data/adb/mochilyn_voice"
#endif
static const char* kDir = MLV_DIR;
static const uint32_t kMagic = 0x4D4C5631;   // "MLV1"

// ---------------------------------------------------------------------------------------------- protokol
struct Msg {
  uint32_t magic;
  uint8_t enabled;   // app ini boleh dihook (hanya relevan untuk balasan pertama)
  uint8_t active;    // preset mengubah suara (false = Normal/mati)
  uint8_t rel;       // true: nada = rata-rata pembicara + relSemi
  uint8_t autoheal;
  float f0, formant, inton, tune, relSemi, delay;
  uint32_t refreshN;
};

static bool readn(int fd, void* buf, size_t n) {
  char* p = (char*)buf;
  while (n) { ssize_t r = read(fd, p, n); if (r < 0 && errno == EINTR) continue; if (r <= 0) return false; p += r; n -= (size_t)r; }
  return true;
}
static bool writen(int fd, const void* buf, size_t n) {
  const char* p = (const char*)buf;
  while (n) { ssize_t r = write(fd, p, n); if (r < 0 && errno == EINTR) continue; if (r <= 0) return false; p += r; n -= (size_t)r; }
  return true;
}

// ---------------------------------------------------------------------------------------------- sisi companion (root)
struct Preset { const char* key; bool active, rel; float f0, formant, inton, relSemi; };
static const Preset kPresets[] = {
    {"plus11", true, true, 205, 1.18f, 1.1f, 11},   // Cewe natural, +11 semitone dari nada asli pembicara
    {"natural", true, false, 205, 1.18f, 1.1f, 0},  // sama dengan preset "Cewek natural" di Sambung
    {"teen", true, false, 225, 1.17f, 1.0f, 0},
    {"onee", true, false, 190, 1.12f, 0.9f, 0},
    {"anime", true, false, 250, 1.22f, 1.2f, 0},
    {"normal", false, false, 205, 1.18f, 1.1f, 0},
};

static std::string trim(std::string s) {
  size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
  return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

static Msg loadConfig() {
  Msg m;
  memset(&m, 0, sizeof m);
  m.magic = kMagic;
  std::string preset = "plus11";
  int enabled = 1, autoheal = 1;
  float tune = 0, delay = 45;
  uint32_t refreshN = 0;
  if (FILE* f = fopen((std::string(kDir) + "/config.txt").c_str(), "r")) {
    char line[256];
    while (fgets(line, sizeof line, f)) {
      std::string s = trim(line);
      if (s.empty() || s[0] == '#') continue;
      size_t eq = s.find('=');
      if (eq == std::string::npos) continue;
      std::string k = trim(s.substr(0, eq)), v = trim(s.substr(eq + 1));
      if (k == "preset") preset = v;
      else if (k == "enabled") enabled = atoi(v.c_str());
      else if (k == "autoheal") autoheal = atoi(v.c_str());
      else if (k == "tune") tune = (float)atof(v.c_str());
      else if (k == "delay") delay = (float)atof(v.c_str());
      else if (k == "refresh") refreshN = (uint32_t)strtoul(v.c_str(), nullptr, 10);
    }
    fclose(f);
  }
  const Preset* p = &kPresets[0];
  for (const Preset& q : kPresets) if (preset == q.key) { p = &q; break; }
  m.active = (enabled && p->active) ? 1 : 0;
  m.rel = p->rel; m.autoheal = autoheal ? 1 : 0;
  m.f0 = p->f0; m.formant = p->formant; m.inton = p->inton; m.relSemi = p->relSemi;
  m.tune = tune; m.delay = delay; m.refreshN = refreshN;
  return m;
}

static bool appAllowed(const std::string& proc, int uid) {
  if (uid < 10000) return false;                // jangan sentuh proses sistem
  FILE* f = fopen((std::string(kDir) + "/apps.txt").c_str(), "r");
  if (!f) return false;
  bool ok = false;
  char line[256];
  while (!ok && fgets(line, sizeof line, f)) {
    std::string s = trim(line);
    if (s.empty() || s[0] == '#') continue;
    if (s == "*") ok = true;
    else if (proc == s || (proc.size() > s.size() && proc.compare(0, s.size(), s) == 0 && proc[s.size()] == ':')) ok = true;  // com.app atau com.app:proses
  }
  fclose(f);
  return ok;
}

static bool readString(int fd, std::string& out) {
  uint32_t len = 0;
  if (!readn(fd, &len, 4) || len > 512) return false;
  out.assign(len, '\0');
  return len == 0 || readn(fd, &out[0], len);
}

static void companionHandler(int fd) {
  std::string proc;
  int32_t uid = 0;
  if (!readString(fd, proc) || !readn(fd, &uid, 4)) { close(fd); return; }
  Msg m = loadConfig();
  m.enabled = (appAllowed(proc, uid) && access(kDir, F_OK) == 0) ? 1 : 0;
  if (!writen(fd, &m, sizeof m)) { close(fd); return; }
  if (!m.enabled) { close(fd); return; }
  for (;;) {
    char cmd;
    if (!readn(fd, &cmd, 1)) break;
    if (cmd == 'C') {
      Msg c = loadConfig();
      c.enabled = 1;
      if (!writen(fd, &c, sizeof c)) break;
    } else if (cmd == 'H') {   // app melapor: hook mikrofon berhasil dipakai
      std::string info;
      if (!readString(fd, info)) break;
      mkdir((std::string(kDir) + "/status").c_str(), 0755);
      std::string name = proc;
      for (char& ch : name) if (ch == ':' || ch == '/') ch = '_';
      if (FILE* f = fopen((std::string(kDir) + "/status/" + name + ".txt").c_str(), "w")) {
        fprintf(f, "%s\nwaktu_unix=%ld\n", info.c_str(), (long)time(nullptr));
        fclose(f);
      }
    } else break;
  }
  close(fd);
}

// ---------------------------------------------------------------------------------------------- sisi app
static std::mutex g_mu;
static Msg g_msg;                       // konfigurasi terbaru (dilindungi g_mu)
static std::atomic<int> g_hit{0};       // 1 = ada laporan "hook berhasil" yang belum dikirim
static std::string g_hitInfo;           // dilindungi g_mu
static std::string g_proc;
static int g_fd = -1;

static jclass g_clsSys = nullptr;
static jmethodID g_mHash = nullptr, g_mSr = nullptr, g_mCh = nullptr, g_mFmt = nullptr;

static jint (*o_byte)(JNIEnv*, jobject, jbyteArray, jint, jint, jboolean) = nullptr;
static jint (*o_short)(JNIEnv*, jobject, jshortArray, jint, jint, jboolean) = nullptr;
static jint (*o_float)(JNIEnv*, jobject, jfloatArray, jint, jint, jboolean) = nullptr;
static jint (*o_direct)(JNIEnv*, jobject, jobject, jint, jboolean) = nullptr;

struct Slot {
  int key = 0, sr = 0, ch = 0, fmt = 0;
  std::unique_ptr<mlv::VoiceEngine> eng;
  uint64_t used = 0;
  uint32_t refreshSeen = 0;
  bool reported = false;
};
static Slot g_slots[4];
static uint64_t g_tick = 0;

static int qint(JNIEnv* env, jobject o, jmethodID m) {
  int v = env->CallIntMethod(o, m);
  if (env->ExceptionCheck()) { env->ExceptionClear(); return -1; }
  return v;
}

// Ambil/siapkan mesin untuk satu objek AudioRecord. Dipanggil dengan g_mu terkunci.
static Slot* slotFor(JNIEnv* env, jobject thiz) {
  int key = env->CallStaticIntMethod(g_clsSys, g_mHash, thiz);
  if (env->ExceptionCheck()) { env->ExceptionClear(); return nullptr; }
  Slot* s = nullptr;
  for (Slot& x : g_slots) if (x.eng && x.key == key) { s = &x; break; }
  if (!s) {
    Slot* old = &g_slots[0];
    for (Slot& x : g_slots) { if (!x.eng) { old = &x; break; } if (x.used < old->used) old = &x; }
    s = old;
    s->eng.reset();
    s->key = key; s->sr = qint(env, thiz, g_mSr); s->ch = qint(env, thiz, g_mCh); s->fmt = qint(env, thiz, g_mFmt);
    s->reported = false;
    if (s->sr < 8000 || s->sr > 96000 || s->ch < 1 || s->ch > 2 || (s->fmt != 2 && s->fmt != 4)) { s->sr = 0; return nullptr; }  // hanya PCM16 / float
    s->eng.reset(new mlv::VoiceEngine(s->sr));
    s->refreshSeen = g_msg.refreshN;
  }
  s->used = ++g_tick;
  return s->sr ? s : nullptr;
}

static void applyConfig(Slot* s) {
  mlv::Params p;
  p.f0 = g_msg.f0; p.formant = g_msg.formant; p.inton = g_msg.inton; p.tune = g_msg.tune;
  p.rel = g_msg.rel != 0; p.relSemi = g_msg.relSemi;
  s->eng->setParams(p);
  s->eng->setActive(g_msg.active != 0);
  s->eng->setAutoHeal(g_msg.autoheal != 0);
  s->eng->setDelayMs(g_msg.delay);
  if (g_msg.refreshN != s->refreshSeen) { s->refreshSeen = g_msg.refreshN; s->eng->refresh(); }
}

// frames: jumlah frame (tiap frame = ch sampel). Format PCM16 atau float, interleaved.
template <typename T> static void processBuffer(Slot* s, T* data, int frames);
template <> void processBuffer<int16_t>(Slot* s, int16_t* d, int frames) {
  float in[2048], out[2048];
  const int ch = s->ch;
  for (int off = 0; off < frames; off += 2048) {
    const int n = std::min(2048, frames - off);
    for (int i = 0; i < n; i++) {
      int sum = 0;
      for (int c = 0; c < ch; c++) sum += d[(size_t)(off + i) * ch + c];
      in[i] = (float)sum / (float)ch / 32768.f;
    }
    s->eng->process(in, out, n);
    for (int i = 0; i < n; i++) {
      float v = out[i] * 32768.f;
      v = v > 32767.f ? 32767.f : (v < -32768.f ? -32768.f : v);
      const int16_t q = (int16_t)(v >= 0 ? v + 0.5f : v - 0.5f);
      for (int c = 0; c < ch; c++) d[(size_t)(off + i) * ch + c] = q;
    }
  }
}
template <> void processBuffer<float>(Slot* s, float* d, int frames) {
  float in[2048], out[2048];
  const int ch = s->ch;
  for (int off = 0; off < frames; off += 2048) {
    const int n = std::min(2048, frames - off);
    for (int i = 0; i < n; i++) {
      float sum = 0;
      for (int c = 0; c < ch; c++) sum += d[(size_t)(off + i) * ch + c];
      in[i] = sum / (float)ch;
    }
    s->eng->process(in, out, n);
    for (int i = 0; i < n; i++) for (int c = 0; c < ch; c++) d[(size_t)(off + i) * ch + c] = out[i];
  }
}

// Titik masuk bersama. Mengembalikan true kalau data diubah. fmtWanted: 2 = PCM16, 4 = float.
template <typename T>
static bool transformAudio(JNIEnv* env, jobject thiz, T* data, int count, int fmtWanted) {
  std::lock_guard<std::mutex> lk(g_mu);
  Slot* s = slotFor(env, thiz);
  if (!s || s->fmt != fmtWanted) return false;
  if (!g_msg.active && s->eng->isIdle()) return false;     // Normal/mati: jangan sentuh data sama sekali
  applyConfig(s);
  const int frames = count / s->ch;
  if (frames <= 0) return false;
  processBuffer<T>(s, data, frames);
  if (!s->reported) {
    s->reported = true;
    char b[200];
    snprintf(b, sizeof b, "Java AudioRecord terhubung: proses=%s sr=%d ch=%d format=%s", g_proc.c_str(), s->sr, s->ch, s->fmt == 2 ? "PCM16" : "float");
    LOGI("%s", b);
    g_hitInfo = b;
    g_hit.store(1);
  }
  return true;
}

static thread_local std::vector<int16_t> t_s16;
static thread_local std::vector<float> t_f32;

static jint h_byte(JNIEnv* env, jobject thiz, jbyteArray arr, jint off, jint size, jboolean blocking) {
  if (!o_byte) return -3;
  jint r = o_byte(env, thiz, arr, off, size, blocking);
  if (r <= 1 || env->ExceptionCheck() || !arr) return r;
  try {
    const int samples = r / 2;
    if (t_s16.size() < (size_t)samples) t_s16.resize((size_t)samples);
    env->GetByteArrayRegion(arr, off, samples * 2, reinterpret_cast<jbyte*>(t_s16.data()));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return r; }
    if (transformAudio<int16_t>(env, thiz, t_s16.data(), samples, 2)) env->SetByteArrayRegion(arr, off, samples * 2, reinterpret_cast<const jbyte*>(t_s16.data()));
  } catch (...) {}
  return r;
}

static jint h_short(JNIEnv* env, jobject thiz, jshortArray arr, jint off, jint size, jboolean blocking) {
  if (!o_short) return -3;
  jint r = o_short(env, thiz, arr, off, size, blocking);
  if (r <= 0 || env->ExceptionCheck() || !arr) return r;
  try {
    if (t_s16.size() < (size_t)r) t_s16.resize((size_t)r);
    env->GetShortArrayRegion(arr, off, r, reinterpret_cast<jshort*>(t_s16.data()));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return r; }
    if (transformAudio<int16_t>(env, thiz, t_s16.data(), r, 2)) env->SetShortArrayRegion(arr, off, r, reinterpret_cast<const jshort*>(t_s16.data()));
  } catch (...) {}
  return r;
}

static jint h_float(JNIEnv* env, jobject thiz, jfloatArray arr, jint off, jint size, jboolean blocking) {
  if (!o_float) return -3;
  jint r = o_float(env, thiz, arr, off, size, blocking);
  if (r <= 0 || env->ExceptionCheck() || !arr) return r;
  try {
    if (t_f32.size() < (size_t)r) t_f32.resize((size_t)r);
    env->GetFloatArrayRegion(arr, off, r, t_f32.data());
    if (env->ExceptionCheck()) { env->ExceptionClear(); return r; }
    if (transformAudio<float>(env, thiz, t_f32.data(), r, 4)) env->SetFloatArrayRegion(arr, off, r, t_f32.data());
  } catch (...) {}
  return r;
}

static jint h_direct(JNIEnv* env, jobject thiz, jobject buf, jint size, jboolean blocking) {
  if (!o_direct) return -3;
  jint r = o_direct(env, thiz, buf, size, blocking);
  if (r <= 1 || env->ExceptionCheck() || !buf) return r;
  try {
    void* p = env->GetDirectBufferAddress(buf);
    if (!p || (reinterpret_cast<uintptr_t>(p) & 1)) return r;
    // format diketahui dari slot: coba PCM16 dulu, lalu float
    int key = env->CallStaticIntMethod(g_clsSys, g_mHash, thiz);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return r; }
    int fmt = 0;
    { std::lock_guard<std::mutex> lk(g_mu); for (Slot& x : g_slots) if (x.eng && x.key == key) fmt = x.fmt; }
    if (!fmt) fmt = qint(env, thiz, g_mFmt);
    if (fmt == 2) transformAudio<int16_t>(env, thiz, static_cast<int16_t*>(p), r / 2, 2);
    else if (fmt == 4 && (reinterpret_cast<uintptr_t>(p) & 3) == 0) transformAudio<float>(env, thiz, static_cast<float*>(p), r / 4, 4);
  } catch (...) {}
  return r;
}

static void* pollThread(void*) {
  for (;;) {
    struct timespec ts = {1, 0};
    nanosleep(&ts, nullptr);
    if (g_fd < 0) return nullptr;
    if (g_hit.exchange(0)) {
      std::string info;
      { std::lock_guard<std::mutex> lk(g_mu); info = g_hitInfo; }
      uint32_t len = (uint32_t)info.size();
      char cmd = 'H';
      if (!writen(g_fd, &cmd, 1) || !writen(g_fd, &len, 4) || !writen(g_fd, info.data(), len)) return nullptr;
    }
    char cmd = 'C';
    Msg m;
    if (!writen(g_fd, &cmd, 1) || !readn(g_fd, &m, sizeof m) || m.magic != kMagic) return nullptr;   // companion hilang: pakai konfigurasi terakhir
    std::lock_guard<std::mutex> lk(g_mu);
    g_msg = m;
  }
}

class MochiModule : public zygisk::ModuleBase {
 public:
  void onLoad(zygisk::Api* api, JNIEnv* env) override { api_ = api; env_ = env; }

  void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
    enabled_ = false;
    std::string proc;
    if (args->nice_name) {
      const char* n = env_->GetStringUTFChars(args->nice_name, nullptr);
      if (n) { proc = n; env_->ReleaseStringUTFChars(args->nice_name, n); }
    }
    if (!proc.empty()) {
      int fd = api_->connectCompanion();
      if (fd >= 0) {
        uint32_t len = (uint32_t)proc.size();
        int32_t uid = (int32_t)args->uid;
        Msg m;
        struct timeval tv = {3, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        if (writen(fd, &len, 4) && writen(fd, proc.data(), len) && writen(fd, &uid, 4) && readn(fd, &m, sizeof m) &&
            m.magic == kMagic && m.enabled) {
          g_msg = m; g_proc = proc; g_fd = fd; enabled_ = true;
        } else {
          close(fd);
        }
      }
    }
    if (!enabled_) api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);   // app lain: lepas modul sepenuhnya
  }

  void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
    if (!enabled_) return;
    if (!installHooks()) {
      LOGW("hook AudioRecord gagal dipasang di %s, suara asli dibiarkan", g_proc.c_str());
      close(g_fd); g_fd = -1;
      return;
    }
    pthread_t th;
    if (pthread_create(&th, nullptr, pollThread, nullptr) == 0) pthread_detach(th);
    LOGI("aktif di %s", g_proc.c_str());
  }

  void preServerSpecialize(zygisk::ServerSpecializeArgs*) override {
    api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);   // jangan masuk ke system_server
  }

 private:
  bool installHooks() {
    jclass ar = env_->FindClass("android/media/AudioRecord");
    jclass sys = env_->FindClass("java/lang/System");
    if (!ar || !sys) { env_->ExceptionClear(); return false; }
    g_mSr = env_->GetMethodID(ar, "getSampleRate", "()I");
    g_mCh = env_->GetMethodID(ar, "getChannelCount", "()I");
    g_mFmt = env_->GetMethodID(ar, "getAudioFormat", "()I");
    g_mHash = env_->GetStaticMethodID(sys, "identityHashCode", "(Ljava/lang/Object;)I");
    if (env_->ExceptionCheck()) env_->ExceptionClear();
    if (!g_mSr || !g_mCh || !g_mFmt || !g_mHash) return false;
    g_clsSys = (jclass)env_->NewGlobalRef(sys);
    if (!g_clsSys) return false;

    JNINativeMethod ms[4] = {
        {const_cast<char*>("native_read_in_byte_array"), const_cast<char*>("([BIIZ)I"), (void*)h_byte},
        {const_cast<char*>("native_read_in_short_array"), const_cast<char*>("([SIIZ)I"), (void*)h_short},
        {const_cast<char*>("native_read_in_float_array"), const_cast<char*>("([FIIZ)I"), (void*)h_float},
        {const_cast<char*>("native_read_in_direct_buffer"), const_cast<char*>("(Ljava/lang/Object;IZ)I"), (void*)h_direct},
    };
    api_->hookJniNativeMethods(env_, "android/media/AudioRecord", ms, 4);
    // setelah pemanggilan, fnPtr berisi fungsi ASLI (nullptr kalau metode tidak ketemu = tidak dihook)
    o_byte = reinterpret_cast<decltype(o_byte)>(ms[0].fnPtr);
    o_short = reinterpret_cast<decltype(o_short)>(ms[1].fnPtr);
    o_float = reinterpret_cast<decltype(o_float)>(ms[2].fnPtr);
    o_direct = reinterpret_cast<decltype(o_direct)>(ms[3].fnPtr);
    LOGI("hook: byte=%d short=%d float=%d direct=%d", o_byte != nullptr, o_short != nullptr, o_float != nullptr, o_direct != nullptr);
    return o_byte || o_short || o_float || o_direct;
  }

  zygisk::Api* api_ = nullptr;
  JNIEnv* env_ = nullptr;
  bool enabled_ = false;
};

REGISTER_ZYGISK_MODULE(MochiModule)
REGISTER_ZYGISK_COMPANION(companionHandler)
__MLV_FILE_END__
mkdir -p "$(dirname "module/module.prop")"
cat > 'module/module.prop' <<'__MLV_FILE_END__'
id=mochilyn_voice
name=MochiLyn Voice Changer
version=v0.1.0
versionCode=1
author=MochiLyn
description=Ubah suara mic jadi cewek natural (+11 semitone) di app pilihan (WhatsApp, Roblox) lewat Zygisk. Ganti preset: tombol Action di Magisk atau perintah mlv.
__MLV_FILE_END__
mkdir -p "$(dirname "module/customize.sh")"
cat > 'module/customize.sh' <<'__MLV_FILE_END__'
#!/system/bin/sh
# Installer MochiLyn Voice Changer (dijalankan oleh Magisk saat modul dipasang)
DATA=/data/adb/mochilyn_voice

ui_print "- MochiLyn Voice Changer v0.1.0 (by MochiLyn)"

# --- cek syarat; semua cek di sini hanya membatalkan pemasangan, tidak mengubah sistem ---
[ "$MAGISK_VER_CODE" -ge 24000 ] 2>/dev/null || abort "! Butuh Magisk 24 atau lebih baru (ada Zygisk)."
[ "$API" -ge 26 ] 2>/dev/null || abort "! Butuh Android 8.0 ke atas."
case "$ARCH" in
  arm64) ABI=arm64-v8a ;;
  arm)   ABI=armeabi-v7a ;;
  *)     abort "! Arsitektur $ARCH belum didukung." ;;
esac
[ -f "$MODPATH/zygisk/$ABI.so" ] || abort "! File zygisk/$ABI.so tidak ada. Zip ini belum dibuild: ambil zip hasil build (lihat README)."

ZY=$(magisk --sqlite "SELECT value FROM settings WHERE key='zygisk'" 2>/dev/null)
case "$ZY" in
  *value=1*) ui_print "- Zygisk: aktif" ;;
  *) ui_print "! Zygisk belum aktif. Magisk > Pengaturan > Zygisk (nyalakan), lalu reboot." ;;
esac

# --- folder data + berkas pengaturan (tidak menimpa punyamu kalau sudah ada) ---
mkdir -p "$DATA/status"
[ -f "$DATA/config.txt" ] || cp "$MODPATH/defaults/config.txt" "$DATA/config.txt"
[ -f "$DATA/apps.txt" ]   || cp "$MODPATH/defaults/apps.txt" "$DATA/apps.txt"
chmod 755 "$DATA" "$DATA/status"; chmod 644 "$DATA/config.txt" "$DATA/apps.txt"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/bin/mlv" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print "- Selesai. Preset bawaan: Cewe natural +11."
ui_print "- App aktif: lihat $DATA/apps.txt (bawaan: WhatsApp, WA Business, Roblox)."
ui_print "- Ganti preset: tombol Action modul ini di Magisk, atau 'su -c mlv next'."
ui_print "- Pastikan app tsb TIDAK ada di DenyList Magisk. Reboot dulu."
__MLV_FILE_END__
mkdir -p "$(dirname "module/action.sh")"
cat > 'module/action.sh' <<'__MLV_FILE_END__'
#!/system/bin/sh
# Tombol "Action" di aplikasi Magisk (Magisk 27+): ganti ke preset berikutnya.
MODDIR=${0%/*}
sh "$MODDIR/system/bin/mlv" next
sh "$MODDIR/system/bin/mlv" status
__MLV_FILE_END__
mkdir -p "$(dirname "module/uninstall.sh")"
cat > 'module/uninstall.sh' <<'__MLV_FILE_END__'
#!/system/bin/sh
rm -rf /data/adb/mochilyn_voice
__MLV_FILE_END__
mkdir -p "$(dirname "module/system/bin/mlv")"
cat > 'module/system/bin/mlv' <<'__MLV_FILE_END__'
#!/system/bin/sh
# mlv - kendali MochiLyn Voice Changer.  Pakai: su -c mlv <perintah>
D=/data/adb/mochilyn_voice
C=$D/config.txt
A=$D/apps.txt
ORDER="plus11 natural teen onee anime normal"

[ "$(id -u)" = "0" ] || { echo "Jalankan sebagai root: su -c mlv ..."; exit 1; }
[ -d "$D" ] || { echo "Folder $D belum ada. Pasang modul dulu."; exit 1; }
[ -f "$C" ] || touch "$C"

get() { sed -n "s/^$1=//p" "$C" | tail -n 1; }
put() {  # put kunci nilai
  T="$C.tmp"
  grep -v "^$1=" "$C" > "$T" 2>/dev/null
  echo "$1=$2" >> "$T"
  cat "$T" > "$C" && rm -f "$T"
}
nice() {
  case "$1" in
    plus11) echo "Cewe natural +11" ;; natural) echo "Cewek natural" ;; teen) echo "Cewe remaja" ;;
    onee) echo "Kakak (one-chan)" ;; anime) echo "Anime" ;; normal) echo "Normal (suara asli)" ;; *) echo "$1" ;;
  esac
}
valid() { for p in $ORDER; do [ "$p" = "$1" ] && return 0; done; return 1; }

case "$1" in
  next)
    cur=$(get preset); [ -n "$cur" ] || cur=plus11
    nxt=""; first=""; found=0
    for p in $ORDER; do
      [ -n "$first" ] || first=$p
      if [ $found = 1 ]; then nxt=$p; break; fi
      [ "$p" = "$cur" ] && found=1
    done
    [ -n "$nxt" ] || nxt=$first
    put preset "$nxt"; put enabled 1
    echo "Preset: $(nice $nxt)" ;;
  set)
    valid "$2" || { echo "Preset tidak dikenal. Pilihan: $ORDER"; exit 1; }
    put preset "$2"; put enabled 1; echo "Preset: $(nice $2)" ;;
  list)
    for p in $ORDER; do echo "$p  -  $(nice $p)"; done ;;
  tune)
    echo "$2" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$' || { echo "Pakai: mlv tune <-15..15>"; exit 1; }
    put tune "$2"; echo "Tune: $2 semitone" ;;
  delay)
    echo "$2" | grep -Eq '^[0-9]+$' || { echo "Pakai: mlv delay <35..200>"; exit 1; }
    [ "$2" -lt 35 ] && set -- delay 35; [ "$2" -gt 200 ] && set -- delay 200
    put delay "$2"; echo "Delay: $2 ms" ;;
  refresh)
    n=$(get refresh); [ -n "$n" ] || n=0; put refresh $((n + 1)); echo "Mesin suara di-refresh" ;;
  on)  put enabled 1; echo "Efek: NYALA" ;;
  off) put enabled 0; echo "Efek: MATI (suara asli)" ;;
  apps) grep -v '^#' "$A" | grep -v '^$' ;;
  add)
    [ -n "$2" ] || { echo "Pakai: mlv add <nama.paket>"; exit 1; }
    grep -qx "$2" "$A" 2>/dev/null || echo "$2" >> "$A"; echo "Ditambah: $2 (buka ulang app-nya)" ;;
  del)
    [ -n "$2" ] || { echo "Pakai: mlv del <nama.paket>"; exit 1; }
    grep -vx "$2" "$A" > "$A.tmp" && cat "$A.tmp" > "$A" && rm -f "$A.tmp"; echo "Dihapus: $2" ;;
  status|"")
    p=$(get preset); [ -n "$p" ] || p=plus11
    echo "Efek     : $([ "$(get enabled)" = "0" ] && echo MATI || echo NYALA)"
    echo "Preset   : $(nice $p)"
    echo "Tune     : $(get tune) semitone    Delay: $(get delay) ms"
    echo "App      : $(grep -v '^#' "$A" 2>/dev/null | grep -v '^$' | tr '\n' ' ')"
    echo "Hook aktif (muncul setelah app memakai mic dengan jalur Java AudioRecord):"
    found=0
    for f in "$D"/status/*.txt; do
      [ -f "$f" ] || continue; found=1; echo "  - $(head -n 1 "$f")"
    done
    [ $found = 1 ] || echo "  (belum ada: buka app, lalu pakai mic / telepon / pesan suara)" ;;
  *)
    echo "mlv status | next | set <preset> | list | tune <n> | delay <ms> | refresh | on | off | apps | add <pkg> | del <pkg>" ;;
esac
__MLV_FILE_END__
mkdir -p "$(dirname "module/defaults/config.txt")"
cat > 'module/defaults/config.txt' <<'__MLV_FILE_END__'
# Pengaturan MochiLyn Voice Changer (dibaca ulang tiap ~1 detik, tidak perlu restart app)
# preset: plus11 | natural | teen | onee | anime | normal
#   plus11  = Cewe natural, +11 semitone dari nada asli kamu (bawaan)
#   natural = Cewek natural, nada tetap ~205 Hz (sama dengan di Sambung)
#   teen    = Cewe remaja     onee = Kakak (one-chan)     anime = Anime
#   normal  = suara asli, tanpa efek
preset=plus11
# enabled: 1 = efek nyala, 0 = mati total (suara asli)
enabled=1
# tune: geser nada halus dalam semitone (-15 sampai 15)
tune=0
# delay: ms, 35 sampai 200. Kecil = lebih cepat tapi kurang stabil, besar = lebih halus
delay=45
# autoheal: 1 = mesin memperbaiki diri kalau suara asli bocor / macet
autoheal=1
__MLV_FILE_END__
mkdir -p "$(dirname "module/defaults/apps.txt")"
cat > 'module/defaults/apps.txt' <<'__MLV_FILE_END__'
# Daftar app yang suaranya diubah (satu nama paket per baris).
# Proses turunan (mis. com.whatsapp:voip) ikut otomatis.
# Tulis * untuk SEMUA app (tidak disarankan: beberapa app bisa error).
com.whatsapp
com.whatsapp.w4b
com.roblox.client
__MLV_FILE_END__
mkdir -p "$(dirname "module/META-INF/com/google/android/update-binary")"
cat > 'module/META-INF/com/google/android/update-binary' <<'__MLV_FILE_END__'
#!/sbin/sh
#################
# Initialization
#################
umask 022
ui_print() { echo "$1"; }
require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v20.4+! "
  ui_print "*******************************"
  exit 1
}
#########################
# Load util_functions.sh
#########################
OUTFD=$2
ZIPFILE=$3
mount /data 2>/dev/null
[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && require_new_magisk
install_module
exit 0
__MLV_FILE_END__
mkdir -p "$(dirname "module/META-INF/com/google/android/updater-script")"
cat > 'module/META-INF/com/google/android/updater-script' <<'__MLV_FILE_END__'
#MAGISK
__MLV_FILE_END__
chmod +x 'build.sh'
chmod +x 'module/META-INF/com/google/android/update-binary'
chmod +x 'module/action.sh'
chmod +x 'module/customize.sh'
chmod +x 'module/system/bin/mlv'
chmod +x 'module/uninstall.sh'
echo "Selesai: folder MochiLynVoice/ siap. Lanjut: bash build.sh (butuh Android NDK)."
