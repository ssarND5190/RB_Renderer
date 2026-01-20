using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace IGame.Core.Util
{
    /// <summary>
    /// BlurTool : 模糊工具。
    /// </summary>
    public class BlurTool : MonoBehaviour
    {
        public static Material blurMaterial;

        // 模糊迭代次数
        public static readonly int ITERATION_COUNT = 3;

        // 模糊强度
        public static readonly float BLUR_SPREAD = 0.6f;

        // 降采样次数
        public static readonly int DOWN_SAMPLE = 2;

        // 高斯核尺寸
        public static readonly float BLUR_SIZE = 1.0f;

        public static readonly FilterMode downSampleFilter = FilterMode.Bilinear;

        public static readonly FilterMode blurFilter = FilterMode.Point;

        private static void InitBlurMaterial()
        {
            Shader blurShader = Shader.Find("IGame/GaussBlur");
            if (blurShader != null && blurShader.isSupported)
            {
                blurMaterial = new Material(blurShader);
                blurMaterial.hideFlags = HideFlags.DontSave;
            }
            else
            {
                Debug.LogError($"初始化高斯模糊Shader失败!");
            }
        }

        // 对render texture进行高斯模糊。
        public static RenderTexture BlurRenderTexture(RenderTexture sourceTexture,
            int downSample = -1, int iterationCount = -1, float blurSpread = -1, float blurSize = -1)
        {
            // 1.初始化高斯模糊材质
            if (blurMaterial == null)
            {
                InitBlurMaterial();
            }

            if (blurMaterial == null || sourceTexture == null)
            {
                return sourceTexture;
            }

            int sample = downSample >= 0 ? downSample : DOWN_SAMPLE;
            int iteration = iterationCount > 0 ? iterationCount : ITERATION_COUNT;
            float spread = blurSpread >= 0 ? blurSpread : BLUR_SPREAD;
            float size = blurSize > 0 ? blurSize : BLUR_SIZE;

            // 2.降低采样次数
            int renderTextureWidth = sourceTexture.width;
            int renderTextureHeight = sourceTexture.height;

            for (int i = 0; i < sample; i++)
            {
                renderTextureWidth /= 2;
                renderTextureHeight /= 2;
            }

            renderTextureWidth = Mathf.Max(renderTextureWidth, 1);
            renderTextureHeight = Mathf.Max(renderTextureHeight, 1);

            // 3.创建高斯模糊所需的两张render texture缓冲
            //      首张缓冲RT需要赋初值为降采样之后的原始图像
            RenderTexture bufferRT1 = RenderTexture.GetTemporary(
                renderTextureWidth, renderTextureHeight, 0, sourceTexture.format
            );
            bufferRT1.filterMode = downSampleFilter;
            Graphics.Blit(sourceTexture, bufferRT1);

            RenderTexture bufferRT2 = RenderTexture.GetTemporary(
                renderTextureWidth, renderTextureHeight, 0, sourceTexture.format
            );
            bufferRT1.filterMode = blurFilter;
            bufferRT2.filterMode = blurFilter;

            // 4.使用两张render texture缓冲, 交替进行高斯模糊迭代
            try
            {
                for (int i = 0; i < iteration; i++)
                {
                    float currentBlurSize = size * (1.0f + i * spread);
                    blurMaterial.SetFloat("_BlurSize", currentBlurSize);

                    // 纵向模糊
                    Graphics.Blit(bufferRT1, bufferRT2, blurMaterial, 0);

                    // 横向模糊
                    Graphics.Blit(bufferRT2, bufferRT1, blurMaterial, 1);
                }

                // 恢复双线性过滤
                bufferRT1.filterMode = FilterMode.Bilinear;
                RenderTexture.ReleaseTemporary(bufferRT2);
            }
            catch (Exception e)
            {
                Debug.LogError($"模糊处理失败: {e.Message}");

                RenderTexture.ReleaseTemporary(bufferRT1);
                RenderTexture.ReleaseTemporary(bufferRT2);

                return sourceTexture;
            }

            return bufferRT1;
        }

        // 使用完模糊之后, 记得释放模糊纹理。
        public static void ReleaseBlurTexture(RenderTexture blurTexture)
        {
            if (blurTexture == null)
            {
                return;
            }

            RenderTexture.ReleaseTemporary(blurTexture);
        }
    }
}