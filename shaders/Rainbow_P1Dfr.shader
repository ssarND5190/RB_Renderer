Shader "Custom/Rainbow_P1Dfr"
{
    Properties
    {
        _BrightColor("Bright Color", Color) = (1,1,1,1)
        _MidColor("Mid Color", Color) = (0.5,0.5,0.5,1)
        _DarkColor("Dark Color", Color) = (0,0,0,1)
        _SheenColor("Sheen Color", Color) = (1,1,0,1)
        _SheenPower("Sheen Power", Range(0,5)) = 2.0
        [ToggleUI]_ClockwiseHue("Clockwise Hue Shift", Float) = 0

        _Smoothness("Smoothness", Range(0,1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "GBuffer"
    Tags { "LightMode"="UniversalGBuffer" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
    #pragma multi_compile _ _DEFERRED_ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 positionCS : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float4 worldPos : TEXCOORD2;
            };

            float3 HSV2RGB(float3 c){
                float3 rgb = clamp( abs(fmod(c.x*6.0+float3(0.0,4.0,2.0),6)-3.0)-1.0, 0, 1);
                rgb = rgb*rgb*(3.0-2.0*rgb);
                return c.z * lerp( float3(1,1,1), rgb, c.y);
            }

            float3 RGB2HSV(float3 c){
                float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
            }

            float4 lerpHue(float3 rgb1, float3 rgb2, float t, bool clockwise)
            {
                float3 hsv1 = RGB2HSV(rgb1);
                float3 hsv2 = RGB2HSV(rgb2);
                float h1 = hsv1.x;
                float h2 = hsv2.x;
                if (clockwise)
                {
                    if (h2 < h1)
                        h2 += 1.0;
                }
                else
                {
                    if (h2 > h1)
                        h2 -= 1.0;
                }
                float h = frac(lerp(h1, h2, t));
                float s = lerp(hsv1.y, hsv2.y, t);
                float v = lerp(hsv1.z, hsv2.z, t);
                return float4(HSV2RGB(float3(h, s, v)), 1.0);
            }

            float4 _BrightColor;
            float4 _MidColor;
            float4 _DarkColor;
            float4 _SheenColor;
            float _SheenPower;
            float _ClockwiseHue;

                float _Smoothness;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
                float4 worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.worldPos = worldPos;
                o.normal = mul(unity_ObjectToWorld, float4(v.normal, 0)).xyz;
                o.positionCS = ComputeScreenPos(o.pos);
                return o;
            }

            struct MyFragmentOutput
    {
        float4 GBuffer0 : SV_Target0;  // RGB=Albedo, A=遮罩
        float4 GBuffer1 : SV_Target1;  // RGB=Specular, A=光滑度
        float4 GBuffer2 : SV_Target2;  // RGB=世界法线, A=保留
        float4 GBuffer3 : SV_Target3;  // 自发光等
        float4 GBuffer4 : SV_Target4;  // 深度（可选）
    };

            MyFragmentOutput frag (v2f i) : SV_Target
            {
                float4 LIGHT_COORDS = TransformWorldToShadowCoord(i.worldPos);
                Light mainLight = GetMainLight(LIGHT_COORDS);
                half shadow = MainLightRealtimeShadow(LIGHT_COORDS);
                float NdotL = dot(normalize(i.normal), mainLight.direction);
                float2 screenUV = i.positionCS.xy / i.positionCS.w;
                AmbientOcclusionFactor ambientOcclusion = GetScreenSpaceAmbientOcclusion(screenUV);
                float4 color;
                if (NdotL < 0.0)
                    color = _DarkColor;
                else if (NdotL < 0.5)
                    color = lerp(_DarkColor, _MidColor, NdotL * 2.0);
                else
                    color = lerp(_MidColor, _BrightColor, (NdotL - 0.5) * 2.0);
                //sheen according to camera angle
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
                float viewDot = dot(normalize(i.normal), viewDir);
                color = lerpHue(_DarkColor.rgb, color.rgb, sqrt(abs(shadow)), _ClockwiseHue > 0.5);
                color += _SheenColor * pow(1.0 - abs(viewDot), _SheenPower);
                color *= ambientOcclusion.indirectAmbientOcclusion;
                color=float4(1,1,1,1);
                
                MyFragmentOutput output;
        
        // GBuffer0: Albedo颜色 + 遮罩（这里放alpha）
        output.GBuffer0 = float4(color.rgb, color.a);
        
        // GBuffer1: Specular颜色 + 光滑度（SSR关键！）
        // 你的Shader没有镜面高光，所以specular设为0
        output.GBuffer1 = float4(0.0, 0.0, 0.0, _Smoothness);
        
        // GBuffer2: 世界空间法线（SSR关键！）
        float3 worldNormal = normalize(i.normal);
        // 编码法线到[0,1]范围
        output.GBuffer2 = float4(worldNormal, 1.0);
        
        // GBuffer3: 自发光 + 其他（如环境光遮蔽）
        output.GBuffer3 = float4(0.0, 0.0, 0.0, 1.0);
        
        // GBuffer4: 深度或其他数据（根据需求）
        // 这里可以输出深度值供高级效果使用
        float depth = i.positionCS.z / i.positionCS.w;
        output.GBuffer4 = float4(depth, 0.0, 0.0, 1.0);
        
        return output;
            }
            ENDHLSL
        }
        Pass
       {
           Name "ShadowCast"
           Tags { "LightMode" = "ShadowCaster" }
           HLSLPROGRAM
           #pragma vertex vert
           #pragma fragment frag
           #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
           struct appdata
           {
               float4 vertex : POSITION;
           };
           struct v2f
           {
               float4 pos : SV_POSITION;
           };
           v2f vert(appdata v)
           {
               v2f o;
               o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
               return o;
           }
           float4 frag(v2f i) : SV_Target
           {
               return float4(0.0, 0.0, 0.0, 1.0);
           }
           ENDHLSL
       }
       // 写入深度图 来自Unlit 打开FrameDebugger来查看这些算法细节
        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags
            {
                "LightMode" = "DepthNormals"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _ _DETAIL_MULX2 _DETAIL_SCALED
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // -------------------------------------
            // Universal Pipeline keywords
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}