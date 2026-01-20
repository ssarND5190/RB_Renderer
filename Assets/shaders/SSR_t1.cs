using System.Collections;
using System.Collections.Generic;
using UnityEngine;
[ExecuteInEditMode]
public class ScreenReflectionBase : MonoBehaviour
{
    Material reflectionMaterial = null;
    public Camera currentCamera = null;
    [Range(0, 1000.0f)]
    public float maxRayMarchingDistance = 500.0f;
    [Range(0, 256)]
    public int maxRayMarchingStep = 64;
    [Range(0, 2.0f)]
    public float rayMarchingStepSize = 0.05f;
    [Range(0, 2.0f)]
    public float depthThickness = 0.01f;
    private void Awake()
    {
        var shader = Shader.Find("Reflection/ScreenReflectionBase");
        reflectionMaterial = new Material(shader);
    }
 
    private void OnEnable()
    {
        currentCamera.depthTextureMode |= DepthTextureMode.DepthNormals;    
    }
 
    private void OnDisable()
    {
        currentCamera.depthTextureMode &= ~DepthTextureMode.DepthNormals;
    }
 
    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (reflectionMaterial == null)
        {
            Graphics.Blit(source, destination);
            return;
        }
 
        reflectionMaterial.SetMatrix("_InverseProjectionMatrix", currentCamera.projectionMatrix.inverse);
        reflectionMaterial.SetMatrix("_CameraProjectionMatrix", currentCamera.projectionMatrix);
        reflectionMaterial.SetFloat("_maxRayMarchingDistance", maxRayMarchingDistance);
        reflectionMaterial.SetFloat("_maxRayMarchingStep", maxRayMarchingStep);
        reflectionMaterial.SetFloat("_rayMarchingStepSize", rayMarchingStepSize);
        reflectionMaterial.SetFloat("_depthThickness", depthThickness);
        Graphics.Blit(source, destination, reflectionMaterial, 0);
    }
 
}