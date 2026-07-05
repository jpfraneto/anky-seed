// -----------------------------------------------------------------------------
// Reveal-order tuning — every constant of the painter's-order algorithm.
//
// The reveal map encodes, per pixel (0-255), when that pixel turns from
// underdrawing to paint. The order tells a story: background washes first,
// midground, then the character, the face and eyes near the end, gold last.
// Tune here, nowhere else.
// -----------------------------------------------------------------------------

export const revealTuning = {
  // Geometry
  analysisSize: 256, // feature computation resolution (square)
  outputSize: 1024, // emitted grayscale PNG resolution (square)

  // Score weights (all features normalized 0..1; higher score paints later)
  weightEdges: 0.45, // brushwork density — detail paints late
  weightSaturation: 0.2, // vivid pigment paints later than washes
  weightCentrality: 0.2, // canvas center (the character) paints later
  weightDifference: 0.15, // where final departs most from the underdrawing

  // Feature preparation
  edgeBlurRadius: 6, // px at analysis size; turns edges into "detail regions"
  orderBlurRadius: 4, // px; makes arrival patch-like, stroke-shaped
  ditherAmplitude: 3, // ± levels of deterministic hash noise at the frontier

  // The face lands at the 70-80% payoff.
  faceEllipse: {
    centerX: 0.5,
    centerY: 0.38, // face sits in the upper half per the A.1 prompt
    radiusX: 0.2,
    radiusY: 0.24,
  },
  faceBandStart: 0.7,
  faceBandEnd: 0.8,

  // Brightest gold details arrive last.
  gold: {
    hueMinDeg: 25,
    hueMaxDeg: 70,
    minSaturation: 0.3,
    minLuminance: 0.5,
  },
  goldBandStart: 0.85,
  goldBandEnd: 1.0,

  // The lantern always glows — even at 0% the ember is lit.
  lantern: {
    minLuminance: 0.72,
    minWarmth: 0.12, // (R - B) in 0..1
    clusterTopFraction: 0.01, // brightest warm slice used to find the centroid
    radius: 0.055, // normalized; hard clamp region
    featherRadius: 0.09, // soft clamp region
    hardClampLevel: 8, // map value inside radius (of 255)
    featherClampLevel: 48,
    fallbackCenterX: 0.5, // if no warm blob is found (shouldn't happen)
    fallbackCenterY: 0.62,
  },

  // Alignment (underdrawing vs final)
  alignSize: 64,
  alignMaxOffsetPx: 8, // search window at align size
  alignWarpThresholdPx: 2, // beyond this, translate the underdrawing
  alignMinCorrelation: 0.35, // below this, regenerate once

  // QA
  qaMinLuminanceStdDev: 0.06,
  qaMinDistinctSwatches: 3,
  qaAspectTolerance: 0.05,
} as const;
