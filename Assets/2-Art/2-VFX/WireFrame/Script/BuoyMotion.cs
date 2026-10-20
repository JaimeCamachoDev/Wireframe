using UnityEngine;

/// Simula una boya: bobbing vertical + balanceo suave (pendulum) con variación por Perlin.
/// - No usa físicas. Mantiene la posición/rotación base como referencia.
/// - Si el objeto tiene Rigidbody y quieres que afecte a físicas, usa MovePosition/MoveRotation en FixedUpdate.
[DisallowMultipleComponent]
public class BuoyMotion : MonoBehaviour
{
    [Header("Vertical (sube/baja)")]
    [Tooltip("Altura máxima del vaivén vertical (metros).")]
    public float verticalAmplitude = 0.35f;

    [Tooltip("Ciclos por segundo del movimiento vertical (Hz).")]
    public float verticalFrequency = 0.25f;

    [Tooltip("Cantidad extra de variación (0..1) basada en ruido Perlin.")]
    [Range(0f, 1f)] public float verticalNoise = 0.25f;

    [Header("Rotación (penduleo)")]
    [Tooltip("Grados máximos de pitch (X) y roll (Z).")]
    public Vector2 tiltAmplitudeDegrees = new Vector2(6f, 10f);

    [Tooltip("Ciclos por segundo del balanceo (Hz).")]
    public float tiltFrequency = 0.18f;

    [Tooltip("Suavizado de la rotación. Más alto = responde más rápido.")]
    public float tiltSmoothing = 6f;

    [Tooltip("Variación extra (0..1) basada en ruido Perlin.")]
    [Range(0f, 1f)] public float tiltNoise = 0.35f;

    [Header("Fase / aleatoriedad")]
    [Tooltip("Semilla para desincronizar múltiples boyas.")]
    public int seed = 12345;

    [Tooltip("Offset de fase en segundos (si lo dejas en 0, se deriva de la semilla).")]
    public float phaseOffsetSeconds = 0f;

    Vector3 _basePos;
    Quaternion _baseRot;

    float _phaseA;
    float _phaseB;
    float _perlinOffsetA;
    float _perlinOffsetB;

    void Awake()
    {
        _basePos = transform.position;
        _baseRot = transform.rotation;

        // Derivamos offsets reproducibles con la semilla.
        var rng = new System.Random(seed);
        _phaseA = (float)rng.NextDouble() * 1000f;
        _phaseB = (float)rng.NextDouble() * 1000f;
        _perlinOffsetA = (float)rng.NextDouble() * 1000f;
        _perlinOffsetB = (float)rng.NextDouble() * 1000f;

        if (phaseOffsetSeconds == 0f)
            phaseOffsetSeconds = (float)rng.NextDouble() * 10f;
    }

    void OnEnable()
    {
        // Re-captura base si recolocas en runtime
        _basePos = transform.position;
        _baseRot = transform.rotation;
    }

    void Update()
    {
        float t = Time.time + phaseOffsetSeconds;

        // --- Vertical ---
        float wV = Mathf.PI * 2f * verticalFrequency;
        float sinV = Mathf.Sin(wV * t + _phaseA);

        // Perlin en [-1,1]
        float pV = (Mathf.PerlinNoise(_perlinOffsetA, t * verticalFrequency * 0.7f) * 2f) - 1f;

        float yOffset = verticalAmplitude * (sinV + pV * verticalNoise);

        // --- Tilt (pendulum) ---
        float wT = Mathf.PI * 2f * tiltFrequency;

        float sinPitch = Mathf.Sin(wT * t + _phaseB);
        float sinRoll = Mathf.Sin(wT * t * 0.93f + _phaseB + 1.7f); // ligera desincronización

        float pPitch = (Mathf.PerlinNoise(_perlinOffsetB, t * tiltFrequency * 0.8f) * 2f) - 1f;
        float pRoll = (Mathf.PerlinNoise(_perlinOffsetB + 10.1f, t * tiltFrequency * 0.8f) * 2f) - 1f;

        float pitch = tiltAmplitudeDegrees.x * (sinPitch + pPitch * tiltNoise);
        float roll = tiltAmplitudeDegrees.y * (sinRoll + pRoll * tiltNoise);

        // Aplica posición
        Vector3 pos = _basePos;
        pos.y += yOffset;
        transform.position = pos;

        // Aplica rotación suave alrededor de la rotación base
        Quaternion targetTilt = _baseRot * Quaternion.Euler(pitch, 0f, roll);
        transform.rotation = Quaternion.Slerp(transform.rotation, targetTilt, 1f - Mathf.Exp(-tiltSmoothing * Time.deltaTime));
    }
}
