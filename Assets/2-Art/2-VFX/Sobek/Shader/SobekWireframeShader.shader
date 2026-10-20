Shader "Custom/URP/SobekStandaloneVR_Quads_RootDissolve"
{
    Properties
    {
        [HDR] _BaseColour ("Base Colour", Color) = (0.15, 0.9, 1.2, 1)
        _BaseOpacity ("Base Opacity", Range(0, 1)) = 0.10

        [HDR] _FresnelColour ("Fresnel Colour", Color) = (0.4, 1.2, 2.0, 1)
        _FresnelPower ("Fresnel Power", Range(0.1, 8.0)) = 3.0
        _FresnelIntensity ("Fresnel Intensity", Range(0, 8)) = 2.0

        [HDR] _WireframeColour ("Wireframe Colour", Color) = (0.65, 1.5, 2.5, 1)
        _WireframeScale ("Wireframe Scale", Range(0.5, 6.0)) = 1.5
        _WireframeOpacity ("Wireframe Opacity", Range(0, 1)) = 1.0

        _DissolveHeight ("Dissolve Height", Float) = 0.0
        _DissolveSoftness ("Dissolve Softness", Range(0.001, 2.0)) = 0.25
        _DissolvePower ("Dissolve Power", Range(0.1, 8.0)) = 1.0
        _DissolveAxis ("Dissolve Axis (Root Space)", Vector) = (0, 0, 1, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Transparent"
            "RenderType"="Transparent"
            "IgnoreProjector"="True"
        }

        Pass
        {
            Name "SobekForward"
            Tags { "LightMode"="SRPDefaultUnlit" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColour;
                float _BaseOpacity;

                half4 _FresnelColour;
                float _FresnelPower;
                float _FresnelIntensity;

                half4 _WireframeColour;
                float _WireframeScale;
                float _WireframeOpacity;

                float _DissolveHeight;
                float _DissolveSoftness;
                float _DissolvePower;
                float4 _DissolveAxis;
            CBUFFER_END

            // Esta matriz la inyecta el script por renderer.
            float4x4 _DissolveRootWorldToLocal;

            struct Attributes
            {
                float4 positionOS     : POSITION;
                float3 normalOS       : NORMAL;
                float3 barycentric    : TEXCOORD2;
                float3 edgeVisibility : TEXCOORD3;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS     : SV_POSITION;
                float3 positionWS     : TEXCOORD0;
                float3 normalWS       : TEXCOORD1;
                float3 barycentric    : TEXCOORD2;
                float3 edgeVisibility : TEXCOORD3;
                float3 positionRS     : TEXCOORD4; // Root-space compartido

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS = normalInputs.normalWS;
                OUT.barycentric = IN.barycentric;
                OUT.edgeVisibility = IN.edgeVisibility;

                // Convertimos la posición mundial del vértice al espacio local del root común.
                OUT.positionRS = mul(_DissolveRootWorldToLocal, float4(posInputs.positionWS, 1.0)).xyz;

                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                float axisLen = max(length(_DissolveAxis.xyz), 1e-5);
                float3 dissolveAxis = _DissolveAxis.xyz / axisLen;

                float axisPos = dot(IN.positionRS, dissolveAxis);

                float dissolve = smoothstep(
                    _DissolveHeight - _DissolveSoftness,
                    _DissolveHeight + _DissolveSoftness,
                    axisPos
                );

                dissolve = pow(saturate(dissolve), _DissolvePower);

                clip(dissolve - 0.001);

                float3 N = normalize(IN.normalWS);
                float3 V = normalize(GetCameraPositionWS() - IN.positionWS);

                float fresnel = pow(saturate(1.0 - dot(N, V)), _FresnelPower) * _FresnelIntensity;

                float3 bary = IN.barycentric;
                float3 fw = max(fwidth(bary), float3(1e-5, 1e-5, 1e-5));

                float3 edgeLine = 1.0 - smoothstep(
                    fw * _WireframeScale,
                    fw * (_WireframeScale + 1.0),
                    bary
                );

                edgeLine *= IN.edgeVisibility;

                float edgeMask = saturate(max(edgeLine.x, max(edgeLine.y, edgeLine.z)));

                float3 baseCol    = _BaseColour.rgb;
                float3 fresnelCol = _FresnelColour.rgb * fresnel;
                float3 wireCol    = _WireframeColour.rgb * edgeMask;

                float3 finalRgb = baseCol + fresnelCol + wireCol;

                float baseAlpha    = saturate(_BaseOpacity * _BaseColour.a);
                float fresnelAlpha = saturate(fresnel * _FresnelColour.a * 0.35);
                float wireAlpha    = saturate(edgeMask * _WireframeOpacity);

                float finalAlpha = saturate(baseAlpha + fresnelAlpha + wireAlpha);

                finalRgb *= dissolve;
                finalAlpha *= dissolve;

                return half4(finalRgb, finalAlpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}