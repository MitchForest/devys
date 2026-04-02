// NoiseShaders.metal
// MetalASCII - Shared noise functions for procedural generation
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// MARK: - Simplex Noise

// Permutation table
constant int perm[512] = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
    // Repeat
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
};

// Gradient vectors for 2D
constant float2 grad2[8] = {
    float2(1, 0), float2(-1, 0), float2(0, 1), float2(0, -1),
    float2(0.7071, 0.7071), float2(-0.7071, 0.7071),
    float2(0.7071, -0.7071), float2(-0.7071, -0.7071)
};

// Gradient vectors for 3D
constant float3 grad3[12] = {
    float3(1,1,0), float3(-1,1,0), float3(1,-1,0), float3(-1,-1,0),
    float3(1,0,1), float3(-1,0,1), float3(1,0,-1), float3(-1,0,-1),
    float3(0,1,1), float3(0,-1,1), float3(0,1,-1), float3(0,-1,-1)
};

// Fast floor
inline int fastfloor(float x) {
    return x > 0 ? int(x) : int(x) - 1;
}

// 2D Simplex Noise
inline float simplex2D(float2 pos) {
    const float F2 = 0.366025403784439;  // (sqrt(3) - 1) / 2
    const float G2 = 0.211324865405187;  // (3 - sqrt(3)) / 6
    
    // Skew the input space
    float s = (pos.x + pos.y) * F2;
    int i = fastfloor(pos.x + s);
    int j = fastfloor(pos.y + s);
    
    // Unskew
    float t = (i + j) * G2;
    float X0 = i - t;
    float Y0 = j - t;
    float x0 = pos.x - X0;
    float y0 = pos.y - Y0;
    
    // Determine which simplex we're in
    int i1, j1;
    if (x0 > y0) { i1 = 1; j1 = 0; }
    else { i1 = 0; j1 = 1; }
    
    float x1 = x0 - i1 + G2;
    float y1 = y0 - j1 + G2;
    float x2 = x0 - 1.0 + 2.0 * G2;
    float y2 = y0 - 1.0 + 2.0 * G2;
    
    // Hash coordinates
    int ii = i & 255;
    int jj = j & 255;
    int gi0 = perm[ii + perm[jj]] % 8;
    int gi1 = perm[ii + i1 + perm[jj + j1]] % 8;
    int gi2 = perm[ii + 1 + perm[jj + 1]] % 8;
    
    // Calculate contributions
    float n0, n1, n2;
    
    float t0 = 0.5 - x0*x0 - y0*y0;
    if (t0 < 0) n0 = 0.0;
    else {
        t0 *= t0;
        n0 = t0 * t0 * dot(grad2[gi0], float2(x0, y0));
    }
    
    float t1 = 0.5 - x1*x1 - y1*y1;
    if (t1 < 0) n1 = 0.0;
    else {
        t1 *= t1;
        n1 = t1 * t1 * dot(grad2[gi1], float2(x1, y1));
    }
    
    float t2 = 0.5 - x2*x2 - y2*y2;
    if (t2 < 0) n2 = 0.0;
    else {
        t2 *= t2;
        n2 = t2 * t2 * dot(grad2[gi2], float2(x2, y2));
    }
    
    // Scale to [-1, 1]
    return 70.0 * (n0 + n1 + n2);
}

