Shader "Unlit/WireframeShader"
{
    Properties
    {
        [HDR] _WireframeColour ("Wireframe Colour", Color) = (1, 1, 1, 1)
        _WireframeScale ("Wireframe Scale", Float) = 1.5
        _WireframeOpacity ("Wireframe Opacity", Range(0, 1)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100

        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Cull Off
            ZWrite Off

            CGPROGRAM
            #pragma target 4.0
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;

                // Necesario para que Unity pueda identificar la instancia/eye actual
                // cuando XR usa Single Pass Instanced o Multiview.
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // Del vertex al geometry: guardamos la posicion en object space porque
            // el geometry shader necesita calcular las aristas antes de proyectar.
            struct v2g
            {
                float4 vertexOS : TEXCOORD0;

                // El geometry shader necesita recibir el instance ID y el dato stereo
                // para reconstruir correctamente unity_StereoEyeIndex antes de emitir vertices.
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
                float3 barycentric : TEXCOORD0;

                // Este campo indica a que ojo / slice del render target array va cada vertice.
                UNITY_VERTEX_OUTPUT_STEREO
            };

            fixed4 _WireframeColour;
            float _WireframeScale;
            float _WireframeOpacity;

            v2g vert(appdata v)
            {
                v2g o;

                // Inicializa el instance ID de Unity. En XR single-pass, Unity usa
                // este dato para derivar unity_StereoEyeIndex.
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2g, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertexOS = v.vertex;
                return o;
            }

            [maxvertexcount(3)]
            void geom(triangle v2g IN[3], inout TriangleStream<g2f> triStream)
            {
                // Punto clave para VR:
                // UnityObjectToClipPos se ejecuta aqui, no en el vertex shader.
                // Por tanto el geometry shader debe restaurar el instance/stereo eye
                // antes de calcular posiciones en clip space.
                UNITY_SETUP_INSTANCE_ID(IN[0]);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN[0]);

                float3 modifier = float3(0.0, 0.0, 0.0);

                // Calcula la longitud de cada arista del triangulo en object space.
                // La arista mas larga se considera la diagonal interna del quad y se
                // oculta sumando +1 a esa coordenada barycentric.
                float edgeLength0 = distance(IN[1].vertexOS.xyz, IN[2].vertexOS.xyz); // opuesta al vertice 0
                float edgeLength1 = distance(IN[0].vertexOS.xyz, IN[2].vertexOS.xyz); // opuesta al vertice 1
                float edgeLength2 = distance(IN[0].vertexOS.xyz, IN[1].vertexOS.xyz); // opuesta al vertice 2

                if ((edgeLength0 > edgeLength1) && (edgeLength0 > edgeLength2))
                {
                    modifier = float3(1.0, 0.0, 0.0);
                }
                else if ((edgeLength1 > edgeLength0) && (edgeLength1 > edgeLength2))
                {
                    modifier = float3(0.0, 1.0, 0.0);
                }
                else if ((edgeLength2 > edgeLength0) && (edgeLength2 > edgeLength1))
                {
                    modifier = float3(0.0, 0.0, 1.0);
                }

                g2f o;

                UNITY_INITIALIZE_OUTPUT(g2f, o);
                UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(IN[0], o);
                o.pos = UnityObjectToClipPos(IN[0].vertexOS);
                o.barycentric = float3(1.0, 0.0, 0.0) + modifier;
                triStream.Append(o);

                UNITY_INITIALIZE_OUTPUT(g2f, o);
                UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(IN[1], o);
                o.pos = UnityObjectToClipPos(IN[1].vertexOS);
                o.barycentric = float3(0.0, 1.0, 0.0) + modifier;
                triStream.Append(o);

                UNITY_INITIALIZE_OUTPUT(g2f, o);
                UNITY_TRANSFER_VERTEX_OUTPUT_STEREO(IN[2], o);
                o.pos = UnityObjectToClipPos(IN[2].vertexOS);
                o.barycentric = float3(0.0, 0.0, 1.0) + modifier;
                triStream.Append(o);

                triStream.RestartStrip();
            }

            fixed4 frag(g2f i) : SV_Target
            {
                // No usamos unity_StereoEyeIndex aqui, pero inicializarlo en fragment
                // mantiene el shader compatible si mas adelante se depura por ojo.
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                // Modo BASIC del shader original:
                // grosor dependiente del tamano del triangulo en pantalla.
                float closest = min(i.barycentric.x, min(i.barycentric.y, i.barycentric.z));
                float edgeMask = step(closest, _WireframeScale / 20.0);

                float alpha = edgeMask * saturate(_WireframeOpacity);

                return fixed4(_WireframeColour.rgb, alpha);
            }
            ENDCG
        }
    }
}