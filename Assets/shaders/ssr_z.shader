Shader "Hidden/SSR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    
    SubShader
    {


        Pass
        {
            Name "Raymarching"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SSRPassFragment
            
            #ifndef _SSR_PASS_INCLUDED  
#define _SSR_PASS_INCLUDED  

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"  
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"  
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"  
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"  

float4 _ProjectionParams2;  
float4 _CameraViewTopLeftCorner;  
float4 _CameraViewXExtent;  
float4 _CameraViewYExtent;  

#define MAXDISTANCE 10  
#define STRIDE 3  
#define STEP_COUNT 200  
// 能反射和不可能的反射之间的界限  
#define THICKNESS 0.5  

void swap(inout float v0, inout float v1) {  
    float temp = v0;  
    v0 = v1;    
    v1 = temp;
}  

half4 GetSource(half2 uv) {  
    return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearRepeat, uv, _BlitMipLevel);  
}  

// 还原世界空间下，相对于相机的位置  
half3 ReconstructViewPos(float2 uv, float linearEyeDepth) {  
    // Screen is y-inverted  
    uv.y = 1.0 - uv.y;  

    float zScale = linearEyeDepth * _ProjectionParams2.x; // divide by near plane  
    float3 viewPos = _CameraViewTopLeftCorner.xyz + _CameraViewXExtent.xyz * uv.x + _CameraViewYExtent.xyz * uv.y;  
    viewPos *= zScale;  
    return viewPos;  
}  

// 从视角坐标转裁剪屏幕ao坐标
float4 TransformViewToHScreen(float3 vpos, float2 screenSize) {  
    float4 cpos = mul(UNITY_MATRIX_P, vpos);  
    cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;  
    cpos.xy *= screenSize;  
    return cpos;  
}  


float4 _SourceSize;  

half4 SSRPassFragment(Varyings input) : SV_Target {  
    float rawDepth = SampleSceneDepth(input.texcoord);  
    float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);  
    float3 vpos = ReconstructViewPos(input.texcoord, linearDepth);  
    float3 normal = SampleSceneNormals(input.texcoord);  
    float3 vDir = normalize(vpos);  
    float3 rDir = TransformWorldToViewDir(normalize(reflect(vDir, normal)));  

    float magnitude = MAXDISTANCE;  

    // 视空间坐标  
    vpos = _WorldSpaceCameraPos + vpos;  
    float3 startView = TransformWorldToView(vpos);  
    float end = startView.z + rDir.z * magnitude;  
    if (end > -_ProjectionParams.y)  
        magnitude = (-_ProjectionParams.y - startView.z) / rDir.z;  
    float3 endView = startView + rDir * magnitude;  

    // 齐次屏幕空间坐标  
    float4 startHScreen = TransformViewToHScreen(startView, _SourceSize.xy);  
    float4 endHScreen = TransformViewToHScreen(endView, _SourceSize.xy);  

    // inverse w  
    float startK = 1.0 / startHScreen.w;  
    float endK = 1.0 / endHScreen.w;  

    //  结束屏幕空间坐标  
    float2 startScreen = startHScreen.xy * startK;  
    float2 endScreen = endHScreen.xy * endK;  

    // 经过齐次除法的视角坐标  
    float3 startQ = startView * startK;  
    float3 endQ = endView * endK;  

    // 根据斜率将dx=1 dy = delta  
    float2 diff = endScreen - startScreen;  
    bool permute = false;  
    if (abs(diff.x) < abs(diff.y)) {  
        permute = true;  

        diff = diff.yx;  
        startScreen = startScreen.yx;  
        endScreen = endScreen.yx;  
    }  
    // 计算屏幕坐标、齐次视坐标、inverse-w的线性增量  
    float dir = sign(diff.x);  
    float invdx = dir / diff.x;  
    float2 dp = float2(dir, invdx * diff.y);  
    float3 dq = (endQ - startQ) * invdx;  
    float dk = (endK - startK) * invdx;  

    dp *= STRIDE;  
    dq *= STRIDE;  
    dk *= STRIDE;  

    // 缓存当前深度和位置  
    float rayZMin = startView.z;  
    float rayZMax = startView.z;  
    float preZ = startView.z;  

    float2 P = startScreen;  
    float3 Q = startQ;  
    float K = startK;  

    end = endScreen.x * dir;  

    // 进行屏幕空间射线步近  
    UNITY_LOOP  
    for (int i = 0; i < STEP_COUNT && P.x * dir <= end; i++) {  
        // 步近  
        P += dp;  
        Q.z += dq.z;  
        K += dk;  
        // 得到步近前后两点的深度  
        rayZMin = preZ;  
        rayZMax = (dq.z * 0.5 + Q.z) / (dk * 0.5 + K);  
        preZ = rayZMax;        if (rayZMin > rayZMax)  
            swap(rayZMin, rayZMax);  

        // 得到交点uv  
        float2 hitUV = permute ? P.yx : P;  
        hitUV *= _SourceSize.zw;  
        if (any(hitUV < 0.0) || any(hitUV > 1.0))  
            return GetSource(input.texcoord);  
        float surfaceDepth = -LinearEyeDepth(SampleSceneDepth(hitUV), _ZBufferParams);  
        bool isBehind = (rayZMin + 0.1 <= surfaceDepth); // 加一个bias 防止stride过小，自反射  
        bool intersecting = isBehind && (rayZMax >= surfaceDepth - THICKNESS);  

        if (intersecting)  
            return GetSource(hitUV) + GetSource(input.texcoord);  
    }  

    return GetSource(input.texcoord);  
     //return half4(1,1,1,1); 
}  