// 3D Simplex Noise
inline float simplex3D(float3 pos) {
    const float F3 = 1.0 / 3.0;
    const float G3 = 1.0 / 6.0;
    
    float s = (pos.x + pos.y + pos.z) * F3;
    int i = fastfloor(pos.x + s);
    int j = fastfloor(pos.y + s);
    int k = fastfloor(pos.z + s);
    
    float t = (i + j + k) * G3;
    float X0 = i - t;
    float Y0 = j - t;
    float Z0 = k - t;
    float x0 = pos.x - X0;
    float y0 = pos.y - Y0;
    float z0 = pos.z - Z0;
    
    int i1, j1, k1, i2, j2, k2;
    
    if (x0 >= y0) {
        if (y0 >= z0) { i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; }
        else if (x0 >= z0) { i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; }
        else { i1=0; j1=0; k1=1; i2=1; j2=0; k2=1; }
    } else {
        if (y0 < z0) { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; }
        else if (x0 < z0) { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; }
        else { i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; }
    }
    
    float x1 = x0 - i1 + G3;
    float y1 = y0 - j1 + G3;
    float z1 = z0 - k1 + G3;
    float x2 = x0 - i2 + 2.0 * G3;
    float y2 = y0 - j2 + 2.0 * G3;
    float z2 = z0 - k2 + 2.0 * G3;
    float x3 = x0 - 1.0 + 3.0 * G3;
    float y3 = y0 - 1.0 + 3.0 * G3;
    float z3 = z0 - 1.0 + 3.0 * G3;
    
    int ii = i & 255;
    int jj = j & 255;
    int kk = k & 255;
    int gi0 = perm[ii + perm[jj + perm[kk]]] % 12;
    int gi1 = perm[ii + i1 + perm[jj + j1 + perm[kk + k1]]] % 12;
    int gi2 = perm[ii + i2 + perm[jj + j2 + perm[kk + k2]]] % 12;
    int gi3 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]] % 12;
    
    float n0, n1, n2, n3;
    
    float t0 = 0.6 - x0*x0 - y0*y0 - z0*z0;
    if (t0 < 0) n0 = 0.0;
    else {
        t0 *= t0;
        n0 = t0 * t0 * dot(grad3[gi0], float3(x0, y0, z0));
    }
    
    float t1 = 0.6 - x1*x1 - y1*y1 - z1*z1;
    if (t1 < 0) n1 = 0.0;
    else {
        t1 *= t1;
        n1 = t1 * t1 * dot(grad3[gi1], float3(x1, y1, z1));
    }
    
    float t2 = 0.6 - x2*x2 - y2*y2 - z2*z2;
    if (t2 < 0) n2 = 0.0;
    else {
        t2 *= t2;
        n2 = t2 * t2 * dot(grad3[gi2], float3(x2, y2, z2));
    }
    
    float t3 = 0.6 - x3*x3 - y3*y3 - z3*z3;
    if (t3 < 0) n3 = 0.0;
    else {
        t3 *= t3;
        n3 = t3 * t3 * dot(grad3[gi3], float3(x3, y3, z3));
    }
    
    return 32.0 * (n0 + n1 + n2 + n3);
}

// MARK: - Fractal Brownian Motion (FBM)

inline float fbm2D(float2 pos, int octaves, float persistence) {
    float total = 0.0;
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxValue = 0.0;
    
    for (int i = 0; i < octaves; i++) {
        total += simplex2D(pos * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    
    return total / maxValue;
}

inline float fbm3D(float3 pos, int octaves, float persistence) {
    float total = 0.0;
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxValue = 0.0;
    
    for (int i = 0; i < octaves; i++) {
        total += simplex3D(pos * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    
    return total / maxValue;
}

// MARK: - Curl Noise (for smooth particle flow)

inline float2 curlNoise2D(float2 pos, float epsilon) {
    float n1 = simplex2D(float2(pos.x, pos.y + epsilon));
    float n2 = simplex2D(float2(pos.x, pos.y - epsilon));
    float n3 = simplex2D(float2(pos.x + epsilon, pos.y));
    float n4 = simplex2D(float2(pos.x - epsilon, pos.y));
    
    float dx = (n1 - n2) / (2.0 * epsilon);
    float dy = (n3 - n4) / (2.0 * epsilon);
    
    // Curl is perpendicular to gradient
    return float2(dx, -dy);
}

// MARK: - Flow Field

inline float2 flowField(float2 pos, float time, float turbulence) {
    // Multi-scale noise for organic flow
    float2 flow = float2(0.0);
    
    // Large scale
    float angle1 = simplex3D(float3(pos * 0.5, time * 0.3)) * 3.14159 * 2.0;
    flow += float2(cos(angle1), sin(angle1)) * 0.6;
    
    // Medium scale
    float angle2 = simplex3D(float3(pos * 1.5, time * 0.5 + 100.0)) * 3.14159 * 2.0;
    flow += float2(cos(angle2), sin(angle2)) * 0.3;
    
    // Small scale (turbulence)
    float angle3 = simplex3D(float3(pos * 4.0, time * 0.8 + 200.0)) * 3.14159 * 2.0;
    flow += float2(cos(angle3), sin(angle3)) * 0.1 * turbulence;
    
    return normalize(flow);
}
