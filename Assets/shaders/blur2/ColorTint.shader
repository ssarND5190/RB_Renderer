//3、Pass，后处理的主要部分，我们的各种算法在这里实现。

Shader "PostProcess/ColorTint"
{
    Properties
    {
        _MainTex ("基础贴图", 2D) = "white" {}
        _ColorTint("颜色", Color) = (1, 1, 1, 1)
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #include "./HimeColorTintFunction.hlsl"
    ENDHLSL 

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline"}
        Cull Off ZWrite Off ZTest Always

        Pass //ColorTint【pass 0】
        {
            HLSLPROGRAM 
            #pragma vertex ColorTintVert
            #pragma fragment ColorTintFrag
            ENDHLSL
        }

        Pass //Gaussian Box Kawase Blur【pass 1】
        {
            HLSLPROGRAM 
            #pragma vertex ColorTintVert
            #pragma fragment KawaseBlurFrag
            ENDHLSL
        }

        Pass //Dual Blur -- Down【pass 2】
        {
            Name "DownSample"
            HLSLPROGRAM 
            #pragma vertex DualBlurDownVert
            #pragma fragment DualBlurDownFrag
            ENDHLSL
        }

        Pass //Dual Blur -- Up【pass 3】
        {
            Name "UpSample"
            HLSLPROGRAM 
            #pragma vertex DualBlurUpVert
            #pragma fragment DualBlurUpFrag
            ENDHLSL
        }

        Pass //mix【pass 4】
        {
            Name "Mix"
            HLSLPROGRAM 
            #pragma vertex MixVert
            #pragma fragment MixFrag
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            ENDHLSL
        }
    }
}