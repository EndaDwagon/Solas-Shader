const vec2 roughReflectionOffsets[8] = vec2[8](
   vec2( 0.21848650099008202, -0.09211370200809937),
   vec2(-0.58661126547828780,  0.32153793477769893),
   vec2(-0.06595078555407359, -0.87965605906648100),
   vec2( 0.43407555004227927,  0.65023182629688160),
   vec2(-0.89152774844610910, -0.23870947755732180),
   vec2( 0.83014374282544340, -0.47450371579821350),
   vec2(-0.33108317876518320,  0.86136662765738790),
   vec2( 0.04472054628368919,  0.37468181734700530)
);

vec4 getRoughReflectionSample(in vec2 coord, in float lod, in float roughness, in float dither) {
    vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
    float angle = dither * 6.28318530718;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rotation = mat2(c, -s, s, c);

    float radius = (0.35 + exp2(lod * 0.90)) * mix(0.35, 2.25, roughness);
    float tapLod = max(lod - 0.75 + roughness * 0.75, 0.0);

    vec4 reflection = texture2DLod(colortex0, coord, max(lod - 1.0, 0.0)) * 2.0;
    float weight = 2.0;

    for (int i = 0; i < 8; i++) {
        vec2 offset = rotation * roughReflectionOffsets[i] * radius * pixelSize;
        float tapWeight = mix(0.95, 0.55, length(roughReflectionOffsets[i]) * roughness);
        reflection += texture2DLod(colortex0, coord + offset, tapLod) * tapWeight;
        weight += tapWeight;
    }

    return reflection / weight;
}

void getReflection(inout vec4 color, in vec3 viewPos, in vec3 newNormal, in float fresnel, in float smoothness, in float skyLightMap) {
    float blueNoiseDither = texture2D(noisetex, gl_FragCoord.xy / 512.0).b;

    #ifdef TAA
    blueNoiseDither = fract(blueNoiseDither + 1.61803398875 * mod(float(frameCounter), 3600.0));
    #endif

    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);

    #ifndef OVERWORLD
    int sampleCount = 34;
    #else
    int sampleCount = int(34 - skyLightMap * 12);
    #endif

    sampleCount = int(float(sampleCount) * mix(0.55, 1.08, smoothness));
    sampleCount = max(sampleCount, 8);

    float border = 0.0;
    float lRfragPos = 0.0;
    float dist = 0.0;
    vec2 cdist = vec2(0.0);

    vec3 reflectPos = Raytrace(depthtex1, viewPos, newNormal, blueNoiseDither, fresnel, 7, 0.45, 0.50, 1.36, sampleCount, border, lRfragPos, dist, cdist);
    vec4 reflection = vec4(0.0);

    if (reflectPos.z < 0.99997) {
        if (border > 0.001) {
            vec2 edgeFactor = pow4(cdist);

            float roughness2 = roughness * roughness;
            float lodFactor = 1.0 - exp(-0.100 * roughness2 * dist);
            float lod = log2(max(viewHeight * 0.175 * roughness2 * lodFactor, 1.0)) * mix(0.35, 0.85, roughness);
            lod = max(lod - 0.5, 0.0);

            reflection = getRoughReflectionSample(reflectPos.xy, lod, roughness, blueNoiseDither);

            edgeFactor.x *= edgeFactor.x;
            edgeFactor = 1.0 - edgeFactor;
            reflection.a *= border * pow(edgeFactor.x * edgeFactor.y, (1.0 + length(reflection.rgb)) * 2.0);
        }

        reflection.a *= clamp(lRfragPos - length(viewPos) + 2.5, 0.0, 1.0);
        reflection.a *= mix(1.0, 0.72, roughness);
    }

    vec3 falloff = vec3(0.0);

    if (reflection.a < 1.0 && isEyeInWater == 0) {
        if (skyLightMap > 0.95) {
            #ifdef OVERWORLD
            vec3 viewPosRef = reflect(normalize(viewPos), newNormal);
            vec3 worldPosRef = ToWorld(viewPosRef);
            float atmosphereHardMixFactor = 0.0;
            vec3 reflectedAtmosphere = getAtmosphere(viewPosRef.xyz, worldPosRef.xyz, atmosphereHardMixFactor);
            reflectedAtmosphere = pow(reflectedAtmosphere, vec3(2.2));
            falloff = mix(falloff, reflectedAtmosphere, skyLightMap);
            #endif
        }

        #if MC_VERSION >= 11900
        falloff *= 1.0 - darknessFactor;
        #endif

        falloff *= 1.0 - blindFactor;
    }

    vec3 finalReflection = max(mix(falloff, reflection.rgb, reflection.a), vec3(0.0));

    float reflectionStrength = smoothness * mix(0.78, 1.0, smoothness);

    #ifdef GENERATED_SPECULAR
    reflectionStrength *= mix(0.65, 1.0, smoothness); // Keeps generated rough reflections present, but prevents rough surfaces from looking mirror-polished.
    #endif

    color.rgb += finalReflection * fresnel * reflectionStrength;
}
