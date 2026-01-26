//================

struct appdata
{
    float4 vertex:POSITION;
    float2 uv:TEXCOORD0;
};

//================

struct v2f
{
    float4 vertex:SV_POSITION;
    float2 uv:TEXCOORD0;
};

//这里是Dual Kawase，需要增加uv
struct v2f_DualBlurDown
{
    float4 vertex:POSITION;
    float2 uv[5]:TEXCOORD0;
};

struct v2f_DualBlurUp
{
    float2 uv[8]:TEXCOORD0;
    float4 vertex:SV_POSITION;
};


//================

sampler2D _MainTex;
float4 _MainTex_ST;

sampler2D _CameraDepthTexture;

sampler2D _OriginalTex; // 原始图像

float _FogHalfLifeDistance;

float4 _ColorTint;
float _BlurRange;
float _RTDownSampling;

float blurrange;
float blurrange_x;
float blurrange_y;

float4 _MainTex_TexelSize;

int _CustomPointLightCount;
uniform float4 _CustomPointLightPositions[8];

v2f ColorTintVert (appdata v)
{
    v2f o;
    o.vertex = TransformObjectToHClip(v.vertex.xyz);
    o.uv = v.uv;
    return o;
}

//【ColorTint】正片叠底
float4 ColorTintFrag (v2f i):SV_TARGET
{
    float4 col = tex2D(_MainTex, i.uv);
    float depth = tex2D(_CameraDepthTexture, i.uv).r;
    float linearEyeDepth = LinearEyeDepth(depth, _ZBufferParams);
    float attenuation = 1.0 - exp2(-linearEyeDepth / _FogHalfLifeDistance);
    //float4 col = float4(depth, depth, depth, 1);
    col.a = attenuation;
    return col;
}

//【高斯模糊的垂直、水平猴版卷积核】
//严格意义上来说，得逐像素卷积
//也可以写两个frag，带来两个pass，一个vertical，一个horizonal。线性近似里，这样9个权重变成3个
//越大的filter，越费
//5x5的带宽和kawase差不多，但dual在这个基础上还能省50%

#define SMALL_KERNEL 7
#define MEDIUM_KERNEL 35
#define BIG_KERNEL 127 //实时渲染别想用这玩意儿



//【Kawase滤波】(Kawase Blur)
//具体思路是在runtime层，基于当前迭代次数，对每次模糊的半径进行设置，半径越来越大；而Shader层实现一个4 tap的Kawase Filter即可：
    float4 KawaseBlurFrag (v2f i):SV_TARGET
{
    float4 col = tex2D(_MainTex, i.uv);
    blurrange = _BlurRange;

    col += tex2D(_MainTex, i.uv + float2(-1, -1) * blurrange * _MainTex_TexelSize.xy) ;
    col += tex2D(_MainTex, i.uv + float2(1, -1) * blurrange * _MainTex_TexelSize.xy) ;
    col += tex2D(_MainTex, i.uv + float2(-1, 1) * blurrange * _MainTex_TexelSize.xy) ;
    col += tex2D(_MainTex, i.uv + float2(1, 1) * blurrange * _MainTex_TexelSize.xy) ;
    //对目标像素、周围4个对角位置的像素采样，共5个
    
    return col * 0.2;
}

//【双重模糊】(Dual Blur)
// 它相比于Kawasel滤波，有一个降采样 & 升采样的过程，叫做Dual Kawase Blur。降采样和升采样使用不同的pass
    v2f_DualBlurDown DualBlurDownVert (appdata v)
{
    //降采样
    v2f_DualBlurDown o;
    o.vertex = TransformObjectToHClip(v.vertex.xyz);
    o.uv[0] = v.uv;

#if UNITY_UV_STARTS_TOP
    o.uv[0].y = 1 - o.uv[0].y;
#endif
	//
    o.uv[1] = v.uv + float2(-1, -1)  * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5; //↖
	o.uv[2] = v.uv + float2(-1,  1)  * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5; //↙
	o.uv[3] = v.uv + float2(1,  -1)  * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5; //↗
	o.uv[4] = v.uv + float2(1,   1)  * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5; //↘
	//
    return o;
    //5 samples，组成一个五筒
}

