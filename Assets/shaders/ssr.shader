Shader "Hidden/SSR0"
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
            #pragma fragment FragRaymarching
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            // C#传递的参数
            float4 _CameraViewTopLeftCorner;
            float4 _CameraViewXExtent;
            float4 _CameraViewYExtent;
            float4 _ProjectionParams2; // (1/near, cameraPos.x, cameraPos.y, cameraPos.z)
            float4 _SourceSize;        // (width, height, 1/width, 1/height)
            float4 _SSRParams0;        // (MaxDistance, Stride, StepCount, Thickness)
            float4 _SSRParams1;        // (BinaryCount, Intensity, 0, 0)
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            #pragma shader_feature _JITTER_ON

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 viewRay : TEXCOORD1;
            };

            // 从深度重建视图空间位置（相对相机）
            float3 ReconstructViewPos(float2 uv, float linearDepth)
{
    // 获取相机参数
    float3 cameraForward = mul((float3x3)unity_CameraToWorld, float3(0, 0, 1));
    float3 cameraRight = mul((float3x3)unity_CameraToWorld, float3(1, 0, 0));
    float3 cameraUp = mul((float3x3)unity_CameraToWorld, float3(0, 1, 0));
    
    // 计算UV在近平面上的偏移（从中心出发）
    float2 uvOffset = (uv - 0.5) * 2.0;
    
    // 使用相机的FOV和Aspect计算方向
    float fovRad = unity_CameraProjection._m11; // 通过投影矩阵获取
    float aspect = unity_CameraProjection._m00 / unity_CameraProjection._m11;
    
    float3 viewDir = cameraForward 
                   + cameraRight * uvOffset.x * aspect * fovRad
                   + cameraUp * uvOffset.y * fovRad;
    
    viewDir = normalize(viewDir);
    
    // 计算世界位置
    return _WorldSpaceCameraPos + viewDir * linearDepth;
}

            // 获取屏幕深度（线性）
            float GetLinearDepth(float2 uv)
            {
                float depth = SampleSceneDepth(uv);
                return LinearEyeDepth(depth, _ZBufferParams);
            }

            // 获取法线（世界空间）
            float3 GetWorldNormal(float2 uv)
            {
                return SampleSceneNormals(uv);
            }

            // 抖动函数（优化步进）
            float3 Jitter(float2 uv, float frameOffset)
            {
                #if _JITTER_ON
                    float2 noise = frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453 + frameOffset);
                    return float3(noise, 0);
                #else
                    return 0;
                #endif
            }

            // 基础光线步进（视空间）
            // 修复后的光线步进函数
float2 RayMarchBasic(float3 rayOriginVS, float3 rayDirVS, float2 uv, float linearDepth)
{
    float maxDistance = _SSRParams0.x;
    int maxSteps = _SSRParams0.z;  // 使用StepCount
    float thickness = _SSRParams0.w;
    
    // 关键：计算初始步长（基于像素深度）
    float stepSize = maxDistance / maxSteps;
    
    // 添加调试：输出初始信息
    // return float4(rayDirVS, 1.0); // 先看光线方向
    
    float currentDistance = stepSize;
    UNITY_LOOP
    for(int i = 0; i < maxSteps; i++)
    {
        // 计算当前采样点（视空间）
        float3 samplePosVS = rayOriginVS + rayDirVS * currentDistance;
        
        // 视空间 -> 裁剪空间 -> NDC -> UV
        float4 clipPos = mul(UNITY_MATRIX_P, float4(samplePosVS, 1.0));
        float3 ndc = clipPos.xyz / clipPos.w;
        
        // 检查是否在视锥内
        if(abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0 || ndc.z < 0 || ndc.z > 1.0)
            break;
        
        // NDC -> UV
        float2 screenUV = ndc.xy * 0.5 + 0.5;
        
        // 获取场景深度（线性深度，视空间）
        float sceneDepth = GetLinearDepth(screenUV);
        
        // 关键：直接比较视空间Z值
        // samplePosVS.z是负值（Unity视空间Z轴向内为负）
        float rayDepth = -samplePosVS.z;  // 取绝对值
        
        // 深度比较（修复逻辑）
        if(rayDepth > sceneDepth)
        {
            float depthDiff = rayDepth - sceneDepth;
            if(depthDiff < thickness)
            {
                // 找到交点，添加屏幕边缘衰减
                float2 edgeFade = 1.0 - saturate(abs(screenUV - 0.5) * 2.0);
                float fade = edgeFade.x * edgeFade.y;
                
                return screenUV;
            }
        }
        
        // 自适应步长：离交点越近，步长越小
        currentDistance += stepSize;
        
        // 提前终止：如果光线已经超出最大深度
        if(currentDistance > maxDistance)
            break;
    }
    
    return float2(0, 0); // 未找到
}

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                
                // 计算视图空间射线
                float depth = 1.0;
                output.viewRay = ReconstructViewPos(input.uv, depth);
                
                return output;
            }

            float4 FragRaymarching(Varyings input) : SV_Target
            {

                
                // 获取当前像素信息
                float depth = GetLinearDepth(input.uv);
                float3 viewPos = ReconstructViewPos(input.uv, depth);
                float3 worldNormal = GetWorldNormal(input.uv);
                
                // 计算反射方向（从相机到交点的向量反射）
                float3 viewDir = normalize(viewPos);
                float3 reflectDir = reflect(viewDir, worldNormal);
                
                // 应用抖动
                float3 jitterOffset = Jitter(input.uv, _Time.y);
                reflectDir += jitterOffset * 0.1;
                
                // 光线步进
                float2 hitUV = RayMarchBasic(viewPos, reflectDir, input.uv, depth);
                // 调试开关
    #define DEBUG_DEPTH 0
    #define DEBUG_NORMAL 0
    #define DEBUG_RAYDIR 0
    #define DEBUG_VIEWRAY 0  // 先看viewRay向量
    #define DEBUG_DEPTH_RAW 0  // 原始深度值
    #define DEBUG_POSITION 0  // 重建的位置
    
    #if DEBUG_VIEWRAY
        // 检查viewRay向量（未乘以深度）
        float3 viewRay = _CameraViewTopLeftCorner.xyz;
        // viewRay应该是标准化的方向向量
        // 输出颜色：R=长度，GB=方向
        float len = length(viewRay);
        return float4(len, viewRay.xy * 0.5 + 0.5, 1.0);
        // 预期：len≈1（方向向量），xy随UV变化
    #endif
    
    #if DEBUG_DEPTH
        depth = GetLinearDepth(input.uv);
        return float4(6.0/depth.xxx, 1.0); // 深度可视化
    #endif
    
    #if DEBUG_NORMAL
        float3 normal = GetWorldNormal(input.uv);
        return float4(normal * 0.5 + 0.5, 1.0); // 法线可视化
    #endif
    
    #if DEBUG_RAYDIR
        depth = GetLinearDepth(input.uv);
        viewPos = ReconstructViewPos(input.uv, depth);
        viewDir = normalize(viewPos);
         worldNormal = GetWorldNormal(input.uv);
         //reflectDir = reflect(viewDir, worldNormal);
        return float4(reflectDir * 0.5 + 0.5, 1.0); // 反射方向可视化
    #endif
                
                // 如果找到交点，采样颜色
                float4 color = float4(0, 0, 0, 0);
                if(hitUV.x > 0 || hitUV.y > 0)
                {
                    color = float4(1,1,0,1);
                    color.a = 1.0;
                }
                
                return color;
            }
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