#endif
            ENDHLSL
        }

        Pass
        {
            Name "Blur"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragBlur
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            float4 _SSRBlurRadius;
            float4 _CameraViewTopLeftCorner;
            float4 _CameraViewXExtent;
            float4 _CameraViewYExtent;
            float4 _ProjectionParams2; // (1/near, cameraPos.x, cameraPos.y, cameraPos.z)
            float4 _SourceSize;        // (width, height, 1/width, 1/height)
            float4 _SSRParams0;        // (MaxDistance, Stride, StepCount, Thickness)
            float4 _SSRParams1;        // (BinaryCount, Intensity, 0, 0)
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 FragBlur(Varyings input) : SV_Target
            {
                float2 texelSize = float2(_SourceSize.z, _SourceSize.w);
                float2 blurRadius = _SSRBlurRadius.xy * texelSize;
                
                // 简单的高斯模糊
                float4 color = 0;
                float totalWeight = 0;
                
                for(int x = -2; x <= 2; x++)
                {
                    for(int y = -2; y <= 2; y++)
                    {
                        float2 offset = float2(x, y) * blurRadius;
                        float2 sampleUV = input.uv + offset;
                        float weight = exp(-(x*x + y*y) / 2.0);
                        
                        color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, sampleUV) * weight;
                        totalWeight += weight;
                    }
                }
                
                return color / totalWeight;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Addtive"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragAdditive
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _CameraViewTopLeftCorner;
            float4 _CameraViewXExtent;
            float4 _CameraViewYExtent;
            float4 _ProjectionParams2; // (1/near, cameraPos.x, cameraPos.y, cameraPos.z)
            float4 _SourceSize;        // (width, height, 1/width, 1/height)
            float4 _SSRParams0;        // (MaxDistance, Stride, StepCount, Thickness)
            float4 _SSRParams1;        // (BinaryCount, Intensity, 0, 0)
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 FragAdditive(Varyings input) : SV_Target
            {
                float4 sceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);
                float4 ssrColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // 叠加模式
                return sceneColor + ssrColor * _SSRParams1.y;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Balance"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragBalance
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _CameraViewTopLeftCorner;
            float4 _CameraViewXExtent;
            float4 _CameraViewYExtent;
            float4 _ProjectionParams2; // (1/near, cameraPos.x, cameraPos.y, cameraPos.z)
            float4 _SourceSize;        // (width, height, 1/width, 1/height)
            float4 _SSRParams0;        // (MaxDistance, Stride, StepCount, Thickness)
            float4 _SSRParams1;        // (BinaryCount, Intensity, 0, 0)
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 FragBalance(Varyings input) : SV_Target
            {
                float4 sceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, input.uv);
                float4 ssrColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // 平衡混合模式
                return lerp(sceneColor, ssrColor, _SSRParams1.y);
            }
            ENDHLSL
        }
    }
}