float4 DualBlurDownFrag (v2f_DualBlurDown i):SV_TARGET
{
    //降采样
    float4 col = tex2D(_MainTex, i.uv[0]) * 4;

    col += tex2D(_MainTex, i.uv[1]) ;
    col += tex2D(_MainTex, i.uv[2]) ;
    col += tex2D(_MainTex, i.uv[3]) ;
    col += tex2D(_MainTex, i.uv[4]) ;
    
    return col * 0.125; //sum / 8.0f
}

    v2f_DualBlurUp DualBlurUpVert (appdata v)
{
    //升采样
    v2f_DualBlurUp o;
    o.vertex = TransformObjectToHClip(v.vertex.xyz);
    o.uv[0] = v.uv;

#if UNITY_UV_STARTS_TOP
    o.uv[0].y = 1 - o.uv[0].y;
#endif
	//
	o.uv[0] = v.uv + float2(-1,-1) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[1] = v.uv + float2(-1, 1) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[2] = v.uv + float2(1, -1) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[3] = v.uv + float2(1,  1) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[4] = v.uv + float2(-2, 0) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[5] = v.uv + float2(0, -2) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[6] = v.uv + float2(2,  0) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
	o.uv[7] = v.uv + float2(0,  2) * (1 + _BlurRange) * _MainTex_TexelSize.xy * 0.5;
    //
    return o;
}

float4 DualBlurUpFrag (v2f_DualBlurUp i):SV_TARGET
{
    //升采样
    float4 col = 0;

    col += tex2D(_MainTex, i.uv[0]) * 2;
    col += tex2D(_MainTex, i.uv[1]) * 2;
    col += tex2D(_MainTex, i.uv[2]) * 2;
    col += tex2D(_MainTex, i.uv[3]) * 2;
    col += tex2D(_MainTex, i.uv[4]) ;
    col += tex2D(_MainTex, i.uv[5]) ;
    col += tex2D(_MainTex, i.uv[6]) ;
    col += tex2D(_MainTex, i.uv[7]) ;

    return col * 0.0833; //sum / 12.0f
}

//Dual Blur End

v2f MixVert (appdata v)
{
    v2f o;
    o.vertex = TransformObjectToHClip(v.vertex.xyz);
    o.uv = v.uv;
    return o;
}

float4 MixFrag (v2f i):SV_TARGET
{
    float4 col = tex2D(_MainTex, i.uv);
    float alp = col.a;
    float4 originalCol = tex2D(_OriginalTex, i.uv);
    float4 mistyColor = _ColorTint;
    float depth = tex2D(_CameraDepthTexture, i.uv).r;
    //float linearEyeDepth = LinearEyeDepth(depth, _ZBufferParams);
    //float halfLifeDistance = _FogHalfLifeDistance;
    //float attenuation = 1.0 - exp2(-linearEyeDepth / halfLifeDistance);

    // 重建世界位置
    float3 worldPos = ComputeWorldSpacePosition(i.uv, depth, UNITY_MATRIX_I_VP);
    // 摄像机方向
    float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);
    Light mainLight = GetMainLight();

    // Sun light
    float dotSun = dot(viewDir, mainLight.direction);
    float dotSunPlus = dotSun * 0.5 + 0.5;
    dotSunPlus = pow(dotSunPlus, 2);

    // Multi light support (optional)
    int addLightsCount = GetAdditionalLightsCount();
    float4 addcolor = float4(0,0,0,0);
    for (int lt = 0; lt < addLightsCount; lt++)
    {
        Light addlight = GetAdditionalLight(lt, worldPos); // 获取每个额外光源的信息
        float3 lightPos_w = _CustomPointLightPositions[lt];
        float3 lightPos_v = mul(unity_WorldToCamera, float4(lightPos_w,1)).xyz;
        float4 lightPos_c = mul(unity_CameraProjection, float4(lightPos_v,1));
        float3 lightPos = lightPos_c.xyz / -lightPos_c.w;
        lightPos = lightPos * 0.5 + 0.5;
        lightPos.z=0;
        // Z: near=1, far=0
        float strength = 80.0;
        float distance = length(float3(i.uv, 0)*strength - lightPos*strength);
        addcolor += 1.0/(distance*distance + 1.0);
        //return float4(lightPos_w, 1);
    }

    mistyColor = 1.0 - (1.0 - mistyColor) * (1.0 - dotSunPlus*0.2);
    mistyColor *= alp * dotSun * 0.5 + 0.5;

    col = lerp(originalCol, col, alp*alp); //blur mix
    col = lerp(col, mistyColor, alp); //color tint mix

    //if(_CustomPointLightCount<3)return float4(1,0,0,1);
    
    return col+addcolor;
}