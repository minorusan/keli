using UnityEngine;
using UnityEngine.UI;

namespace Maradel.Content
{
    /// <summary>
    /// Drives a filled <see cref="Image"/> (Image Type = Filled) from <see cref="DownloadProgress"/>.
    /// Responds to download events by setting <c>image.fillAmount</c>. Auto-hides when idle.
    /// Drop on a Canvas; assign the fill Image (+ optional label Text).
    /// </summary>
    [AddComponentMenu("Maradel/Download Progress View")]
    public sealed class DownloadProgressView : MonoBehaviour
    {
        [Tooltip("Image with Image Type = Filled; its fillAmount is set to the download progress.")]
        [SerializeField] Image fillImage;
        [Tooltip("Optional label (TMP or legacy via a setter). Left as Text for simplicity.")]
        [SerializeField] Text label;
        [Tooltip("Root to show/hide with the download (defaults to this GameObject).")]
        [SerializeField] GameObject root;
        [Tooltip("Keep visible briefly after completion.")]
        [SerializeField] float hideDelay = 0.5f;

        float _idleTimer;

        void Reset() { root = gameObject; }

        void Update()
        {
            if (root == null) root = gameObject;

            if (DownloadProgress.Active)
            {
                _idleTimer = 0f;
                if (!root.activeSelf) root.SetActive(true);
                if (fillImage != null) fillImage.fillAmount = DownloadProgress.Value01;
                if (label != null) label.text = $"{DownloadProgress.Label}  {DownloadProgress.Value01 * 100f:0}%  {DownloadProgress.SizeText}";
            }
            else
            {
                if (fillImage != null) fillImage.fillAmount = DownloadProgress.Value01;
                _idleTimer += Time.deltaTime;
                if (_idleTimer >= hideDelay && root.activeSelf) root.SetActive(false);
            }
        }
    }
}
