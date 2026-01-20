Shader "Reflection/ScreenReflectionBase"
{
    Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	
	SubShader
	{
		Pass
		{
			ZTest Off
			Cull Off
			ZWrite Off
			Fog{ Mode Off }
 
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"
			
			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};
 
			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;	
				float3 viewRay : TEXCOORD1;
			};
 
			sampler2D _MainTex;
			float4 _MainTex_ST;//(1 / width, 1 / height, width, height)
			sampler2D _CameraDepthTexture;
			//使用外部传入的matrix，实际上等同于下面两个unity内置matrix
			//似乎在老版本unity中在pss阶段使用正交相机绘制Quad，矩阵会被替换，2017.3版本测试使用内置矩阵也可以
			float4x4 _InverseProjectionMatrix;//投影矩阵的逆矩阵
			float4x4 _CameraProjectionMatrix;//unity_CameraProjection
			float _maxRayMarchingDistance; 
			float _maxRayMarchingStep; //不仅次数
			float _rayMarchingStepSize; 
			float _depthThickness; 
			
			sampler2D _CameraDepthNormalsTexture;
			
			bool checkDepthCollision(float3 viewPos, out float2 screenPos)
			{
				float4 clipPos = mul(_CameraProjectionMatrix, float4(viewPos, 1.0));
 
				clipPos = clipPos / clipPos.w;
				screenPos = float2(clipPos.x, clipPos.y) * 0.5 + 0.5;
				float4 depthnormalTex = tex2D(_CameraDepthNormalsTexture, screenPos);
				float depth = DecodeFloatRG(depthnormalTex.zw) * _ProjectionParams.z;
				//判断当前反射点是否在屏幕外，或者超过了当前深度值
				return screenPos.x > 0 && screenPos.y > 0 && screenPos.x < 1.0 && screenPos.y < 1.0 && depth < -viewPos.z;
			}
			
			bool viewSpaceRayMarching(float3 rayOri, float3 rayDir, out float2 hitScreenPos)
			{
				int maxStep = _maxRayMarchingStep;
				UNITY_LOOP
				for(int i = 0; i < maxStep; i++)
				{
					float3 currentPos = rayOri + rayDir * _rayMarchingStepSize * i;
					if (length(rayOri - currentPos) > _maxRayMarchingDistance)
						return false;
					if (checkDepthCollision(currentPos, hitScreenPos))
					{
						return true;
					}
				}
				return false;
			}
			
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                float4 screenPos = ComputeScreenPos(o.vertex);
				
				float4 clipPos = float4(screenPos.xy * 2 - 1.0, 1.0, 1.0); //远裁面上的点 逆透视除法，乘上裁剪空间w分量，w又是视角空间的-z
				float4 viewRay = mul(_InverseProjectionMatrix, clipPos);
				o.viewRay = viewRay.xyz / viewRay.w;
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				fixed4 mainTex = tex2D(_MainTex, i.uv);
				float linear01Depth;
				float3 viewNormal;
				
				float4 cdn = tex2D(_CameraDepthNormalsTexture, i.uv);
				DecodeDepthNormal(cdn, linear01Depth, viewNormal);
				//重建视空间坐标
				float3 viewPos = linear01Depth * i.viewRay;
				float3 viewDir = normalize(viewPos);
				viewNormal = normalize(viewNormal);
				//视空间方向反射方向
				float3 reflectDir = reflect(viewDir, viewNormal);
				float2 hitScreenPos = float2(0,0);
				//从该点开始RayMarching
				if (viewSpaceRayMarching(viewPos, reflectDir, hitScreenPos))
				{
					float4 reflectTex = tex2D(_MainTex, hitScreenPos);
					mainTex.rgb += reflectTex.rgb;
				}
				return mainTex;
			}
			
			ENDCG
		}
	}

}