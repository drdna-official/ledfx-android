// ignore_for_file: constant_identifier_names, non_constant_identifier_names

const int FFT_SIZE = 4096;
const int MIC_RATE = 44100;
const int MAX_FREQ = MIC_RATE ~/ 2;
const int MIN_FREQ = 20;
const int MIN_FREQ_DIFFERENCE = 50;
const List<int> MEL_MAX_FREQS = [350, 2000, MAX_FREQ];

final LOWS_RANGE = "Low (${MIN_FREQ}Hz-${MEL_MAX_FREQS[0]}Hz)";
final MIDS_RANGE = "Mid (${MEL_MAX_FREQS[0]}Hz-${MEL_MAX_FREQS[1]}Hz)";
final HIGHS_RANGE = "High (${MEL_MAX_FREQS[1]}Hz-${MEL_MAX_FREQS[2]}Hz)";

final Map<String, (int, int)> FREQ_RANGE_SIMPLE = {
  LOWS_RANGE: (MIN_FREQ, MEL_MAX_FREQS[0]),
  MIDS_RANGE: (MEL_MAX_FREQS[0], MEL_MAX_FREQS[1]),
  HIGHS_RANGE: (MEL_MAX_FREQS[1], MEL_MAX_FREQS[2]),
};
