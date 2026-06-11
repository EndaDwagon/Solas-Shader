vec3 nvec3(vec4 pos) {
    return pos.xyz / pos.w;
}

const float errMult = 2.2;

vec3 RaytraceProject(in vec3 viewPos) {
    return nvec3(gbufferProjection * vec4(viewPos, 1.0)) * 0.5 + 0.5;
}

vec3 RaytraceViewPosition(in sampler2D depthtex, in vec2 coord, out float sampleDepth) {
    sampleDepth = texture(depthtex, coord).r;

    vec3 rfragpos = vec3(coord, sampleDepth);
         rfragpos = nvec3(gbufferProjectionInverse * vec4(rfragpos * 2.0 - 1.0, 1.0));

    #if defined DISTANT_HORIZONS || defined VOXY
    if (sampleDepth >= 1.0) {
    #endif
        #ifdef DISTANT_HORIZONS
        float dhDepth = texture(dhDepthTex1, coord).r;
        if (dhDepth < 1.0) {
            rfragpos = nvec3(dhProjectionInverse * vec4(vec3(coord, dhDepth) * 2.0 - 1.0, 1.0));
            sampleDepth = dhDepth;
        }
        #endif

        #ifdef VOXY
        float vxDepth = texture(vxDepthTexOpaque, coord).r;
        if (vxDepth < 1.0) {
            rfragpos = nvec3(vxProjInv * vec4(vec3(coord, vxDepth) * 2.0 - 1.0, 1.0));
            sampleDepth = vxDepth;
        }
        #endif
    #if defined DISTANT_HORIZONS || defined VOXY
    }
    #endif

    return rfragpos;
}

bool RaytraceIsInsideScreen(in vec3 pos) {
    return abs(pos.x - 0.5) <= 0.6 && abs(pos.y - 0.5) <= 0.55 && pos.z > 0.0 && pos.z < 1.0001;
}

float RaytraceHitError(in vec3 rayPos, in vec3 samplePos, in float stepDistance) {
    float depthError = abs(rayPos.z - samplePos.z);
    float positionError = length(rayPos - samplePos);
    float distanceFade = 0.015 * length(samplePos);
    float thickness = max(stepDistance * errMult, 0.045 + distanceFade);

    return min(positionError, depthError * 3.0) / max(thickness, 1e-5);
}

vec3 Raytrace(sampler2D depthtex, vec3 viewPos, vec3 normal, float dither, float fresnel,
              int refinementSteps, float stepSize, float refMult, float stepLength, int sampleCount, out float border, out float lRfragPos, out float dist, out vec2 cdist) {
    vec3 pos = vec3(0.0);
    vec3 rfragpos = vec3(0.0);

    border = 0.0;
    lRfragPos = 0.0;
    dist = 0.0;
    cdist = vec2(1.0);

    vec3 nViewPos = normalize(viewPos);
    vec3 nNormal = normalize(normal);
    vec3 rayVector = normalize(reflect(nViewPos, nNormal));

    vec3 start = viewPos + nNormal * (length(viewPos) * fmix(0.010, 0.002, fresnel) + 0.050);
    float jitter = fmix(0.35, 0.95, dither);

    vec3 rayIncrement = rayVector * stepSize;
    vec3 rayDir = rayIncrement * jitter;
    vec3 previousRayPos = start;
    vec3 rayPos = start + rayDir;

    for (int i = 0; i < sampleCount; i++) {
        pos = RaytraceProject(rayPos);
        if (!RaytraceIsInsideScreen(pos)) break;

        float sampleDepth = 1.0;
        rfragpos = RaytraceViewPosition(depthtex, pos.xy, sampleDepth);

        float stepDistance = max(length(rayPos - previousRayPos), 0.001);
        float hitError = RaytraceHitError(rayPos, rfragpos, stepDistance);

        if (sampleDepth < 1.0 && hitError < 1.0) {
            vec3 lowRayPos = previousRayPos;
            vec3 highRayPos = rayPos;
            vec3 bestRayPos = rayPos;
            float bestError = hitError;

            for (int j = 0; j < refinementSteps; j++) {
                vec3 midRayPos = mix(lowRayPos, highRayPos, 0.5);
                vec3 midPos = RaytraceProject(midRayPos);

                if (!RaytraceIsInsideScreen(midPos)) {
                    lowRayPos = midRayPos;
                    continue;
                }

                float midDepth = 1.0;
                vec3 midRfragpos = RaytraceViewPosition(depthtex, midPos.xy, midDepth);
                float midError = RaytraceHitError(midRayPos, midRfragpos, stepDistance * refMult);

                if (midDepth < 1.0 && midError < bestError) {
                    bestError = midError;
                    bestRayPos = midRayPos;
                    pos = midPos;
                    rfragpos = midRfragpos;
                }

                if (-midRayPos.z > -midRfragpos.z) {
                    highRayPos = midRayPos;
                } else {
                    lowRayPos = midRayPos;
                }
            }

            pos = RaytraceProject(bestRayPos);
            if (RaytraceIsInsideScreen(pos)) {
                float finalDepth = 1.0;
                rfragpos = RaytraceViewPosition(depthtex, pos.xy, finalDepth);
            }
            break;
        }

        previousRayPos = rayPos;
        rayIncrement *= stepLength;
        rayDir += rayIncrement;
        rayPos = start + rayDir;
    }

    if (pos.z < 0.99997 && RaytraceIsInsideScreen(pos)) {
        lRfragPos = length(rfragpos);
        dist = length(start - rfragpos);
        cdist = abs(pos.xy - 0.5) / vec2(0.6, 0.55);
        border = clamp(1.0 - pow2(pow32(max(cdist.x, cdist.y))), 0.0, 1.0);
    }

    return pos;
}
